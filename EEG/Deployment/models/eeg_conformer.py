"""
EEG Conformer: convolutional + transformer hybrid for EEG decoding.

Reference:
    Song et al., "EEG Conformer: Convolutional transformer for EEG decoding
    and visualization", IEEE TNSRE 2023.
    https://ieeexplore.ieee.org/document/9991178

Adapted to 8-channel motor imagery input (1, 1, 8, 1001).
"""

from __future__ import annotations

import torch
import torch.nn as nn


class PatchEmbedding(nn.Module):
    """
    Conv stem that maps raw EEG to a sequence of token embeddings.

    Input:  (B, 1, n_channels, n_times)
    Output: (B, n_tokens, embed_dim)
    """

    def __init__(self, n_channels: int = 8, n_times: int = 1001,
                 f1: int = 40, kernel_t: int = 25,
                 pool_kernel: int = 75, pool_stride: int = 15,
                 dropout: float = 0.5):
        super().__init__()
        self.temporal_conv = nn.Conv2d(1, f1, kernel_size=(1, kernel_t), padding=(0, 0))
        self.spatial_conv = nn.Conv2d(f1, f1, kernel_size=(n_channels, 1))
        self.bn = nn.BatchNorm2d(f1)
        self.act = nn.ELU()
        self.pool = nn.AvgPool2d(kernel_size=(1, pool_kernel), stride=(1, pool_stride))
        self.dropout = nn.Dropout(dropout)
        self.proj = nn.Conv2d(f1, f1, kernel_size=(1, 1))
        self.embed_dim = f1

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self.temporal_conv(x)
        x = self.spatial_conv(x)
        x = self.bn(x)
        x = self.act(x)
        x = self.pool(x)
        x = self.dropout(x)
        x = self.proj(x)
        x = x.squeeze(2)
        x = x.permute(0, 2, 1)
        return x


class TransformerEncoder(nn.Module):
    def __init__(self, embed_dim: int, n_heads: int, mlp_ratio: int, dropout: float):
        super().__init__()
        self.norm1 = nn.LayerNorm(embed_dim)
        self.attn = nn.MultiheadAttention(embed_dim, n_heads, dropout=dropout, batch_first=True)
        self.norm2 = nn.LayerNorm(embed_dim)
        hidden = embed_dim * mlp_ratio
        self.mlp = nn.Sequential(
            nn.Linear(embed_dim, hidden),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(hidden, embed_dim),
            nn.Dropout(dropout),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        h = self.norm1(x)
        attn_out, _ = self.attn(h, h, h, need_weights=False)
        x = x + attn_out
        x = x + self.mlp(self.norm2(x))
        return x


class EEGConformer(nn.Module):
    """
    EEG Conformer adapted for 8-channel input.

    Args:
        n_channels: number of EEG channels (default 8 for OpenBCI).
        n_classes:  output classes (3 = left/right/both).
        n_times:    samples per epoch (1001 = 4 s @ 250 Hz, endpoint inclusive).
        f1:         conv stem feature count == transformer embed dim.
        depth:      number of transformer encoder layers.
        n_heads:    attention heads.
        mlp_ratio:  feed-forward hidden multiplier in transformer block.
        dropout:    dropout rate (used in conv stem and transformer).
    """

    def __init__(self, n_channels: int = 8, n_classes: int = 3, n_times: int = 1001,
                 f1: int = 40, depth: int = 6, n_heads: int = 10,
                 mlp_ratio: int = 4, dropout: float = 0.5):
        super().__init__()
        self.embed = PatchEmbedding(
            n_channels=n_channels, n_times=n_times,
            f1=f1, dropout=dropout,
        )
        with torch.no_grad():
            dummy = torch.zeros(1, 1, n_channels, n_times)
            tokens = self.embed(dummy)
            n_tokens, embed_dim = tokens.shape[1], tokens.shape[2]

        self.pos = nn.Parameter(torch.zeros(1, n_tokens, embed_dim))
        nn.init.trunc_normal_(self.pos, std=0.02)

        self.blocks = nn.ModuleList([
            TransformerEncoder(embed_dim, n_heads, mlp_ratio, dropout)
            for _ in range(depth)
        ])
        self.norm = nn.LayerNorm(embed_dim)

        self.head = nn.Sequential(
            nn.Linear(n_tokens * embed_dim, 256),
            nn.ELU(),
            nn.Dropout(dropout),
            nn.Linear(256, 32),
            nn.ELU(),
            nn.Dropout(dropout),
            nn.Linear(32, n_classes),
        )

        self.n_tokens = n_tokens
        self.embed_dim = embed_dim

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self.embed(x)
        x = x + self.pos
        for block in self.blocks:
            x = block(x)
        x = self.norm(x)
        x = x.flatten(1)
        return self.head(x)


def count_parameters(model: nn.Module) -> int:
    return sum(p.numel() for p in model.parameters() if p.requires_grad)
