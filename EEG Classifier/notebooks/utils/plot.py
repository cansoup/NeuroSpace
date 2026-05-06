"""Plotting helpers. Matplotlib only."""

from __future__ import annotations

import numpy as np
import matplotlib.pyplot as plt


def plot_confusion(cm, classes: dict, ax=None, title: str = ""):
    cm = np.asarray(cm)
    if ax is None:
        _, ax = plt.subplots(figsize=(4, 4))
    cm_norm = cm / cm.sum(axis=1, keepdims=True).clip(min=1)
    im = ax.imshow(cm_norm, cmap="Blues", vmin=0, vmax=1)
    labels = [classes[i] for i in sorted(classes)]
    ax.set_xticks(range(len(labels)), labels, rotation=45, ha="right")
    ax.set_yticks(range(len(labels)), labels)
    ax.set_xlabel("predicted")
    ax.set_ylabel("true")
    if title:
        ax.set_title(title)
    for i in range(cm.shape[0]):
        for j in range(cm.shape[1]):
            ax.text(j, i, f"{cm[i,j]}", ha="center", va="center",
                    color="white" if cm_norm[i, j] > 0.5 else "black",
                    fontsize=9)
    return ax


def plot_erp(X, y, classes: dict, srate: int = 250, channel: int = 0,
             ax=None):
    """Mean trial trace per class, for one channel."""
    if ax is None:
        _, ax = plt.subplots(figsize=(8, 3))
    t = np.arange(X.shape[-1]) / srate
    for label, name in classes.items():
        sel = X[y == label, channel]
        if len(sel) == 0:
            continue
        mean = sel.mean(0)
        sem = sel.std(0) / np.sqrt(len(sel))
        ax.plot(t, mean, label=f"{name} (n={len(sel)})")
        ax.fill_between(t, mean - sem, mean + sem, alpha=0.2)
    ax.set_xlabel("time (s)")
    ax.set_ylabel("amplitude (z)")
    ax.set_title(f"ERP — channel {channel}")
    ax.legend(fontsize=8)
    return ax


def plot_psd(X, srate: int = 250, band=(1, 40), ax=None, label: str = ""):
    """Average PSD across trials, one line per channel."""
    from scipy.signal import welch

    if ax is None:
        _, ax = plt.subplots(figsize=(8, 3))
    n_ch = X.shape[1]
    for ch in range(n_ch):
        data = X[:, ch, :].reshape(-1)
        f, pxx = welch(data, fs=srate, nperseg=min(256, data.shape[-1]))
        mask = (f >= band[0]) & (f <= band[1])
        ax.semilogy(f[mask], pxx[mask], label=f"ch{ch} {label}".strip())
    ax.set_xlabel("Hz")
    ax.set_ylabel("PSD")
    ax.legend(fontsize=7)
    return ax
