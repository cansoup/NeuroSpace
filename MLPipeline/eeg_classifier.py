#!/usr/bin/env python3
"""
eeg_classifier.py
=================
Online EEG Motor Imagery classifier for the VisionStudio BCI pipeline.

Architecture
------------
XDF / Live LSL ──► pre-process ──► EEGNet ──► sliding window ──► majority vote ──► LSL out
                      │
                  (bandpass + z-score)

Dataset notes (bci-mi-n-100.xdf)
---------------------------------
  Channels  : 8 raw hardware channels  (ch0,1,2,4,6,7 = EEG; ch3,5 = reference)
  Srate     : 250 Hz
  Duration  : ~28 min
  Markers   : 768=left(n=200), 769=right(n=100), 770=foot, 782=trial_end, 32766=sync
  Note      : Class imbalance 2:1 (left vs right) — handled via class_weight in training

Usage
-----
  # Calibrate EEGNet on the XDF, then replay at 10× speed:
  python eeg_classifier.py --train --xdf bci-mi-n-100.xdf

  # Load saved weights and replay:
  python eeg_classifier.py --xdf bci-mi-n-100.xdf --weights eegnet_weights.pt

  # Live LSL stream:
  python eeg_classifier.py --mode online --weights eegnet_weights.pt

Requirements
------------
  pip install torch numpy scipy pylsl
  (pylsl optional – falls back to stdout if unavailable)
"""

from __future__ import annotations
import argparse
import struct
import time
import xml.etree.ElementTree as ET
from collections import deque
from typing import Optional

import numpy as np
from scipy.signal import butter, sosfiltfilt
from scipy.linalg import eigh

import torch
import torch.nn as nn
import torch.nn.functional as F

# ── LSL ───────────────────────────────────────────────────────────────────────
try:
    from pylsl import StreamInfo, StreamOutlet, StreamInlet, resolve_stream
    HAS_LSL = True
except ImportError:
    HAS_LSL = False

# ── Constants ─────────────────────────────────────────────────────────────────
SRATE         = 250          # Hz
N_CHANNELS    = 8            # total channels in stream
EEG_CHANNELS  = [0,1,2,4,6,7]  # exclude reference channels 3 & 5
N_EEG         = len(EEG_CHANNELS)
BANDPASS_LO   = 8.0          # Hz
BANDPASS_HI   = 30.0         # Hz
WINDOW_SEC    = 2.0          # sliding window length
STEP_SEC      = 0.25         # step between windows → 4 Hz prediction rate
VOTE_N        = 5            # majority-vote buffer size

WINDOW_SAMP   = int(WINDOW_SEC * SRATE)   # 500
STEP_SAMP     = int(STEP_SEC  * SRATE)    # 62

# Training hyperparams
TMIN, TMAX    = 0.5, 2.5     # epoch window relative to MI onset (seconds)
EPOCHS        = 40
LR            = 1e-3
DROPOUT       = 0.5

# Marker codes → class index
MARKER_CLS    = {768: 1, 769: 2}   # 1=left, 2=right (0 reserved for idle)
LABEL         = {0: "idle", 1: "left", 2: "right"}
N_CLASSES     = 3


# ── EEGNet ────────────────────────────────────────────────────────────────────

class DepthwiseConv2d(nn.Conv2d):
    def __init__(self, in_ch, depth, kernel):
        super().__init__(in_ch, in_ch * depth, kernel, groups=in_ch, bias=False)


