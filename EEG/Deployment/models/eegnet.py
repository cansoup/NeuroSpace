#!/usr/bin/env python3
"""
EEGNet: A Compact Convolutional Neural Network for EEG-based Brain-Computer Interfaces

Reference:
    Lawhern, V. J., Solon, A. J., Waytowich, N. R., Gordon, S. M., Hung, C. P., & Lance, B. J. (2018).
    EEGNet: a compact convolutional neural network for EEG-based brain-computer interfaces.
    Journal of neural engineering, 15(5), 056013.
"""

import torch
import torch.nn as nn
import torch.nn.functional as F


class EEGNet(nn.Module):
    def __init__(
        self,
        n_classes: int = 4,
        n_channels: int = 60,
        n_timepoints: int = 1000,
        F1: int = 8,
        D: int = 2,
        F2: int = 16,
        kernel_length: int = 64,
        dropout: float = 0.5,
        pool_size: int = 8
    ):
        super(EEGNet, self).__init__()

        self.n_classes = n_classes
        self.n_channels = n_channels
        self.n_timepoints = n_timepoints

        self.conv1 = nn.Conv2d(1, F1, kernel_size=(1, kernel_length),
                               padding=(0, kernel_length // 2), bias=False)
        self.bn1 = nn.BatchNorm2d(F1)

        self.conv2_depthwise = nn.Conv2d(F1, F1 * D, kernel_size=(n_channels, 1),
                                         groups=F1, bias=False)
        self.bn2 = nn.BatchNorm2d(F1 * D)
        self.pool2 = nn.AvgPool2d(kernel_size=(1, pool_size))
        self.dropout2 = nn.Dropout(p=dropout)

        self.conv3_depthwise = nn.Conv2d(F1 * D, F1 * D, kernel_size=(1, 16),
                                         padding=(0, 8), groups=F1 * D, bias=False)
        self.conv3_pointwise = nn.Conv2d(F1 * D, F2, kernel_size=(1, 1), bias=False)
        self.bn3 = nn.BatchNorm2d(F2)
        self.pool3 = nn.AvgPool2d(kernel_size=(1, pool_size))
        self.dropout3 = nn.Dropout(p=dropout)

        self._feature_size = self._get_feature_size(n_channels, n_timepoints)
        self.fc = nn.Linear(self._feature_size, n_classes)

    def _get_feature_size(self, n_channels, n_timepoints):
        with torch.no_grad():
            dummy = torch.zeros(1, 1, n_channels, n_timepoints)
            x = self.conv1(dummy)
            x = self.conv2_depthwise(x)
            x = self.pool2(x)
            x = self.conv3_depthwise(x)
            x = self.conv3_pointwise(x)
            x = self.pool3(x)
            return x.view(1, -1).shape[1]

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = F.elu(self.bn1(self.conv1(x)))
        x = self.dropout2(self.pool2(F.elu(self.bn2(self.conv2_depthwise(x)))))
        x = self.dropout3(self.pool3(F.elu(self.bn3(self.conv3_pointwise(self.conv3_depthwise(x))))))
        return self.fc(x.view(x.size(0), -1))

    def predict_proba(self, x):
        return F.softmax(self.forward(x), dim=1)

    def predict(self, x):
        return torch.argmax(self.predict_proba(x), dim=1)


def count_parameters(model):
    return sum(p.numel() for p in model.parameters() if p.requires_grad)
