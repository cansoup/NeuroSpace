"""
Online motor-imagery inference.

Subscribes to an LSL EEG stream and an LSL marker stream, extracts a 4-second
epoch starting at each motor-imagery cue (769 / 770 / 773), preprocesses it
(100 Hz lowpass + 50 Hz notch) the same way the training notebook does, runs
visionpro_best.pth, and prints the predicted class with running accuracy.

Typical rehearsal setup:
  Terminal A: XDFStreamer.exe -> load data/visionpro-ml.xdf -> Play
  Terminal B: python scripts/online_inference.py

For the live session, replace XDFStreamer with the OpenBCI -> LSL bridge.
Nothing on this side changes.
"""

import os
import sys
import time
from collections import deque
from pathlib import Path

import numpy as np
import torch
import mne
from pylsl import StreamInlet, resolve_byprop

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
sys.path.append(str(PROJECT_ROOT / "bci-ml-pipeline" / "models" / "architectures"))
from eegnet import EEGNet

# ---------------------------------------------------------------------------
# Configuration (matches notebooks/train_visionpro_model.ipynb)
# ---------------------------------------------------------------------------
MODEL_PATH = PROJECT_ROOT / "visionpro_best.pth"
CHANNELS_TO_USE = [2, 3, 5]        # zero-indexed = OpenBCI channels 3, 4, 6
SFREQ = 250
EPOCH_SECONDS = 4.0
N_TIMEPOINTS = 1001                 # mne.Epochs(tmin=0, tmax=4) is endpoint-inclusive
LOWPASS_HZ = 100.0
NOTCH_HZ = 50.0
MI_MARKERS = {769: ("left", 0), 770: ("right", 1), 773: ("both", 2)}
CLASS_NAMES = ["Left", "Right", "Both"]
RESOLVE_TIMEOUT = 10.0              # seconds to wait for LSL streams
BUFFER_SECONDS = 10.0               # EEG buffer length
POLL_SLEEP = 0.01                   # idle sleep between pull_chunk calls

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"


def load_model():
    model = EEGNet(
        n_channels=len(CHANNELS_TO_USE),
        n_classes=len(MI_MARKERS),
        n_timepoints=N_TIMEPOINTS,
        F1=8,
        D=2,
        F2=16,
        kernel_length=64,
        dropout=0.5,
    )
    checkpoint = torch.load(MODEL_PATH, map_location=DEVICE)
    model.load_state_dict(checkpoint["model_state_dict"])
    model.to(DEVICE).eval()
    val_acc = checkpoint.get("val_acc", float("nan"))
    print(f"Loaded model from {MODEL_PATH.name} (epoch {checkpoint.get('epoch', '?')}, val_acc={val_acc:.3f})")
    return model


def resolve_stream(stream_type, expect_rate=None, min_channels=None):
    print(f"Waiting for LSL stream type='{stream_type}' (timeout {RESOLVE_TIMEOUT}s)...")
    streams = resolve_byprop("type", stream_type, timeout=RESOLVE_TIMEOUT)
    if not streams:
        raise SystemExit(
            f"No LSL stream of type '{stream_type}' found. "
            f"Is XDFStreamer running and playing? "
            f"If using XDFStreamer, confirm every stream you want to broadcast "
            f"has its checkbox ticked in the left panel."
        )
    info = streams[0]
    name = info.name()
    srate = info.nominal_srate()
    nch = info.channel_count()
    print(f"Resolved {stream_type}: name='{name}', rate={srate} Hz, channels={nch}")

    # Guard against XDFStreamer exposing only the marker stream: the first
    # matching stream then satisfies the type filter but has the wrong shape.
    if expect_rate is not None and abs(srate - expect_rate) > 0.5:
        raise SystemExit(
            f"Expected rate ~{expect_rate} Hz for {stream_type}, got {srate}. "
            f"Did only the Markers stream get enabled in XDFStreamer?"
        )
    if min_channels is not None and nch < min_channels:
        raise SystemExit(
            f"Expected at least {min_channels} channels for {stream_type}, got {nch}."
        )

    return StreamInlet(info, max_chunklen=0)


