"""
train_cv.py — Leave-one-out / k-fold cross-validated EEGNet training.

Designed for small datasets like bci-mi-n-100.xdf (200 trials).
Uses data augmentation on training folds only to avoid leakage.

Usage:
    python train_cv.py --xdf bci-mi-n-100.xdf --folds 5 --save model.pt

What this script does:
  1. Preprocess the .xdf file
  2. Run k-fold stratified cross-validation
  3. Augment each training fold (4× synthetic trials per real trial)
  4. Train EEGNet per fold, keep the best checkpoint
  5. Report mean ± std accuracy across folds
  6. Save the best single-fold model for inference
"""

from __future__ import annotations

import argparse
import logging
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from sklearn.model_selection import StratifiedKFold
from torch.utils.data import DataLoader, TensorDataset

from augment import augment_dataset
from eegnet import EEGNet
from preprocessing import preprocess

logger = logging.getLogger(__name__)


def accuracy(logits: torch.Tensor, targets: torch.Tensor) -> float:
    return (logits.argmax(dim=1) == targets).float().mean().item()


def train_fold(
    X_train: np.ndarray,
    y_train: np.ndarray,
    X_val: np.ndarray,
    y_val: np.ndarray,
    n_channels: int,
    n_times: int,
    num_classes: int,
    num_epochs: int,
    lr: float,
    batch_size: int,
    dropout: float,
    patience: int,
    device: torch.device,
    save_path: str,
    fold: int,
    n_augments: int = 4,
) -> tuple[float, float]:
    """Train one fold, return (best_val_acc, final_train_acc)."""

    # ── Augment training fold ──────────────────────────────────────────────
    logger.info("  Fold %d: augmenting %d → %d training trials …",
                fold, len(y_train), len(y_train) * (1 + n_augments))
    X_aug, y_aug = augment_dataset(X_train, y_train, n_augments=n_augments,
                                   random_state=fold * 7)

    # Convert to tensors
    Xt = torch.from_numpy(X_aug.astype(np.float32))
    yt = torch.from_numpy(y_aug.astype(np.int64))
    Xv = torch.from_numpy(X_val.astype(np.float32))
    yv = torch.from_numpy(y_val.astype(np.int64))

    train_loader = DataLoader(TensorDataset(Xt, yt), batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(TensorDataset(Xv, yv), batch_size=batch_size)

    # ── Model ──────────────────────────────────────────────────────────────
    model = EEGNet(
        num_classes=num_classes,
        channels=n_channels,
        samples=n_times,
        dropout_rate=dropout,
        F1=8, D=2, F2=16,
    ).to(device)

    criterion = nn.CrossEntropyLoss(label_smoothing=0.1)
    optimizer = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=1e-3)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=num_epochs)

    best_val_acc = 0.0
    epochs_no_improve = 0

    for epoch in range(1, num_epochs + 1):
        model.train()
        train_accs = []
        for Xb, yb in train_loader:
            Xb, yb = Xb.to(device), yb.to(device)
            optimizer.zero_grad()
            logits = model(Xb)
            loss = criterion(logits, yb)
            loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()
            train_accs.append(accuracy(logits, yb))
        scheduler.step()

        model.eval()
        val_accs = []
        with torch.no_grad():
            for Xb, yb in val_loader:
                Xb, yb = Xb.to(device), yb.to(device)
                val_accs.append(accuracy(model(Xb), yb))

        v_acc = float(np.mean(val_accs))
        t_acc = float(np.mean(train_accs))

        if v_acc > best_val_acc:
            best_val_acc = v_acc
            epochs_no_improve = 0
            torch.save(
                {
                    "model_state": model.state_dict(),
                    "config": {
                        "num_classes": num_classes,
                        "channels": n_channels,
                        "samples": n_times,
                        "dropout_rate": dropout,
                        "F1": 8, "D": 2, "F2": 16,
                    },
                    "best_val_acc": best_val_acc,
                    "epoch": epoch,
                    "fold": fold,
                },
                save_path,
            )
        else:
            epochs_no_improve += 1
            if epochs_no_improve >= patience:
                logger.info("    Early stop epoch %d (best val=%.3f)", epoch, best_val_acc)
                break

    return best_val_acc, t_acc