class EEGNet(nn.Module):
    """
    EEGNet (Lawhern et al. 2018).
    Input:  (batch, 1, n_channels, n_timepoints)
    Output: (batch, n_classes) logits
    """

    def __init__(
        self,
        n_classes:    int = N_CLASSES,
        n_channels:   int = N_EEG,
        n_timepoints: int = WINDOW_SAMP,
        F1: int = 8,   # number of temporal filters
        D:  int = 2,   # depthwise multiplier
        F2: int = 16,  # separable filters
        p:  float = DROPOUT,
    ):
        super().__init__()
        self.n_classes    = n_classes
        self.n_channels   = n_channels
        self.n_timepoints = n_timepoints

        # ── Block 1: temporal + spatial ──────────────────────────────────────
        self.conv1   = nn.Conv2d(1, F1, (1, 64), padding=(0, 32), bias=False)
        self.bn1     = nn.BatchNorm2d(F1)

        self.conv2   = DepthwiseConv2d(F1, D, (n_channels, 1))
        self.bn2     = nn.BatchNorm2d(F1 * D)
        self.pool1   = nn.AvgPool2d((1, 4))
        self.drop1   = nn.Dropout(p)

        # ── Block 2: separable convolution ────────────────────────────────────
        self.conv3_d = nn.Conv2d(F1*D, F1*D, (1,16), padding=(0,8), groups=F1*D, bias=False)
        self.conv3_p = nn.Conv2d(F1*D, F2,   (1,1),  bias=False)
        self.bn3     = nn.BatchNorm2d(F2)
        self.pool2   = nn.AvgPool2d((1, 8))
        self.drop2   = nn.Dropout(p)

        # ── Classifier ────────────────────────────────────────────────────────
        with torch.no_grad():
            dummy = torch.zeros(1, 1, n_channels, n_timepoints)
            flat  = self._features(dummy).shape[1]
        self.fc = nn.Linear(flat, n_classes)

    def _features(self, x):
        x = F.elu(self.bn2(self.conv2(self.bn1(self.conv1(x)))))
        x = self.drop1(self.pool1(x))
        x = F.elu(self.bn3(self.conv3_p(self.conv3_d(x))))
        x = self.drop2(self.pool2(x))
        return x.flatten(1)

    def forward(self, x):
        return self.fc(self._features(x))


# ── Signal processing ─────────────────────────────────────────────────────────

def make_bandpass(lo: float = BANDPASS_LO,
                  hi: float = BANDPASS_HI,
                  fs: float = SRATE):
    return butter(4, [lo, hi], btype="bandpass", fs=fs, output="sos")

_SOS = make_bandpass()   # module-level filter object (reused across windows)


def preprocess(window: np.ndarray) -> torch.Tensor:
    """
    window : (n_channels, n_timepoints)  raw hardware units
    returns: (1, 1, n_channels, n_timepoints)  z-scored bandpassed float32 tensor
    """
    w = sosfiltfilt(_SOS, window, axis=1)
    w = (w - w.mean(axis=1, keepdims=True)) / (w.std(axis=1, keepdims=True) + 1e-6)
    return torch.tensor(w, dtype=torch.float32).unsqueeze(0).unsqueeze(0)


# ── XDF parser ────────────────────────────────────────────────────────────────

def _varlen(f) -> int:
    b = f.read(1)[0]
    if b == 1: return struct.unpack("<B", f.read(1))[0]
    if b == 4: return struct.unpack("<I", f.read(4))[0]
    if b == 8: return struct.unpack("<Q", f.read(8))[0]
    return b


def load_xdf(path: str) -> tuple[np.ndarray, np.ndarray, list, float]:
    """
    Returns
    -------
    eeg     : (N, C)  float32
    ts      : (N,)    float64  LSL timestamps
    markers : list of (timestamp, int_code)
    srate   : float
    """
    streams, rows, times, marks = {}, [], [], []

    with open(path, "rb") as f:
        assert f.read(4) == b"XDF:", "Not an XDF file"
        while True:
            try:
                nb  = _varlen(f)
                tag = struct.unpack("<H", f.read(2))[0]
                body = f.read(nb - 2)
            except Exception:
                break

            if tag == 2:                             # StreamHeader
                sid  = struct.unpack("<I", body[:4])[0]
                root = ET.fromstring(body[4:].decode("utf-8", errors="replace"))
                streams[sid] = {c.tag: c.text for c in root}

            elif tag == 3:                           # Samples
                sid   = struct.unpack("<I", body[:4])[0]
                si    = streams.get(sid, {})
                stype = si.get("type", "")
                n_ch  = int(si.get("channel_count", 1))
                fc, fs = {"float32": ("f",4), "int32": ("i",4)}.get(
                    si.get("channel_format","float32"), ("f",4))

                pos = 4
                ni  = body[pos]; pos += 1
                if   ni == 1: n = body[pos]; pos += 1
                elif ni == 4: n = struct.unpack("<I", body[pos:pos+4])[0]; pos += 4
                else:         n = ni

                for _ in range(n):
                    ti = body[pos]; pos += 1
                    ts = struct.unpack("<d", body[pos:pos+8])[0] if ti == 8 else None
                    pos += 8 if ti == 8 else 0
                    vals = struct.unpack_from(f"<{n_ch}{fc}", body, pos)
                    pos  += n_ch * fs

                    if   stype == "EEG":     rows.append(vals); times.append(ts)
                    elif stype == "Markers": marks.append((ts, vals[0]))

    eeg   = np.array(rows, dtype=np.float32)
    ts_arr = np.array([t if t is not None else 0.0 for t in times], dtype=np.float64)
    srate = float(streams.get(2, {}).get("nominal_srate", SRATE))

    # Only keep EEG channels
    eeg = eeg[:, EEG_CHANNELS]

    print(f"[xdf] {len(eeg)} samples × {eeg.shape[1]} EEG channels "
          f"@ {srate:.0f} Hz  |  {len(marks)} markers")
    return eeg, ts_arr, marks, srate


