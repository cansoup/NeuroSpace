"""
train.py — Train EEGNet on the preprocessed BCI Motor Imagery dataset.

Usage:
    python train.py --xdf bci-mi-n-100.xdf --epochs 150 --save model.pt

What this script does:
  1. Loads and preprocesses the .xdf file via preprocessing.py
  2. Splits into stratified train / validation / test sets (70 / 15 / 15)
  3. Trains EEGNet with Adam + OneCycleLR scheduler
  4. Applies early stopping (patience 20 epochs)
  5. Evaluates on held-out test set and prints a confusion matrix
  6. Saves the best model weights to disk for inference
"""

from __future__ import annotations

import argparse
import json
import logging
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from sklearn.model_selection import StratifiedShuffleSplit
from torch.utils.data import DataLoader, TensorDataset

from eegnet import EEGNet
from preprocessing import preprocess

logger = logging.getLogger(__name__)


# ── Helpers ──────────────────────────────────────────────────────────────────

def accuracy(logits: torch.Tensor, targets: torch.Tensor) -> float:
    return (logits.argmax(dim=1) == targets).float().mean().item()


def get_dataloaders(X: torch.Tensor, y: torch.Tensor, batch_size: int = 32):
    """Stratified 70 / 15 / 15 train/val/test split."""
    idx = np.arange(len(y))
    y_np = y.numpy()

    sss_tv = StratifiedShuffleSplit(n_splits=1, test_size=0.30, random_state=42)
    train_idx, temp_idx = next(sss_tv.split(idx, y_np))

    sss_vt = StratifiedShuffleSplit(n_splits=1, test_size=0.50, random_state=42)
    val_idx, test_idx = next(sss_vt.split(temp_idx, y_np[temp_idx]))
    val_idx = temp_idx[val_idx]
    test_idx = temp_idx[test_idx]

    def make_loader(indices, shuffle=False):
        ds = TensorDataset(X[indices], y[indices])
        return DataLoader(ds, batch_size=batch_size, shuffle=shuffle)

    return (
        make_loader(train_idx, shuffle=True),
        make_loader(val_idx),
        make_loader(test_idx),
        test_idx,
    )


def train(
    xdf_path: str,
    save_path: str = "model.pt",
    num_epochs: int = 150,
    lr: float = 1e-3,
    batch_size: int = 32,
    dropout: float = 0.5,
    patience: int = 20,
    num_classes: int = 2,
) -> dict:
    # ── Data ─────────────────────────────────────────────────────────────
    logger.info("Preprocessing %s …", xdf_path)
    X, y = preprocess(xdf_path)

    _, n_channels, n_times = X.shape[0], X.shape[2], X.shape[3]
    logger.info("Trials: %d | Channels: %d | Samples/trial: %d", len(y), n_channels, n_times)

    train_loader, val_loader, test_loader, test_idx = get_dataloaders(X, y, batch_size)

    # ── Model ─────────────────────────────────────────────────────────────
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    logger.info("Device: %s", device)

    model = EEGNet(
        num_classes=num_classes,
        channels=n_channels,
        samples=n_times,
        dropout_rate=dropout,
    ).to(device)

    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.OneCycleLR(
        optimizer, max_lr=lr, steps_per_epoch=len(train_loader), epochs=num_epochs
    )

    # ── Training loop ─────────────────────────────────────────────────────
    best_val_acc = 0.0
    epochs_no_improve = 0
    history: list[dict] = []

    for epoch in range(1, num_epochs + 1):
        model.train()
        train_losses, train_accs = [], []
        for Xb, yb in train_loader:
            Xb, yb = Xb.to(device), yb.to(device)
            optimizer.zero_grad()
            logits = model(Xb)
            loss = criterion(logits, yb)
            loss.backward()
            optimizer.step()
            scheduler.step()
            train_losses.append(loss.item())
            train_accs.append(accuracy(logits, yb))

        model.eval()
        val_losses, val_accs = [], []
        with torch.no_grad():
            for Xb, yb in val_loader:
                Xb, yb = Xb.to(device), yb.to(device)
                logits = model(Xb)
                val_losses.append(criterion(logits, yb).item())
                val_accs.append(accuracy(logits, yb))

        t_loss = np.mean(train_losses)
        t_acc = np.mean(train_accs)
        v_loss = np.mean(val_losses)
        v_acc = np.mean(val_accs)

        history.append({"epoch": epoch, "train_loss": t_loss, "train_acc": t_acc,
                         "val_loss": v_loss, "val_acc": v_acc})

        if epoch % 10 == 0 or epoch == 1:
            logger.info(
                "Epoch %3d/%d | train_loss=%.4f acc=%.3f | val_loss=%.4f acc=%.3f",
                epoch, num_epochs, t_loss, t_acc, v_loss, v_acc,
            )

        # Early stopping
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
                    },
                    "best_val_acc": best_val_acc,
                    "epoch": epoch,
                },
                save_path,
            )
        else:
            epochs_no_improve += 1
            if epochs_no_improve >= patience:
                logger.info("Early stopping at epoch %d (patience=%d).", epoch, patience)
                break

    # ── Test evaluation ───────────────────────────────────────────────────
    checkpoint = torch.load(save_path, map_location=device, weights_only=False)
    model.load_state_dict(checkpoint["model_state"])
    model.eval()

    all_preds, all_targets = [], []
    with torch.no_grad():
        for Xb, yb in test_loader:
            Xb = Xb.to(device)
            preds = model(Xb).argmax(dim=1).cpu().numpy()
            all_preds.extend(preds)
            all_targets.extend(yb.numpy())

    all_preds = np.array(all_preds)
    all_targets = np.array(all_targets)
    test_acc = (all_preds == all_targets).mean()

    class_names = ["left", "right"] if num_classes == 2 else [str(i) for i in range(num_classes)]
    print("\n" + "=" * 50)
    print(f"  Test Accuracy: {test_acc * 100:.1f}%")
    print(f"  Best Val Acc : {best_val_acc * 100:.1f}%")
    print("=" * 50)

    # Confusion matrix
    print("\nConfusion Matrix (rows=true, cols=pred):")
    print(f"{'':>10}", end="")
    for cn in class_names:
        print(f"{cn:>10}", end="")
    print()
    for i, cn in enumerate(class_names):
        print(f"{cn:>10}", end="")
        for j in range(num_classes):
            print(f"{int(np.sum((all_targets == i) & (all_preds == j))):>10}", end="")
        print()
    print()

    # Save history
    hist_path = Path(save_path).with_suffix(".history.json")
    with open(hist_path, "w") as f:
        json.dump(history, f, indent=2)
    logger.info("Training history saved to %s", hist_path)

    return {"test_acc": test_acc, "best_val_acc": best_val_acc, "history": history}


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")

    parser = argparse.ArgumentParser(description="Train EEGNet on BCI Motor Imagery data")
    parser.add_argument("--xdf", required=True, help="Path to .xdf dataset file")
    parser.add_argument("--save", default="model.pt", help="Output model file (.pt)")
    parser.add_argument("--epochs", type=int, default=150)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--dropout", type=float, default=0.5)
    parser.add_argument("--patience", type=int, default=20)
    parser.add_argument("--classes", type=int, default=2, help="2=left/right MVP, 6=full directional")
    args = parser.parse_args()

    train(
        xdf_path=args.xdf,
        save_path=args.save,
        num_epochs=args.epochs,
        lr=args.lr,
        batch_size=args.batch_size,
        dropout=args.dropout,
        patience=args.patience,
        num_classes=args.classes,
    )
