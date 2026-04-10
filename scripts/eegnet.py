"""
EEGNet — compact CNN for EEG Motor Imagery classification.

Architecture from:
  Lawhern et al. (2018). EEGNet: a compact convolutional neural network for
  EEG-based brain-computer interfaces. Journal of Neural Engineering, 15(5).

Input shape: (batch, 1, C, T)
  C = number of EEG channels
  T = number of time samples

Two variants:
  - EEGNet2  : binary left / right  (MVP)
  - EEGNet6  : 6-class for full directional intent
"""

from __future__ import annotations

import torch
import torch.nn as nn
import torch.nn.functional as F


class EEGNet(nn.Module):
    """
    Parameters
    ----------
    num_classes : int
        Number of output classes.
    channels : int
        Number of EEG channels (C).
    samples : int
        Number of time samples per trial (T).
    dropout_rate : float
        Dropout probability used in both blocks.
    kern_length : int
        Temporal convolution kernel length (Block 1).
        Typically 2 × sampling_rate / 2 → 64 for 250 Hz.
    F1 : int
        Number of temporal filters (Block 1).
    D : int
        Depth multiplier for depthwise convolution (Block 1).
    F2 : int
        Number of separable filters (Block 2).  Usually F1 * D.
    """

    def __init__(
        self,
        num_classes: int = 2,
        channels: int = 8,
        samples: int = 500,
        dropout_rate: float = 0.5,
        kern_length: int = 64,
        F1: int = 8,
        D: int = 2,
        F2: int = 16,
    ) -> None:
        super().__init__()

        # ── Block 1 ────────────────────────────────────────────────────────
        # Temporal convolution
        self.conv1 = nn.Conv2d(
            1, F1, (1, kern_length), padding=(0, kern_length // 2), bias=False
        )
        self.bn1 = nn.BatchNorm2d(F1)

        # Depthwise spatial convolution
        self.depthwise = nn.Conv2d(
            F1, F1 * D, (channels, 1), groups=F1, bias=False
        )
        self.bn2 = nn.BatchNorm2d(F1 * D)
        self.pool1 = nn.AvgPool2d((1, 4))
        self.drop1 = nn.Dropout(p=dropout_rate)

        # ── Block 2 ────────────────────────────────────────────────────────
        # Separable convolution (depthwise + pointwise)
        self.separable = nn.Conv2d(
            F1 * D, F1 * D, (1, 16), padding=(0, 8), groups=F1 * D, bias=False
        )
        self.pointwise = nn.Conv2d(F1 * D, F2, (1, 1), bias=False)
        self.bn3 = nn.BatchNorm2d(F2)
        self.pool2 = nn.AvgPool2d((1, 8))
        self.drop2 = nn.Dropout(p=dropout_rate)

        # ── Classifier ─────────────────────────────────────────────────────
        # Compute flattened size dynamically
        with torch.no_grad():
            dummy = torch.zeros(1, 1, channels, samples)
            flat_size = self._forward_features(dummy).shape[1]

        self.fc = nn.Linear(flat_size, num_classes)

    # ------------------------------------------------------------------
    def _forward_features(self, x: torch.Tensor) -> torch.Tensor:
        # Block 1
        x = self.bn1(self.conv1(x))
        x = F.elu(self.bn2(self.depthwise(x)))
        x = self.drop1(self.pool1(x))

        # Block 2
        x = self.separable(x)
        x = F.elu(self.bn3(self.pointwise(x)))
        x = self.drop2(self.pool2(x))

        return x.flatten(1)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.fc(self._forward_features(x))
