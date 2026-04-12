"""
augment.py — Data augmentation for small EEG Motor Imagery datasets.

Techniques used:
  1. Gaussian noise injection
  2. Time-warping (random stretch/compress via resampling)
  3. Amplitude scaling
  4. Channel dropout (zero out a random channel)
  5. Sliding-window cropping (multiple crops per trial)

All functions operate on numpy arrays of shape (C, T).
"""

from __future__ import annotations

import numpy as np
from scipy.signal import resample


def add_gaussian_noise(epoch: np.ndarray, snr_db: float = 20.0) -> np.ndarray:
    """Add Gaussian noise at a given SNR (in dB)."""
    signal_power = np.mean(epoch ** 2)
    noise_power = signal_power / (10 ** (snr_db / 10))
    noise = np.random.normal(0, np.sqrt(noise_power), epoch.shape)
    return epoch + noise


def amplitude_scale(epoch: np.ndarray, scale_range: tuple = (0.8, 1.2)) -> np.ndarray:
    """Randomly scale amplitude within [scale_min, scale_max]."""
    scale = np.random.uniform(*scale_range)
    return epoch * scale


def time_warp(epoch: np.ndarray, warp_range: tuple = (0.9, 1.1)) -> np.ndarray:
    """Stretch/compress the time axis and resample back to original length."""
    C, T = epoch.shape
    factor = np.random.uniform(*warp_range)
    new_T = int(T * factor)
    warped = resample(epoch, new_T, axis=1)
    return resample(warped, T, axis=1)


def channel_dropout(epoch: np.ndarray, p: float = 0.1) -> np.ndarray:
    """Zero out each channel independently with probability p."""
    mask = np.random.binomial(1, 1 - p, size=(epoch.shape[0], 1)).astype(np.float32)
    return epoch * mask


def random_crop(epoch: np.ndarray, crop_frac: float = 0.85) -> np.ndarray:
    """Return a random contiguous crop of the time axis, resampled to original T."""
    C, T = epoch.shape
    crop_len = int(T * crop_frac)
    start = np.random.randint(0, T - crop_len + 1)
    cropped = epoch[:, start:start + crop_len]
    return resample(cropped, T, axis=1)


def augment_epoch(epoch: np.ndarray, n_augments: int = 3) -> list[np.ndarray]:
    """
    Generate n_augments augmented copies of a single epoch (C, T).
    Returns a list of augmented epochs (does not include the original).
    """
    augmented = []
    ops = [
        lambda e: add_gaussian_noise(e, snr_db=np.random.uniform(15, 25)),
        lambda e: amplitude_scale(e),
        lambda e: time_warp(e),
        lambda e: channel_dropout(e, p=0.1),
        lambda e: random_crop(e, crop_frac=np.random.uniform(0.8, 0.95)),
    ]
    for _ in range(n_augments):
        aug = epoch.copy()
        # Apply 2–3 random ops
        chosen = np.random.choice(len(ops), size=np.random.randint(2, 4), replace=False)
        for idx in chosen:
            aug = ops[idx](aug)
        augmented.append(aug)
    return augmented


def augment_dataset(
    X: np.ndarray,
    y: np.ndarray,
    n_augments: int = 4,
    random_state: int = 42,
) -> tuple[np.ndarray, np.ndarray]:
    """
    Augment a full dataset.

    Parameters
    ----------
    X : (N, 1, C, T)  float32
    y : (N,)           int64
    n_augments : int   number of synthetic copies per real trial

    Returns
    -------
    X_aug : (N * (1 + n_augments), 1, C, T)
    y_aug : (N * (1 + n_augments),)
    """
    np.random.seed(random_state)
    X_list = [X]
    y_list = [y]

    for i in range(len(X)):
        epoch = X[i, 0]   # (C, T)
        for aug_epoch in augment_epoch(epoch, n_augments=n_augments):
            X_list.append(aug_epoch[np.newaxis, np.newaxis])   # (1,1,C,T)
            y_list.append(y[i : i + 1])

    X_aug = np.concatenate(X_list, axis=0)
    y_aug = np.concatenate(y_list, axis=0)
    return X_aug, y_aug