def extract_epochs(
    eeg: np.ndarray,
    ts:  np.ndarray,
    markers: list,
    srate: float,
    tmin: float = TMIN,
    tmax: float = TMAX,
) -> tuple[np.ndarray, np.ndarray]:
    """
    Returns
    -------
    X : (n_trials, n_channels, n_timepoints)  float32
    y : (n_trials,)  int64   (1=left, 2=right)
    """
    eeg_C  = eeg.T       # (C, N)
    t_pre  = int(tmin * srate)
    t_post = int(tmax * srate)
    X_list, y_list = [], []

    for t, code in markers:
        if code not in MARKER_CLS or t is None:
            continue
        idx = int(np.searchsorted(ts, t))
        s, e = idx + t_pre, idx + t_post
        if s < 0 or e > eeg_C.shape[1]:
            continue
        X_list.append(eeg_C[:, s:e].copy())
        y_list.append(MARKER_CLS[code])

    if not X_list:
        raise ValueError("No valid MI epochs found — check marker codes.")

    X = np.stack(X_list).astype(np.float32)
    y = np.array(y_list, dtype=np.int64)
    print(f"[epochs] {len(X)} epochs  "
          f"(left={np.sum(y==1)}, right={np.sum(y==2)})  "
          f"shape={X.shape[1:]}")
    return X, y


# ── Majority vote ─────────────────────────────────────────────────────────────

class MajorityVote:
    def __init__(self, window: int = VOTE_N, n_classes: int = N_CLASSES):
        self._buf = deque(maxlen=window)
        self._n   = n_classes

    def push(self, pred: int) -> int:
        self._buf.append(pred)
        counts = np.bincount(list(self._buf), minlength=self._n)
        return int(counts.argmax())

    def reset(self):
        self._buf.clear()


# ── Training ──────────────────────────────────────────────────────────────────

