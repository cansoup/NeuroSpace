"""
EEG Online Classification Pipeline — NeuroSpace
=======================================================
Requirements from Stanley:
  - Stream EEG via LSL (or replay XDF via XDFStreamer)
  - Preprocess: notch 50 Hz, then low-pass 100 Hz
  - Classify with EEGNet (3-class MI: left, right, both hands)
  - Post-process: sliding window + majority vote
  - Send classification output back as LSL stream for the app

Event markers (from XDF dataset):
  768  → Trial start
  769  → Left hand MI cue
  770  → Right hand MI cue
  773  → Both hands MI cue
  782  → MI cue end

Channels used: index 2, 3, 5 (i.e. channels 3, 4, 6)

Usage:
  # Option A – live headset
  python eeg_online_classifier.py --model eegnet_weights.pt

  # Option B – replay XDF file (requires XDFStreamer running first)
  python eeg_online_classifier.py --model eegnet_weights.pt --xdf path/to/visionpro-ml.xdf

  # Option C – train on XDF data first
  python eeg_online_classifier.py --train path/to/visionpro-ml.xdf

"""

import time
import argparse
import numpy as np
from collections import deque

import torch
import torch.nn as nn
from scipy.signal import butter, lfilter, lfilter_zi, filtfilt, iirnotch
from pylsl import StreamInfo, StreamInlet, StreamOutlet, resolve_byprop

# ─────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────
SRATE          = 250          # Hz – must match headset
# [FIX-18] ch5 is saturated (~2.6M offset) — replaced with active motor-cortex channels
CHANNELS       = [0, 1, 3, 4]   # 0-indexed — C3/C4 area (active EEG)
N_CHANNELS     = len(CHANNELS)
WINDOW_SEC     = 2.5          # [FIX-7] was 4.0 — shorter = more epochs, less overfit
STEP_SEC       = 0.5          # sliding window step
VOTE_WINDOW    = 3            # [FIX-16] was 5 — smaller window surfaces real class variation faster
# LOWPASS_HZ removed — [FIX-19] replaced by 8-30 Hz bandpass in filter design
NOTCH_HZ       = 50.0

# [FIX-17] CLASSES and N_CLASSES are no longer module-level constants.
# They are detected from the XDF at train time and stored in the checkpoint,
# then restored by load_model() for inference.  The defaults below are only
# used if a model is loaded without a saved class map (e.g. legacy checkpoints).
ALL_MARKERS = {769: "left", 770: "right", 773: "both"}   # all possible MI markers
DEFAULT_CLASSES = {0: "left", 1: "right", 2: "both"}     # fallback for legacy .pt

WINDOW_SAMPLES = int(WINDOW_SEC * SRATE)   # 625
STEP_SAMPLES   = int(STEP_SEC   * SRATE)   # 125


# ─────────────────────────────────────────────
# FILTER DESIGN
# ─────────────────────────────────────────────

def butter_bandpass(lo, hi, fs, order=4):
    # [FIX-19] Bandpass to isolate mu (8-12 Hz) + beta (13-30 Hz) MI bands
    nyq = 0.5 * fs
    b, a = butter(order, [lo / nyq, hi / nyq], btype='band')
    return b, a

def design_notch(freq, fs, Q=30):
    b, a = iirnotch(freq / (0.5 * fs), Q)
    return b, a

_bp_b,    _bp_a    = butter_bandpass(8.0, 30.0, SRATE)   # [FIX-19] mu+beta bandpass
_notch_b, _notch_a = design_notch(NOTCH_HZ, SRATE)


# ─────────────────────────────────────────────
# PREPROCESSING
# ─────────────────────────────────────────────

