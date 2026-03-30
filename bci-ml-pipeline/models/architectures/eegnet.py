#!/usr/bin/env python3
"""
EEGNet: A Compact Convolutional Neural Network for EEG-based Brain-Computer Interfaces

Reference:
    Lawhern, V. J., Solon, A. J., Waytowich, N. R., Gordon, S. M., Hung, C. P., & Lance, B. J. (2018).
    EEGNet: a compact convolutional neural network for EEG-based brain–computer interfaces.
    Journal of neural engineering, 15(5), 056013.

Architecture:
    1. Temporal convolution (learns frequency filters)
    2. Depthwise spatial convolution (learns spatial filters per frequency)
    3. Separable convolution (extracts temporal patterns)
    4. Classification head

This implementation is optimized for 4-class motor imagery classification
from BCI Competition IIIa dataset.
"""

import torch
import torch.nn as nn
import torch.nn.functional as F


class EEGNet(nn.Module):
    """
    EEGNet architecture for EEG classification.

    Args:
        n_classes (int): Number of output classes (default: 4)
        n_channels (int): Number of EEG channels (default: 60)
        n_timepoints (int): Number of time samples per epoch (default: 1000)
        F1 (int): Number of temporal filters (default: 8)
        D (int): Depth multiplier for spatial filters (default: 2)
        F2 (int): Number of pointwise filters, typically F1*D (default: 16)
        kernel_length (int): Length of temporal convolution (default: 64)
        dropout (float): Dropout rate (default: 0.5)
        pool_size (int): Average pooling size (default: 8)
    """

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
        self.F1 = F1
        self.D = D
        self.F2 = F2
        self.dropout = dropout

        # ===== BLOCK 1: Temporal Convolution =====
        # Conv2D: learns temporal filters (frequency-like patterns)
        # Input: (batch, 1, channels, timepoints)
        # Output: (batch, F1, channels, timepoints)
        self.conv1 = nn.Conv2d(
            in_channels=1,
            out_channels=F1,
            kernel_size=(1, kernel_length),
            padding=(0, kernel_length // 2),
            bias=False
        )
        self.bn1 = nn.BatchNorm2d(F1)

        # ===== BLOCK 2: Depthwise Spatial Convolution =====
        # Learns spatial filters for each temporal filter
        # Input: (batch, F1, channels, timepoints)
        # Output: (batch, F1*D, 1, timepoints)
        self.conv2_depthwise = nn.Conv2d(
            in_channels=F1,
            out_channels=F1 * D,
            kernel_size=(n_channels, 1),
            groups=F1,  # Depthwise: each input channel convolved separately
            bias=False
        )
        self.bn2 = nn.BatchNorm2d(F1 * D)
        self.pool2 = nn.AvgPool2d(kernel_size=(1, pool_size))
        self.dropout2 = nn.Dropout(p=dropout)

        # ===== BLOCK 3: Separable Convolution =====
        # Learns higher-level temporal patterns
        # Depthwise temporal convolution
        self.conv3_depthwise = nn.Conv2d(
            in_channels=F1 * D,
            out_channels=F1 * D,
            kernel_size=(1, 16),
            padding=(0, 8),
            groups=F1 * D,
            bias=False
        )
        # Pointwise convolution (1x1 conv to mix channels)
        self.conv3_pointwise = nn.Conv2d(
            in_channels=F1 * D,
            out_channels=F2,
            kernel_size=(1, 1),
            bias=False
        )
        self.bn3 = nn.BatchNorm2d(F2)
        self.pool3 = nn.AvgPool2d(kernel_size=(1, pool_size))
        self.dropout3 = nn.Dropout(p=dropout)

        # ===== CLASSIFIER =====
        # Calculate the size after all convolutions and pooling
        # This depends on input timepoints and pooling operations
        self._feature_size = self._get_feature_size(n_channels, n_timepoints)

        self.fc = nn.Linear(self._feature_size, n_classes)

    def _get_feature_size(self, n_channels: int, n_timepoints: int) -> int:
        """
        Calculate the flattened feature size after all conv/pool layers.
        """
        # Create a dummy input to compute output size
        with torch.no_grad():
            dummy_input = torch.zeros(1, 1, n_channels, n_timepoints)
            x = self.conv1(dummy_input)
            x = self.conv2_depthwise(x)
            x = self.pool2(x)
            x = self.conv3_depthwise(x)
            x = self.conv3_pointwise(x)
            x = self.pool3(x)
            feature_size = x.view(1, -1).shape[1]
        return feature_size

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """
        Forward pass.

        Args:
            x (torch.Tensor): Input tensor of shape (batch, 1, channels, timepoints)

        Returns:
            torch.Tensor: Output logits of shape (batch, n_classes)
        """
        # Block 1: Temporal Convolution
        x = self.conv1(x)
        x = self.bn1(x)
        x = F.elu(x)  # ELU activation after temporal convolution

        # Block 2: Depthwise Spatial Convolution
        x = self.conv2_depthwise(x)
        x = self.bn2(x)
        x = F.elu(x)  # ELU activation
        x = self.pool2(x)
        x = self.dropout2(x)

        # Block 3: Separable Convolution
        x = self.conv3_depthwise(x)
        x = self.conv3_pointwise(x)
        x = self.bn3(x)
        x = F.elu(x)
        x = self.pool3(x)
        x = self.dropout3(x)

        # Flatten and classify
        x = x.view(x.size(0), -1)
        x = self.fc(x)

        return x

    def predict_proba(self, x: torch.Tensor) -> torch.Tensor:
        """
        Get class probabilities using softmax.

        Args:
            x (torch.Tensor): Input tensor

        Returns:
            torch.Tensor: Class probabilities (batch, n_classes)
        """
        logits = self.forward(x)
        return F.softmax(logits, dim=1)

    def predict(self, x: torch.Tensor) -> torch.Tensor:
        """
        Get predicted class labels.

        Args:
            x (torch.Tensor): Input tensor

        Returns:
            torch.Tensor: Predicted class indices (batch,)
        """
        probabilities = self.predict_proba(x)
        return torch.argmax(probabilities, dim=1)


def count_parameters(model: nn.Module) -> int:
    """Count the number of trainable parameters in a model."""
    return sum(p.numel() for p in model.parameters() if p.requires_grad)


def test_eegnet():
    """Test the EEGNet model with dummy data."""
    print("\n" + "="*60)
    print("EEGNet Architecture Test")
    print("="*60)

    # Model parameters (matching BCI Competition IIIa)
    n_classes = 4
    n_channels = 60
    n_timepoints = 1000  # 4 seconds × 250 Hz
    batch_size = 16

    # Create model
    model = EEGNet(
        n_classes=n_classes,
        n_channels=n_channels,
        n_timepoints=n_timepoints,
        F1=8,
        D=2,
        F2=16,
        kernel_length=64,
        dropout=0.5,
        pool_size=8
    )

    print(f"\nModel created:")
    print(f"  Input shape: (batch, 1, {n_channels}, {n_timepoints})")
    print(f"  Output shape: (batch, {n_classes})")
    print(f"  Total parameters: {count_parameters(model):,}")

    # Test forward pass
    dummy_input = torch.randn(batch_size, 1, n_channels, n_timepoints)
    print(f"\nTesting forward pass with batch_size={batch_size}...")

    output = model(dummy_input)
    print(f"  Output shape: {output.shape}")
    print(f"  Output range: [{output.min():.3f}, {output.max():.3f}]")

    # Test prediction
    probabilities = model.predict_proba(dummy_input)
    predictions = model.predict(dummy_input)
    print(f"\n  Probabilities shape: {probabilities.shape}")
    print(f"  Probabilities sum to 1: {probabilities.sum(dim=1).mean():.3f}")
    print(f"  Predictions shape: {predictions.shape}")
    print(f"  Unique predictions: {torch.unique(predictions).tolist()}")

    print("\n" + "="*60)
    print("EEGNet test passed")
    print("="*60 + "\n")


if __name__ == "__main__":
    test_eegnet()