def train(
    xdf_path: str,
    save_path: str,
    device: torch.device,
    n_epochs: int = EPOCHS,
    lr: float = LR,
    val_frac: float = 0.2,
) -> EEGNet:
    """Fine-tune EEGNet on the XDF recording and save weights."""
    eeg, ts, markers, srate = load_xdf(xdf_path)
    X_raw, y = extract_epochs(eeg, ts, markers, srate)

    # ── Pre-process ──────────────────────────────────────────────────────────
    sos = make_bandpass(fs=srate)
    X_filt = np.stack([sosfiltfilt(sos, X_raw[i], axis=1) for i in range(len(X_raw))])
    mu  = X_filt.mean(axis=2, keepdims=True)
    std = X_filt.std(axis=2,  keepdims=True) + 1e-6
    X_proc = ((X_filt - mu) / std).astype(np.float32)

    # Pad / trim to WINDOW_SAMP
    T = X_proc.shape[2]
    if T > WINDOW_SAMP:
        X_proc = X_proc[:, :, :WINDOW_SAMP]
    elif T < WINDOW_SAMP:
        X_proc = np.concatenate(
            [X_proc, np.zeros((len(X_proc), N_EEG, WINDOW_SAMP - T), dtype=np.float32)], axis=2)

    # ── Split ────────────────────────────────────────────────────────────────
    n     = len(X_proc)
    n_val = max(2, int(n * val_frac))
    perm  = np.random.default_rng(42).permutation(n)
    tr_i, va_i = perm[n_val:], perm[:n_val]

    X_tr = torch.tensor(X_proc[tr_i]).unsqueeze(1).to(device)
    y_tr = torch.tensor(y[tr_i]).to(device)
    X_va = torch.tensor(X_proc[va_i]).unsqueeze(1).to(device)
    y_va = torch.tensor(y[va_i]).to(device)

    # ── Class weights (handle imbalance) ─────────────────────────────────────
    counts = np.bincount(y[tr_i], minlength=N_CLASSES).astype(float)
    counts = np.where(counts == 0, 1.0, counts)
    w = torch.tensor(counts.sum() / (N_CLASSES * counts), dtype=torch.float32).to(device)

    # ── Model + optimizer ─────────────────────────────────────────────────────
    model = EEGNet().to(device)
    opt   = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=1e-4)
    sch   = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=n_epochs)
    ce    = nn.CrossEntropyLoss(weight=w)

    print(f"\n[train] {len(tr_i)} train / {len(va_i)} val  |  "
          f"class weights: {[f'{x:.2f}' for x in w.cpu().numpy()]}")

    best_acc, best_state = 0.0, None
    model.train()
    for ep in range(1, n_epochs + 1):
        opt.zero_grad()
        loss = ce(model(X_tr), y_tr)
        loss.backward(); opt.step(); sch.step()

        if ep % 5 == 0 or ep == n_epochs:
            model.eval()
            with torch.no_grad():
                pred    = model(X_va).argmax(1)
                val_acc = (pred == y_va).float().mean().item()
            if val_acc > best_acc:
                best_acc   = val_acc
                best_state = {k: v.clone() for k, v in model.state_dict().items()}
            model.train()
            print(f"  ep {ep:3d}/{n_epochs}  loss={loss.item():.4f}  val_acc={val_acc:.3f}  "
                  f"best={best_acc:.3f}")

    if best_state:
        model.load_state_dict(best_state)
    model.eval()
    torch.save(model.state_dict(), save_path)
    print(f"\n[train] Done. Best val_acc={best_acc:.3f}  weights → {save_path}\n")
    return model


# ── LSL helpers ───────────────────────────────────────────────────────────────

def create_lsl_outlet(name: str = "EEG_Prediction") -> Optional[object]:
    if not HAS_LSL:
        print("[lsl] pylsl not found – predictions will print to stdout.")
        return None
    info   = StreamInfo(name, "Markers", 1, 0, "int32", "eeg_pred_bci001")
    outlet = StreamOutlet(info)
    print(f"[lsl] Output stream '{name}' created.")
    return outlet


def emit(outlet, label: int, ts: Optional[float] = None):
    tag = f"[{time.strftime('%H:%M:%S')}]" if ts is None else f"[ts={ts:.2f}]"
    if outlet:
        outlet.push_sample([label])
    else:
        bar = {"idle": "░░░░░", "left": "◀◀◀◀◀", "right": "▶▶▶▶▶"}[LABEL[label]]
        print(f"{tag}  {bar}  {label}  ({LABEL[label]})")


# ── Offline replay ────────────────────────────────────────────────────────────

def run_offline(xdf_path: str, model: EEGNet, outlet,
                device: torch.device, replay_speed: float = 10.0):
    eeg, ts, markers, srate = load_xdf(xdf_path)
    eeg_C   = eeg.T       # (C, N)
    n_samp  = eeg_C.shape[1]
    vote    = MajorityVote()

    print(f"\n[replay] {n_samp} samples  window={WINDOW_SEC}s  step={STEP_SEC}s  "
          f"speed={replay_speed:.0f}×\n")

    model.eval()
    results = []
    with torch.no_grad():
        pos = 0
        while pos + WINDOW_SAMP <= n_samp:
            w  = eeg_C[:, pos:pos + WINDOW_SAMP]
            x  = preprocess(w).to(device)
            p  = F.softmax(model(x), dim=1).cpu().numpy()[0]
            raw  = int(p.argmax())
            voted = vote.push(raw)

            t_now = ts[pos] if ts[pos] != 0.0 else None
            results.append((t_now, raw, voted, p))
            emit(outlet, voted, t_now)

            time.sleep(STEP_SEC / replay_speed)
            pos += STEP_SAMP

    print(f"\n[replay] Done. {len(results)} predictions emitted.")
    _print_summary(results)