def cross_validate(
    xdf_path: str,
    save_path: str = "model.pt",
    n_folds: int = 5,
    num_epochs: int = 300,
    lr: float = 5e-4,
    batch_size: int = 16,
    dropout: float = 0.3,
    patience: int = 40,
    num_classes: int = 2,
    n_augments: int = 4,
) -> dict:

    logger.info("Preprocessing %s …", xdf_path)
    X_tensor, y_tensor = preprocess(xdf_path)
    X = X_tensor.numpy()
    y = y_tensor.numpy()

    n_channels = X.shape[2]
    n_times = X.shape[3]
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    logger.info("Device: %s | Shape: %s | Classes: %d", device, X.shape, num_classes)

    skf = StratifiedKFold(n_splits=n_folds, shuffle=True, random_state=42)
    fold_accs = []
    best_overall = 0.0
    best_save = Path(save_path)

    for fold, (train_idx, val_idx) in enumerate(skf.split(X, y), start=1):
        logger.info("── Fold %d/%d (train=%d, val=%d) ──", fold, n_folds,
                    len(train_idx), len(val_idx))

        fold_path = str(best_save.with_stem(best_save.stem + f"_fold{fold}"))

        val_acc, _ = train_fold(
            X_train=X[train_idx],
            y_train=y[train_idx],
            X_val=X[val_idx],
            y_val=y[val_idx],
            n_channels=n_channels,
            n_times=n_times,
            num_classes=num_classes,
            num_epochs=num_epochs,
            lr=lr,
            batch_size=batch_size,
            dropout=dropout,
            patience=patience,
            device=device,
            save_path=fold_path,
            fold=fold,
            n_augments=n_augments,
        )

        fold_accs.append(val_acc)
        logger.info("  Fold %d val acc: %.3f", fold, val_acc)

        # Keep the best fold model as the final model
        if val_acc > best_overall:
            best_overall = val_acc
            import shutil
            shutil.copy(fold_path, save_path)

    mean_acc = float(np.mean(fold_accs))
    std_acc = float(np.std(fold_accs))

    print("\n" + "=" * 55)
    print(f"  {n_folds}-Fold Cross-Validation Results")
    print(f"  Accuracy per fold: {[f'{a*100:.1f}%' for a in fold_accs]}")
    print(f"  Mean ± Std : {mean_acc*100:.1f}% ± {std_acc*100:.1f}%")
    print(f"  Best fold  : {best_overall*100:.1f}%")
    print(f"  Model saved: {save_path}")
    print("=" * 55 + "\n")

    return {
        "fold_accs": fold_accs,
        "mean_acc": mean_acc,
        "std_acc": std_acc,
        "best_acc": best_overall,
    }


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")

    parser = argparse.ArgumentParser(description="Cross-validated EEGNet training with augmentation")
    parser.add_argument("--xdf", required=True)
    parser.add_argument("--save", default="model.pt")
    parser.add_argument("--folds", type=int, default=5)
    parser.add_argument("--epochs", type=int, default=300)
    parser.add_argument("--lr", type=float, default=5e-4)
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--dropout", type=float, default=0.3)
    parser.add_argument("--patience", type=int, default=40)
    parser.add_argument("--classes", type=int, default=2)
    parser.add_argument("--augments", type=int, default=4,
                        help="Synthetic copies per real trial in training fold")
    args = parser.parse_args()

    cross_validate(
        xdf_path=args.xdf,
        save_path=args.save,
        n_folds=args.folds,
        num_epochs=args.epochs,
        lr=args.lr,
        batch_size=args.batch_size,
        dropout=args.dropout,
        patience=args.patience,
        num_classes=args.classes,
        n_augments=args.augments,
    )
