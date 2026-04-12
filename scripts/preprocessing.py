"""
preprocessing.py — Load, epoch, and preprocess the .xdf BCI Motor-Imagery dataset.

Marker codes (GRAZ BCI standard):
  768  → trial start (cue onset)
  769  → left-hand Motor Imagery label
  770  → right-hand Motor Imagery label
  782  → trial end
  32766 → session start

Pipeline:
  1. Load .xdf with pyxdf
  2. Bandpass filter 8–30 Hz (mu + beta band, optimal for MI)
  3. Epoch: each trial = cue_start + 0.5 s onset delay → 4 s window
  4. Baseline-correct using the 0.5 s pre-stimulus window
  5. Standardise per-channel (zero-mean, unit-variance)
  6. Output: torch tensors  X (N, 1, C, T)  and  y (N,)
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Tuple

import numpy as np
import pyxdf
import torch
from scipy.signal import butter, sosfiltfilt

logger = logging.getLogger(__name__)

# ── Constants ───────────────────────────────────────────────────────────────
SFREQ = 250                 # Hz  (OpenBCI Cyton default)
LOWCUT = 8.0                # Hz  – lower edge of mu/beta band
HIGHCUT = 30.0              # Hz  – upper edge of mu/beta band
TMIN = -0.5                 # s   – pre-stimulus baseline start
TMIN_EPOCH = 0.5            # s   – epoch start relative to cue onset (skip motor prep)
TMAX_EPOCH = 2.5            # s   – epoch end   relative to cue onset (2 s of MI)
LABEL_MAP = {769: 0, 770: 1}  # 769=left→0, 770=right→1

# ── 6-class extension label map (future use) ────────────────────────────────
# Add more markers here when training data for up/down/forward/backward is available
LABEL_MAP_6 = {
    769: 0,   # left
    770: 1,   # right
    # 771: 2,  # up   (not in this dataset – placeholder)
    # 772: 3,  # down
    # 773: 4,  # forward
    # 774: 5,  # backward
}

CHANNEL_NAMES = ["C3", "C4", "Cz", "P3", "P4", "Pz", "O1", "O2"]  # OpenBCI 8-ch typical layout


def _bandpass(data: np.ndarray, lowcut: float, highcut: float, fs: float, order: int = 5) -> np.ndarray:
    """Zero-phase Butterworth bandpass filter.  data shape: (samples, channels)."""
    nyq = 0.5 * fs
    sos = butter(order, [lowcut / nyq, highcut / nyq], btype="band", output="sos")
    return sosfiltfilt(sos, data, axis=0)


def load_xdf(xdf_path: str | Path) -> Tuple[np.ndarray, np.ndarray, float]:
    """
    Load an .xdf file and return raw EEG and marker arrays.

    Returns
    -------
    eeg : (N_samples, N_channels) float32
    eeg_ts : (N_samples,)  timestamps
    markers : list of (timestamp, value) tuples
    sfreq : effective sampling rate
    """
    xdf_path = Path(xdf_path)
    logger.info("Loading XDF: %s", xdf_path)
    streams, _ = pyxdf.load_xdf(str(xdf_path))

    eeg_stream = None
    marker_stream = None

    for stream in streams:
        stype = stream["info"]["type"][0].upper()
        if stype == "EEG":
            eeg_stream = stream
        elif stype == "MARKERS":
            marker_stream = stream

    if eeg_stream is None:
        raise ValueError("No EEG stream found in XDF file.")
    if marker_stream is None:
        raise ValueError("No Markers stream found in XDF file.")

    eeg_data = eeg_stream["time_series"].astype(np.float32)   # (T, C)
    eeg_ts = eeg_stream["time_stamps"]                         # (T,)
    sfreq = float(eeg_stream["info"]["nominal_srate"][0])

    marker_ts = marker_stream["time_stamps"]
    marker_vals = marker_stream["time_series"].flatten().astype(int)
    markers = list(zip(marker_ts, marker_vals))

    logger.info(
        "EEG: %s @ %.1f Hz | Markers: %d total",
        eeg_data.shape, sfreq, len(markers),
    )
    return eeg_data, eeg_ts, markers, sfreq


def preprocess(
    xdf_path: str | Path,
    label_map: dict[int, int] | None = None,
    tmin: float = TMIN_EPOCH,
    tmax: float = TMAX_EPOCH,
    baseline: Tuple[float, float] = (TMIN, 0.0),
    lowcut: float = LOWCUT,
    highcut: float = HIGHCUT,
    normalize: bool = True,
) -> Tuple[torch.Tensor, torch.Tensor]:
    """
    Full preprocessing pipeline.

    Returns
    -------
    X : torch.Tensor  shape (N_trials, 1, N_channels, N_times)
    y : torch.Tensor  shape (N_trials,)  int64 class labels
    """
    if label_map is None:
        label_map = LABEL_MAP

    eeg_data, eeg_ts, markers, sfreq = load_xdf(xdf_path)
    sfreq = sfreq or SFREQ

    # ── 1. Bandpass filter ──────────────────────────────────────────────
    logger.info("Bandpass filtering %.1f–%.1f Hz …", lowcut, highcut)
    eeg_filtered = _bandpass(eeg_data, lowcut, highcut, sfreq)

    # ── 2. Extract trial labels and onset times ─────────────────────────
    # GRAZ protocol: marker 768 = cue onset, next marker (769/770) = class label
    # We pair each 768 with the next label marker
    label_times: list[Tuple[float, int]] = []

    marker_iter = iter(markers)
    marker_list = list(markers)
    i = 0
    while i < len(marker_list):
        ts, val = marker_list[i]
        if val == 768:  # trial start / cue onset
            # look ahead for the class label marker (769/770)
            for j in range(i + 1, min(i + 5, len(marker_list))):
                _, next_val = marker_list[j]
                if next_val in label_map:
                    label_times.append((ts, label_map[next_val]))
                    break
        i += 1

    logger.info("Found %d labelled trials (classes: %s)", len(label_times), set(l for _, l in label_times))

    # ── 3. Epoch ────────────────────────────────────────────────────────
    n_samples_epoch = int((tmax - tmin) * sfreq)
    n_samples_baseline = int(abs(baseline[0]) * sfreq)
    n_samples_onset = int(abs(tmin) * sfreq)   # offset to reach epoch start

    epochs: list[np.ndarray] = []
    labels: list[int] = []

    for onset_ts, label in label_times:
        # Find nearest EEG sample to onset
        idx_onset = int(np.searchsorted(eeg_ts, onset_ts))

        # Baseline start (before cue)
        idx_bl_start = idx_onset + int(baseline[0] * sfreq)
        # Epoch start / end
        idx_start = idx_onset + int(tmin * sfreq)
        idx_end = idx_start + n_samples_epoch

        if idx_bl_start < 0 or idx_end > len(eeg_filtered):
            logger.warning("Trial at %.2f s skipped (out of bounds).", onset_ts)
            continue

        epoch = eeg_filtered[idx_start:idx_end, :]   # (T, C)

        # ── 4. Baseline correction ──────────────────────────────────────
        baseline_data = eeg_filtered[idx_bl_start:idx_onset, :]
        epoch = epoch - baseline_data.mean(axis=0, keepdims=True)

        epochs.append(epoch)
        labels.append(label)

    if len(epochs) == 0:
        raise RuntimeError("No valid epochs found. Check marker codes and timing.")

    X = np.stack(epochs, axis=0)   # (N, T, C)
    y = np.array(labels, dtype=np.int64)

    # ── 5. Standardise (per channel, across time within each trial) ─────
    if normalize:
        mean = X.mean(axis=1, keepdims=True)
        std = X.std(axis=1, keepdims=True) + 1e-8
        X = (X - mean) / std

    # ── 6. Reshape → (N, 1, C, T) for EEGNet ───────────────────────────
    X = X.transpose(0, 2, 1)          # (N, C, T)
    X = X[:, np.newaxis, :, :]        # (N, 1, C, T)

    X_tensor = torch.from_numpy(X.astype(np.float32))
    y_tensor = torch.from_numpy(y)

    logger.info("Preprocessing done. X: %s, y: %s", X_tensor.shape, y_tensor.shape)
    return X_tensor, y_tensor


if __name__ == "__main__":
    import sys
    logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
    xdf = sys.argv[1] if len(sys.argv) > 1 else "bci-mi-n-100.xdf"
    X, y = preprocess(xdf)
    print(f"X shape: {X.shape}  |  y distribution: {dict(zip(*np.unique(y.numpy(), return_counts=True)))}")