def preprocess(data: np.ndarray, zero_phase: bool = False) -> np.ndarray:
    """
    data       : (n_samples, n_channels) float32
    zero_phase : use filtfilt (offline/training) vs lfilter (online, causal)
    returns filtered array of same shape

    [FIX-3]  Notch applied BEFORE bandpass (correct order).
    [FIX-4]  zero_phase=True uses filtfilt to avoid phase distortion in training.
    [FIX-19] Bandpass 8-30 Hz isolates mu+beta MI bands — replaces lowpass-only.
    """
    filt = filtfilt if zero_phase else lfilter
    # 1. Notch at 50 Hz (powerline artefact)
    out = filt(_notch_b, _notch_a, data, axis=0)
    # 2. Bandpass 8-30 Hz — keeps mu (8-12 Hz) and beta (13-30 Hz) only
    out = filt(_bp_b, _bp_a, out, axis=0)
    # 3. Per-channel z-score normalisation
    out = (out - out.mean(axis=0)) / (out.std(axis=0) + 1e-8)
    return out.astype(np.float32)


# ─────────────────────────────────────────────
# DATA AUGMENTATION  [FIX-11]
# ─────────────────────────────────────────────

def augment(X: np.ndarray, noise_std: float = 0.08,
            max_shift: int = 40) -> np.ndarray:
    """
    X : (n, 1, ch, time)
    [FIX-19] Extended augmentation for small datasets (90 trials):
      - Gaussian noise
      - Random time-shift
      - Random amplitude scaling per channel (±20%)
      - Random channel dropout (zero out 1 channel 30% of the time)
    """
    X = X.copy()
    n = X.shape[0]
    n_ch = X.shape[2]

    # Gaussian noise
    X += np.random.randn(*X.shape).astype(np.float32) * noise_std

    # Random time-shift
    shifts = np.random.randint(-max_shift, max_shift + 1, size=n)
    for i, s in enumerate(shifts):
        X[i] = np.roll(X[i], s, axis=-1)

    # Amplitude scaling: each channel scaled by U(0.8, 1.2)
    scales = np.random.uniform(0.8, 1.2, size=(n, 1, n_ch, 1)).astype(np.float32)
    X *= scales

    # Channel dropout: randomly zero one channel per sample (30% chance)
    for i in range(n):
        if np.random.rand() < 0.30:
            ch = np.random.randint(n_ch)
            X[i, 0, ch, :] = 0.0

    return X


# ─────────────────────────────────────────────
# EEGNet
# ─────────────────────────────────────────────