def preprocess_epoch(samples):
    """
    samples: np.ndarray, shape (n_ch, ~1001).
    Returns (1, 1, n_ch, 1001) float32 tensor ready for EEGNet.
    """
    n_ch, n_samp = samples.shape

    # Pad or truncate to exactly N_TIMEPOINTS.
    if n_samp < N_TIMEPOINTS:
        pad = np.zeros((n_ch, N_TIMEPOINTS - n_samp), dtype=samples.dtype)
        samples = np.concatenate([samples, pad], axis=1)
    elif n_samp > N_TIMEPOINTS:
        samples = samples[:, :N_TIMEPOINTS]

    # Matching training notebook cell 3: MNE IIR filters, verbose off.
    ch_names = [f"Ch{i + 1}" for i in CHANNELS_TO_USE]
    info = mne.create_info(ch_names=ch_names, sfreq=SFREQ, ch_types=["eeg"] * n_ch)
    raw = mne.io.RawArray(samples, info, verbose=False)
    raw.filter(l_freq=None, h_freq=LOWPASS_HZ, method="iir", verbose=False)
    raw.notch_filter(freqs=NOTCH_HZ, method="iir", verbose=False)
    filtered = raw.get_data()

    # Per-epoch robust scaling (median, IQR). Training used population stats;
    # per-epoch is the standard choice for real-time systems.
    normalized = np.zeros_like(filtered)
    for c in range(filtered.shape[0]):
        channel = filtered[c]
        med = np.median(channel)
        q25, q75 = np.percentile(channel, [25, 75])
        iqr = q75 - q25
        if iqr > 0:
            normalized[c] = (channel - med) / iqr
        else:
            std = channel.std() + 1e-8
            normalized[c] = (channel - channel.mean()) / std

    tensor = torch.from_numpy(normalized).float().unsqueeze(0).unsqueeze(0)
    return tensor.to(DEVICE)


def extract_window(buffer, start_ts, end_ts):
    """Return ndarray (n_ch, n) of samples with timestamps in [start_ts, end_ts]."""
    rows = [sample for ts, sample in buffer if start_ts <= ts <= end_ts]
    if not rows:
        return None
    return np.stack(rows, axis=1)


def main():
    model = load_model()
    eeg_inlet = resolve_stream("EEG", expect_rate=SFREQ, min_channels=max(CHANNELS_TO_USE) + 1)
    marker_inlet = resolve_stream("Markers")

    max_buffer = int(BUFFER_SECONDS * SFREQ)
    eeg_buffer = deque(maxlen=max_buffer)  # (timestamp, np.ndarray[len=3])
    pending = []                           # list[(marker_ts, class_idx, class_name)]

    total = correct = 0
    per_class = {name: [0, 0] for name in CLASS_NAMES}  # name -> [correct, total]

    print("Listening... press Ctrl-C to stop.\n")
    try:
        while True:
            # 1. Drain EEG.
            eeg_chunk, eeg_ts = eeg_inlet.pull_chunk(timeout=0.0, max_samples=256)
            if eeg_chunk:
                arr = np.asarray(eeg_chunk)  # (n_samples, n_channels)
                sub = arr[:, CHANNELS_TO_USE]
                for ts, row in zip(eeg_ts, sub):
                    eeg_buffer.append((ts, row.astype(np.float32)))

            # 2. Drain markers.
            mk_chunk, mk_ts = marker_inlet.pull_chunk(timeout=0.0, max_samples=32)
            if mk_chunk:
                for marker_row, ts in zip(mk_chunk, mk_ts):
                    try:
                        code = int(marker_row[0])
                    except (TypeError, ValueError):
                        continue
                    if code in MI_MARKERS:
                        name, idx = MI_MARKERS[code]
                        pending.append((ts, idx, name))

            # 3. Process epochs whose 4-sec window has fully arrived.
            if pending and eeg_buffer:
                latest_ts = eeg_buffer[-1][0]
                still_pending = []
                for marker_ts, true_idx, true_name in pending:
                    end_ts = marker_ts + EPOCH_SECONDS
                    if latest_ts < end_ts:
                        still_pending.append((marker_ts, true_idx, true_name))
                        continue

                    window = extract_window(eeg_buffer, marker_ts, end_ts)
                    if window is None or window.shape[1] < SFREQ:
                        print(f"[skipped] insufficient EEG for marker={true_name} at t={marker_ts:.3f}")
                        continue

                    x = preprocess_epoch(window)
                    with torch.no_grad():
                        logits = model(x)
                        probs = torch.softmax(logits, dim=1)[0].cpu().numpy()
                    pred_idx = int(np.argmax(probs))
                    pred_name = CLASS_NAMES[pred_idx]

                    total += 1
                    per_class[CLASS_NAMES[true_idx]][1] += 1
                    hit = pred_idx == true_idx
                    if hit:
                        correct += 1
                        per_class[CLASS_NAMES[true_idx]][0] += 1
                    tick = "\u2713" if hit else "\u2717"
                    acc = correct / total
                    print(f"[{total:>3}] true={true_name:<5} pred={pred_name:<5} "
                          f"p={probs[pred_idx]:.2f} {tick} running_acc={acc:.3f} ({correct}/{total})")

                pending = still_pending

            time.sleep(POLL_SLEEP)

    except KeyboardInterrupt:
        print("\nStopped.")
        if total == 0:
            print("No trials classified.")
            return
        print(f"Overall accuracy: {correct / total:.3f} ({correct}/{total})")
        for name, (c, t) in per_class.items():
            if t:
                print(f"  {name:<5} {c / t:.3f} ({c}/{t})")


if __name__ == "__main__":
    main()
