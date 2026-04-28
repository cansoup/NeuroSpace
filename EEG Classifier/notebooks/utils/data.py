"""
Data loading and preprocessing — mirrors the semantics of
`eeg_online_classifier.py` so notebooks stay deployment-compatible.
"""

from __future__ import annotations

import numpy as np
from scipy.signal import butter, filtfilt, lfilter, iirnotch

SRATE_DEFAULT = 250
CHANNELS_DEFAULT = [0, 1, 3, 4]          # C3/C4 area, skipping saturated ch2
NOTCH_HZ = 50.0
BAND_DEFAULT = (8.0, 30.0)               # mu + beta MI bands
WINDOW_SEC_DEFAULT = 2.5

ALL_MARKERS = {769: "left", 770: "right", 773: "both"}
DEFAULT_CLASSES = {0: "left", 1: "right", 2: "both"}


def _design_filters(band, srate):
    nyq = 0.5 * srate
    b_bp, a_bp = butter(4, [band[0] / nyq, band[1] / nyq], btype="band")
    b_nt, a_nt = iirnotch(NOTCH_HZ / nyq, 30)
    return (b_bp, a_bp), (b_nt, a_nt)


def preprocess(data: np.ndarray, band=BAND_DEFAULT, srate=SRATE_DEFAULT,
               zero_phase: bool = True) -> np.ndarray:
    """(n_samples, n_channels) → notch → bandpass → z-score. Same as
    `eeg_online_classifier.preprocess` with configurable band."""
    (b_bp, a_bp), (b_nt, a_nt) = _design_filters(band, srate)
    filt = filtfilt if zero_phase else lfilter
    out = filt(b_nt, a_nt, data, axis=0)
    out = filt(b_bp, a_bp, out, axis=0)
    out = (out - out.mean(axis=0)) / (out.std(axis=0) + 1e-8)
    return out.astype(np.float32)


def load_xdf_epochs(
    xdf_path: str,
    window_sec: float = WINDOW_SEC_DEFAULT,
    channels=CHANNELS_DEFAULT,
    srate: int = SRATE_DEFAULT,
    band=BAND_DEFAULT,
    zero_phase: bool = True,
):
    """
    Load XDF, epoch on MI-cue markers, preprocess.

    Returns
    -------
    X : np.ndarray, (n_trials, n_channels, n_samples)
    y : np.ndarray, (n_trials,)
    classes : dict[int, str]   e.g. {0: 'left', 1: 'right', 2: 'both'}
    """
    import pyxdf

    streams, _ = pyxdf.load_xdf(xdf_path)
    eeg = next(s for s in streams if s["info"]["type"][0] == "EEG")
    mk = next(s for s in streams if s["info"]["type"][0] == "Markers")

    eeg_data = np.asarray(eeg["time_series"])[:, channels]
    eeg_times = np.asarray(eeg["time_stamps"])
    mk_times = np.asarray(mk["time_stamps"])
    mk_values = np.array([int(v[0]) for v in mk["time_series"]])

    present = sorted(m for m in ALL_MARKERS if m in mk_values)
    if not present:
        raise ValueError("No recognised MI markers (769/770/773) in XDF.")
    marker_to_label = {m: i for i, m in enumerate(present)}
    classes = {i: ALL_MARKERS[m] for m, i in marker_to_label.items()}

    n_samples = int(window_sec * srate)
    X, y = [], []
    for mt, mv in zip(mk_times, mk_values):
        if mv not in marker_to_label:
            continue
        idx = np.searchsorted(eeg_times, mt)
        end = idx + n_samples
        if end > len(eeg_data):
            continue
        epoch = preprocess(eeg_data[idx:end], band=band, srate=srate,
                           zero_phase=zero_phase)
        X.append(epoch.T)                    # (ch, time)
        y.append(marker_to_label[mv])

    X = np.stack(X).astype(np.float32)
    y = np.array(y, dtype=np.int64)
    return X, y, classes