def _print_summary(results):
    from collections import Counter
    counts = Counter(r[2] for r in results)
    print("\n── Prediction distribution ──────────────────────────")
    for k in range(N_CLASSES):
        n   = counts.get(k, 0)
        bar = "█" * max(1, n // 5)
        print(f"  {LABEL[k]:>6} ({k}): {n:4d}  {bar}")
    print("─────────────────────────────────────────────────────\n")


# ── Online (live LSL) ─────────────────────────────────────────────────────────

def run_online(model: EEGNet, outlet, device: torch.device):
    if not HAS_LSL:
        raise RuntimeError("pylsl required for online mode.")

    print("[online] Resolving EEG LSL stream…")
    inlets = resolve_stream("type", "EEG")
    inlet  = StreamInlet(inlets[0])
    sinfo  = inlets[0]
    print(f"[online] Connected: '{sinfo.name()}'  {sinfo.channel_count()} ch @ {sinfo.nominal_srate()} Hz")

    buf                = deque(maxlen=WINDOW_SAMP * 2)
    vote               = MajorityVote()
    samps_since_pred   = 0

    model.eval()
    with torch.no_grad():
        while True:
            chunk, _ = inlet.pull_chunk(timeout=1.0, max_samples=STEP_SAMP * 2)
            if not chunk:
                continue
            for sample in chunk:
                # Keep only EEG channels
                buf.append([sample[c] for c in EEG_CHANNELS])
            samps_since_pred += len(chunk)

            if len(buf) >= WINDOW_SAMP and samps_since_pred >= STEP_SAMP:
                w    = np.array(list(buf)[-WINDOW_SAMP:]).T.astype(np.float32)
                x    = preprocess(w).to(device)
                p    = F.softmax(model(x), dim=1).cpu().numpy()[0]
                raw  = int(p.argmax())
                voted = vote.push(raw)
                emit(outlet, voted)
                samps_since_pred = 0


# ── CLI ───────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description="EEG Motor Imagery Online Classifier")
    ap.add_argument("--mode",    choices=["offline","online"], default="offline",
                    help="offline = replay XDF;  online = live LSL stream")
    ap.add_argument("--xdf",     default="bci-mi-n-100.xdf",
                    help="Path to XDF recording (offline mode / training)")
    ap.add_argument("--weights", default="eegnet_weights.pt",
                    help="Path to load/save EEGNet weights (.pt)")
    ap.add_argument("--train",   action="store_true",
                    help="Fine-tune EEGNet on --xdf before running")
    ap.add_argument("--epochs",  type=int, default=EPOCHS)
    ap.add_argument("--speed",   type=float, default=10.0,
                    help="Replay speed multiplier (offline mode). 1.0 = real-time")
    args = ap.parse_args()

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"[init] Device: {device}  |  EEG channels: {EEG_CHANNELS}")

    # ── Build / load model ────────────────────────────────────────────────────
    if args.train:
        model = train(args.xdf, args.weights, device, n_epochs=args.epochs)
    else:
        model = EEGNet().to(device)
        try:
            model.load_state_dict(torch.load(args.weights, map_location=device))
            print(f"[init] Loaded weights from '{args.weights}'")
        except FileNotFoundError:
            print(f"[init] No weights found at '{args.weights}' — using random init.\n"
                  f"       Run with --train to calibrate on your XDF data first.")
        model.eval()

    # ── Create output stream ──────────────────────────────────────────────────
    outlet = create_lsl_outlet()

    # ── Run ───────────────────────────────────────────────────────────────────
    if args.mode == "offline":
        run_offline(args.xdf, model, outlet, device, replay_speed=args.speed)
    else:
        run_online(model, outlet, device)


if __name__ == "__main__":
    main()