class EEGNet(nn.Module):
    """
    EEGNet — Lawhern et al., 2018  https://doi.org/10.1088/1741-2552/aace8c
    Input  : (batch, 1, n_channels, n_samples)
    Output : (batch, n_classes)

    [FIX-1] block2 is now a true depthwise-separable convolution.
    [FIX-2] flat_size computed by a dry-run, not n_samples // 32.
    [FIX-6] default dropout raised to 0.5.
    """
    def __init__(self, n_classes=3, n_channels=3, n_samples=625,
                 F1=4, D=2, F2=8, kern_len=64, dropout=0.6):  # [FIX-19] smaller+more dropout for 90-trial dataset
        super().__init__()

        self.block1 = nn.Sequential(
            # Temporal convolution
            nn.Conv2d(1, F1, (1, kern_len), padding=(0, kern_len // 2), bias=False),
            nn.BatchNorm2d(F1),
            # Depthwise spatial convolution
            nn.Conv2d(F1, F1 * D, (n_channels, 1), groups=F1, bias=False),
            nn.BatchNorm2d(F1 * D),
            nn.ELU(),
            nn.AvgPool2d((1, 4)),
            nn.Dropout(dropout),
        )

        # [FIX-1] True depthwise-separable conv:
        #   step 1 — depthwise  (groups = F1*D, one filter per channel)
        #   step 2 — pointwise  (1×1 conv to mix channels)
        self.block2 = nn.Sequential(
            nn.Conv2d(F1 * D, F1 * D, (1, 16), padding=(0, 8),
                      groups=F1 * D, bias=False),          # depthwise
            nn.Conv2d(F1 * D, F2, (1, 1), bias=False),     # pointwise
            nn.BatchNorm2d(F2),
            nn.ELU(),
            nn.AvgPool2d((1, 8)),
            nn.Dropout(dropout),
        )

        # [FIX-2] Compute flat_size via dry-run — padding shifts make // 32 wrong
        flat_size = self._get_flat_size(n_channels, n_samples)
        self.classifier = nn.Linear(flat_size, n_classes)

    def _get_flat_size(self, n_channels: int, n_samples: int) -> int:
        with torch.no_grad():
            dummy = torch.zeros(1, 1, n_channels, n_samples)
            return self.block2(self.block1(dummy)).flatten(1).shape[1]

    def forward(self, x):
        x = self.block1(x)
        x = self.block2(x)
        return self.classifier(x.flatten(1))


def load_model(model_path=None):
    """
    Returns (model, classes) where classes is e.g. {0: 'left', 1: 'right'}.
    [FIX-17] Checkpoint now stores {'state_dict': ..., 'classes': ...}.
             Legacy checkpoints (bare state_dict) fall back to DEFAULT_CLASSES.
    [FIX-21] Checkpoint may also store 'cfg' (F1/D/kern_len/dropout),
             'window_sec', and 'channels' — used when loading notebook-tuned
             weights whose architecture differs from the defaults below.
    """
    if model_path:
        raw = torch.load(model_path, map_location='cpu')

        # [FIX-17] Support both new format (dict with 'classes') and legacy bare state_dict
        if isinstance(raw, dict) and 'state_dict' in raw:
            state          = raw['state_dict']
            classes        = raw['classes']
            cfg            = raw.get('cfg')           # may be None for legacy .pt
            saved_window   = raw.get('window_sec')
            saved_channels = raw.get('channels')
        else:
            print("[model] WARNING — legacy checkpoint format detected (no class map).")
            print(f"         Assuming DEFAULT_CLASSES: {DEFAULT_CLASSES}")
            state          = raw
            classes        = DEFAULT_CLASSES
            cfg            = None
            saved_window   = None
            saved_channels = None

        # [FIX-21] Cross-check training-time window/channels against online constants.
        if saved_window is not None and float(saved_window) != float(WINDOW_SEC):
            print(f"[model] ERROR — checkpoint trained with WINDOW_SEC={saved_window}s "
                  f"but online WINDOW_SEC={WINDOW_SEC}s.")
            print(f"         Change WINDOW_SEC in this file to match, or retrain.")
            raise SystemExit(1)
        if saved_channels is not None and list(saved_channels) != CHANNELS:
            print(f"[model] ERROR — checkpoint trained on channels={list(saved_channels)} "
                  f"but online CHANNELS={CHANNELS}.")
            raise SystemExit(1)

        n_classes = len(classes)
        if cfg:
            model = EEGNet(n_classes=n_classes, n_channels=N_CHANNELS,
                           n_samples=WINDOW_SAMPLES,
                           F1=cfg['F1'], D=cfg['D'],
                           F2=cfg.get('F2', cfg['F1'] * cfg['D'] * 2),
                           kern_len=cfg['kern_len'],
                           dropout=cfg['dropout'])
            arch_tag = (f"F1={cfg['F1']} D={cfg['D']} "
                        f"kern={cfg['kern_len']} dr={cfg['dropout']}")
        else:
            model    = EEGNet(n_classes=n_classes, n_channels=N_CHANNELS,
                              n_samples=WINDOW_SAMPLES)
            arch_tag = "default"

        # [FIX-13] Stale weights guard — flat_size must match current architecture
        saved_in   = state['classifier.weight'].shape[1]
        current_in = model.classifier.in_features
        if saved_in != current_in:
            print(f"[model] ERROR — weights are incompatible with current architecture.")
            print(f"         Saved flat_size={saved_in}, current flat_size={current_in}.")
            print(f"         This usually means WINDOW_SEC or N_CHANNELS changed since training.")
            print(f"         Retrain:  python eeg_online_classifier.py --train <xdf>")
            raise SystemExit(1)

        model.load_state_dict(state)
        print(f"[model] loaded weights from {model_path}  "
              f"({n_classes}-class: {list(classes.values())}, arch: {arch_tag})")
    else:
        print("[model] WARNING — no weights loaded, using random initialisation.")
        print("         Train first:  python eeg_online_classifier.py --train <xdf>")
        classes = DEFAULT_CLASSES
        model   = EEGNet(n_classes=len(classes), n_channels=N_CHANNELS,
                         n_samples=WINDOW_SAMPLES)

    model.eval()
    return model, classes


# ─────────────────────────────────────────────
# MAJORITY VOTE POST-PROCESSING
# ─────────────────────────────────────────────

class MajorityVoter:
    def __init__(self, window=VOTE_WINDOW, n_classes=3):
        self.buf      = deque(maxlen=window)
        self.n_classes = n_classes

    def update(self, pred: int) -> int:
        self.buf.append(pred)
        counts = np.bincount(list(self.buf), minlength=self.n_classes)
        return int(counts.argmax())


# ─────────────────────────────────────────────
# LSL OUTPUT STREAM
# ─────────────────────────────────────────────

def create_output_stream() -> StreamOutlet:
    info = StreamInfo(
        name='EEG_Classification',
        type='Markers',
        channel_count=1,
        nominal_srate=0,
        channel_format='int32',
        source_id='eegnet_classifier'
    )
    outlet = StreamOutlet(info)
    print("[lsl] output stream 'EEG_Classification' created")
    return outlet


# ─────────────────────────────────────────────
# ONLINE CLASSIFICATION LOOP
# ─────────────────────────────────────────────

def _extract_cue_schedule(xdf_path: str):
    """[FIX-23] Read MI cue timings from the XDF so the classifier can gate on
    them even when XDFStreamer only broadcasts the EEG stream (one stream at a
    time). Returns [(offset_sec, marker_value), ...] sorted by offset, where
    offset is seconds from the first EEG sample."""
    import pyxdf
    streams, _ = pyxdf.load_xdf(xdf_path)
    eeg = next(s for s in streams if s['info']['type'][0] == 'EEG')
    mk  = next(s for s in streams if s['info']['type'][0] == 'Markers')
    eeg_t0 = float(eeg['time_stamps'][0])
    schedule = []
    for mt, mv in zip(mk['time_stamps'], mk['time_series']):
        mval = int(mv[0])
        if mval in ALL_MARKERS:
            schedule.append((float(mt) - eeg_t0, mval))
    schedule.sort()
    return schedule


def run_online(model: EEGNet, outlet: StreamOutlet, classes: dict,
               mock: bool = False, cue_schedule=None):
    """classes: {0: 'left', 1: 'right'} or {0: 'left', 1: 'right', 2: 'both'}

    [FIX-22] Gated on Markers stream when one is available. Output is emitted
             only while we are inside a post-cue window (cue_time .. cue_time +
             WINDOW_SEC + STEP_SEC). Outside that window the model still runs
             silently so the voter stays warm, but nothing is printed or pushed
             — the stream of constant default-class predictions that happens
             during rest state is suppressed.
    [FIX-23] Fallback path when no live Markers stream is available: if
             cue_schedule is provided (via --xdf) we fire synthetic cues based
             on wall-clock elapsed time since the first EEG chunk arrives.
             Assumes the classifier is started BEFORE XDFStreamer starts
             replaying, so first-chunk wallclock ≈ XDF sample 0.
    """
    print("[lsl] looking for EEG stream …")
    streams = resolve_byprop("type", "EEG", timeout=5.0)

    if not streams:
        print("[error] No EEG stream found. Ensure your headset or replayer is active.")
        return

    inlet = StreamInlet(streams[0])
    print(f"[lsl] connected to EEG '{streams[0].name()}'")

    # [FIX-22] Subscribe to the replayer/headset Markers stream (skip our own
    # EEG_Classification output by filtering on source_id).
    mk_inlet = None
    for s in (resolve_byprop("type", "Markers", timeout=3.0) or []):
        if s.source_id() != 'eegnet_classifier':
            mk_inlet = StreamInlet(s)
            print(f"[lsl] connected to Markers '{s.name()}' — cue-gated (live markers)")
            break
    if mk_inlet is None and cue_schedule:
        print(f"[lsl] no live Markers — cue-gated from XDF schedule "
              f"({len(cue_schedule)} cues, "
              f"first @ {cue_schedule[0][0]:.1f}s, last @ {cue_schedule[-1][0]:.1f}s)")
        print( "      Make sure you started this classifier BEFORE hitting play in XDFStreamer.")
    elif mk_inlet is None:
        print("[lsl] no Markers stream and no --xdf — running ungated (every window printed)")

    # [FIX-22] live-marker → training-time label index. Training assigned
    # indices by sorted(marker value), so reconstruct the map from `classes`.
    marker_to_label = {}
    for mval, name in ALL_MARKERS.items():
        for idx, cls_name in classes.items():
            if cls_name == name:
                marker_to_label[mval] = idx

    voter               = MajorityVoter(window=VOTE_WINDOW, n_classes=len(classes))
    ring_buf            = deque(maxlen=WINDOW_SAMPLES)   # holds FILTERED samples
    collected           = 0
    since_last_classify = 0

    # [FIX-24] Persistent per-channel filter state. The online preprocess used
    # to call lfilter() on each 2.5 s window from zero state, which made the
    # first ~0.5 s of every window the filter's ring-down transient. The std
    # of that transient dominated the per-window z-score, squashing the real
    # EEG into noise and freezing the model's output at its prior. By keeping
    # zi across chunks we filter the continuous stream once; only per-window
    # z-scoring happens inside the window.
    zi_notch = np.tile(lfilter_zi(_notch_b, _notch_a),
                       (N_CHANNELS, 1)).T.astype(np.float32)
    zi_bp    = np.tile(lfilter_zi(_bp_b, _bp_a),
                       (N_CHANNELS, 1)).T.astype(np.float32)
    filter_primed = False       # set True after the first warm-up chunk

    # Cue-window state (wall-clock based — OK for 2.5 s intervals).
    cue_time        = None
    cue_true        = None
    stream_start    = None    # [FIX-23] wall-clock at first EEG chunk
    schedule_idx    = 0       # [FIX-23] pointer into cue_schedule
    gated           = mk_inlet is not None or bool(cue_schedule)

    print("[classifier] running — press Ctrl-C to stop")
    with torch.no_grad():
        while True:
            chunk, _ = inlet.pull_chunk(timeout=0.1, max_samples=STEP_SAMPLES)
            if not chunk:
                continue

            if stream_start is None:
                stream_start = time.time()
                if cue_schedule and mk_inlet is None:
                    print(f"[lsl] EEG streaming — T0 locked, schedule armed")

            # [FIX-22] Drain any markers that have arrived since last loop.
            if mk_inlet is not None:
                mk_chunk, _ = mk_inlet.pull_chunk(timeout=0.0)
                for mv in mk_chunk or []:
                    mval = int(mv[0])
                    if mval in marker_to_label:
                        cue_time = time.time()
                        cue_true = marker_to_label[mval]
                        print(f"\n[cue] marker={mval} true={classes[cue_true]}")
            # [FIX-23] Fire scheduled cues whose wall-clock offset has elapsed.
            elif cue_schedule:
                elapsed_total = time.time() - stream_start
                while (schedule_idx < len(cue_schedule)
                       and cue_schedule[schedule_idx][0] <= elapsed_total):
                    offset, mval = cue_schedule[schedule_idx]
                    schedule_idx += 1
                    if mval in marker_to_label:
                        cue_time = time.time()
                        cue_true = marker_to_label[mval]
                        print(f"\n[cue@{offset:6.1f}s] marker={mval} "
                              f"true={classes[cue_true]}")

            raw = np.array(chunk, dtype=np.float32)[:, CHANNELS]

            # [FIX-24] Prime the filter state on the first chunk using its
            # mean as the "steady-state DC" — avoids a large step response
            # at t=0 from the raw DC offset (~1.9e5 on these channels).
            if not filter_primed:
                dc = raw.mean(axis=0)
                zi_notch = zi_notch * dc                # scale by per-channel DC
                zi_bp    = zi_bp    * dc
                filter_primed = True

            # [FIX-24] Causal notch + bandpass with state preserved across chunks.
            notched, zi_notch = lfilter(_notch_b, _notch_a, raw,
                                        axis=0, zi=zi_notch)
            filtered, zi_bp   = lfilter(_bp_b, _bp_a, notched,
                                        axis=0, zi=zi_bp)

            ring_buf.extend(filtered.astype(np.float32).tolist())
            collected           += len(filtered)
            since_last_classify += len(filtered)

            if collected < WINDOW_SAMPLES:
                continue
            if since_last_classify < STEP_SAMPLES:
                continue
            since_last_classify = 0

            win = np.array(ring_buf, dtype=np.float32)

            if mock:
                n     = len(classes)
                pred  = int(np.random.randint(n))
                probs = np.random.dirichlet(np.ones(n)).tolist()
            else:
                # [FIX-24] Filtering is already done upstream — just z-score.
                win    = (win - win.mean(axis=0)) / (win.std(axis=0) + 1e-8)
                t      = torch.tensor(win.T[None, None, :, :])
                logits = model(t)
                probs  = torch.softmax(logits, dim=1).squeeze().tolist()
                if isinstance(probs, float):
                    probs = [probs]
                pred   = int(logits.argmax(dim=1).item())

            voted = voter.update(pred)
            label = classes[voted]

            # [FIX-22/23] Decide whether to emit this prediction.
            if gated:
                if cue_time is None:
                    continue  # no cue yet — stay silent
                elapsed = time.time() - cue_time
                if elapsed > WINDOW_SEC + STEP_SEC:
                    cue_time = None       # window expired — next cue resets it
                    continue
                if elapsed < WINDOW_SEC:
                    tag = f"filling {elapsed / WINDOW_SEC * 100:3.0f}%"
                else:
                    tag = "ALIGNED   "
                mark = "OK " if pred == cue_true else "MISS"
                conf = "  ".join(f"{classes[i]}={probs[i]:.2f}" for i in range(len(classes)))
                print(f"[classify] raw={classes[pred]:6s}  voted={label:6s}  | {conf}"
                      f"  [true={classes[cue_true]:5s} {mark} {tag}]")
            else:
                conf = "  ".join(f"{classes[i]}={probs[i]:.2f}" for i in range(len(classes)))
                print(f"[classify] raw={classes[pred]:6s}  voted={label:6s}  | {conf}")

            outlet.push_sample([voted])


# ─────────────────────────────────────────────
# XDF EPOCH EXTRACTION
# ─────────────────────────────────────────────

def extract_epochs_from_xdf(xdf_path: str):
    """
    Load XDF, extract labelled 2.5-second epochs.
    Returns X (n, 1, ch, time), y (n,), and classes dict {label_int: name}.

    [FIX-4]  preprocessing uses zero_phase=True (filtfilt) to avoid phase distortion.
    [FIX-17] Detects which MI markers are present — works for 2-class and 3-class datasets.
    """
    import pyxdf
    streams, _ = pyxdf.load_xdf(xdf_path)

    eeg_stream = next(s for s in streams if s['info']['type'][0] == 'EEG')
    mk_stream  = next(s for s in streams if s['info']['type'][0] == 'Markers')

    eeg_data   = eeg_stream['time_series'][:, CHANNELS]
    eeg_times  = eeg_stream['time_stamps']
    mk_times   = mk_stream['time_stamps']
    mk_values  = np.array([int(v[0]) for v in mk_stream['time_series']])

    # [FIX-17] Build marker→label map from only the markers that appear in this file
    present_markers = sorted(
        m for m in ALL_MARKERS if m in mk_values
    )
    if not present_markers:
        raise ValueError("[data] No recognised MI markers (769/770/773) found in XDF.")
    MARKER_TO_LABEL = {m: i for i, m in enumerate(present_markers)}
    classes = {i: ALL_MARKERS[m] for m, i in MARKER_TO_LABEL.items()}
    print(f"[data] detected {len(classes)}-class problem: "
          + ", ".join(f"{v}(marker {m})" for m, v in zip(present_markers, classes.values())))

    X, y = [], []
    for mt, mv in zip(mk_times, mk_values):
        if mv not in MARKER_TO_LABEL:
            continue
        label = MARKER_TO_LABEL[mv]
        idx   = np.searchsorted(eeg_times, mt)
        end   = idx + WINDOW_SAMPLES
        if end > len(eeg_data):
            continue
        epoch = eeg_data[idx:end]                        # (time, ch)
        epoch = preprocess(epoch, zero_phase=True)       # [FIX-4]
        X.append(epoch.T[None, :, :])                    # (1, ch, time)
        y.append(label)

    X = np.stack(X).astype(np.float32)
    y = np.array(y, dtype=np.int64)
    print(f"[data] {len(y)} epochs | class counts: "
          + ", ".join(f"{classes[i]}={c}" for i, c in enumerate(np.bincount(y))))
    return X, y, classes


# ─────────────────────────────────────────────
# TRAINING
# ─────────────────────────────────────────────

def _run_epochs(model, dl_tr, dl_val, epochs, lr, n_classes):
    """Inner training loop — returns (best_val_acc, best_state_dict)."""
    counts_arr = np.zeros(n_classes, dtype=np.float32)
    for _, yb in dl_tr:
        for v in yb.numpy():
            counts_arr[v] += 1
    weights   = torch.tensor(1.0 / (counts_arr + 1e-6))
    weights  /= weights.sum()
    criterion = nn.CrossEntropyLoss(weight=weights)

    optimiser = torch.optim.Adam(model.parameters(), lr=lr)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(
                    optimiser, T_max=epochs, eta_min=1e-5)

    best_acc   = 0.0
    best_state = None

    for ep in range(1, epochs + 1):
        model.train()
        for xb, yb in dl_tr:
            xb_aug = torch.tensor(augment(xb.numpy()))
            optimiser.zero_grad()
            criterion(model(xb_aug), yb).backward()
            optimiser.step()
        scheduler.step()

        model.eval()
        correct = total = 0
        with torch.no_grad():
            for xb, yb in dl_val:
                correct += (model(xb).argmax(1) == yb).sum().item()
                total   += len(yb)
        val_acc = correct / total
        lr_now  = scheduler.get_last_lr()[0]

        tag = " ◀ best" if val_acc > best_acc else ""
        print(f"  Epoch {ep:3d}/{epochs}  val_acc={val_acc:.3f}  lr={lr_now:.2e}{tag}")
        if val_acc > best_acc:
            best_acc   = val_acc
            best_state = {k: v.clone() for k, v in model.state_dict().items()}

    return best_acc, best_state


def train(xdf_path: str, save_path: str = 'eegnet_weights.pt',
          epochs: int = 300, lr: float = 8e-4, k_folds: int = 5):
    """
    [FIX-8]  CosineAnnealingLR scheduler.
    [FIX-9]  Class-weighted loss.
    [FIX-10] No early stopping — all epochs run; best val_acc checkpoint saved.
    [FIX-11] Augmentation (noise, shift, amplitude scale, channel dropout).
    [FIX-17] N_CLASSES inferred from XDF; class map saved into checkpoint.
    [FIX-19] k-fold CV (k=5) for reliable accuracy on small datasets (~90 trials).
             Final model re-trained on ALL data so nothing is wasted.
    """
    from torch.utils.data import TensorDataset, DataLoader
    from sklearn.model_selection import StratifiedKFold

    X, y, classes = extract_epochs_from_xdf(xdf_path)
    n_classes = len(classes)

    # ── Phase 1: k-fold CV to measure real accuracy ──────────────────────────
    skf        = StratifiedKFold(n_splits=k_folds, shuffle=True, random_state=42)
    fold_accs  = []

    print(f"\n[train] Phase 1 — {k_folds}-fold cross-validation ({len(y)} total epochs)")
    for fold, (tr_idx, val_idx) in enumerate(skf.split(X, y), 1):
        print(f"\n  ── Fold {fold}/{k_folds} ──")
        X_tr, X_val = X[tr_idx], X[val_idx]
        y_tr, y_val = y[tr_idx], y[val_idx]

        dl_tr  = DataLoader(TensorDataset(torch.tensor(X_tr), torch.tensor(y_tr)),
                            batch_size=16, shuffle=True)
        dl_val = DataLoader(TensorDataset(torch.tensor(X_val), torch.tensor(y_val)),
                            batch_size=32)

        model = EEGNet(n_classes=n_classes, n_channels=N_CHANNELS,
                       n_samples=WINDOW_SAMPLES)
        acc, _ = _run_epochs(model, dl_tr, dl_val, epochs, lr, n_classes)
        fold_accs.append(acc)
        print(f"  Fold {fold} best val_acc = {acc:.3f}")

    mean_acc = float(np.mean(fold_accs))
    print(f"\n[train] CV result: {mean_acc:.3f} ± {float(np.std(fold_accs)):.3f}  "
          f"(chance={1/n_classes:.3f})")

    # ── Phase 2: re-train on ALL data for the saved model ────────────────────
    print(f"\n[train] Phase 2 — final model on all {len(y)} samples")
    dl_all = DataLoader(TensorDataset(torch.tensor(X), torch.tensor(y)),
                        batch_size=16, shuffle=True)
    dl_dummy = DataLoader(TensorDataset(torch.tensor(X), torch.tensor(y)),
                          batch_size=32)   # val = train (just for consistent API)

    model_final = EEGNet(n_classes=n_classes, n_channels=N_CHANNELS,
                         n_samples=WINDOW_SAMPLES)
    _, best_state = _run_epochs(model_final, dl_all, dl_dummy, epochs, lr, n_classes)

    model_final.load_state_dict(best_state)
    torch.save({'state_dict': best_state, 'classes': classes}, save_path)
    print(f"\n[train] saved → {save_path}  (CV val_acc={mean_acc:.3f})")
    return model_final, classes


# ─────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='EEG Online Classifier')
    parser.add_argument('--model', type=str, default=None,
                        help='Path to trained EEGNet weights (.pt)')
    parser.add_argument('--train', type=str, default=None,
                        metavar='XDF', help='Train on this XDF file then exit')
    parser.add_argument('--xdf',   type=str, default=None,
                        help='XDF being replayed via XDFStreamer. Prints class '
                             'distribution AND — if no live Markers stream is '
                             'available — drives cue-gated inference from the '
                             'XDF\'s own marker timestamps.')
    parser.add_argument('--mock', action='store_true',
                        help='Bypass model — emit random classifications for pipeline testing')
    args = parser.parse_args()

    try:
        if args.train:
            train(args.train, save_path='eegnet_weights.pt')
        else:
            # [FIX-14] Print class distribution from XDF before inference so
            #          imbalance is visible without a separate diagnostic script.
            # [FIX-23] Also extract cue schedule (offset-from-first-EEG-sample,
            #          marker) so run_online can fall back to schedule-based
            #          gating when XDFStreamer only broadcasts the EEG stream.
            cue_schedule = None
            if args.xdf:
                print("[diagnostic] Checking class distribution in XDF …")
                import pyxdf
                streams, _ = pyxdf.load_xdf(args.xdf)
                mk_stream  = next(s for s in streams if s['info']['type'][0] == 'Markers')
                values     = [int(v[0]) for v in mk_stream['time_series']]
                for marker, name in ALL_MARKERS.items():
                    print(f"  {name:6s}: {values.count(marker)} trials (marker {marker})")
                cue_schedule = _extract_cue_schedule(args.xdf)

            model, classes = load_model(args.model)   # [FIX-17]
            outlet = create_output_stream()
            run_online(model, outlet, classes,
                       mock=args.mock, cue_schedule=cue_schedule)

    except KeyboardInterrupt:
        print("\n[status] Ctrl-C detected. Terminating classifier …")
    finally:
        print("[status] Program exited.")
