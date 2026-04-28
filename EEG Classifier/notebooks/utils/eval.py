"""
Shared CV evaluation harness. Every notebook uses the same folds so
benchmark numbers are comparable.
"""

from __future__ import annotations

import pickle
from pathlib import Path
from typing import Callable

import numpy as np
from sklearn.metrics import (
    accuracy_score,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
)
from sklearn.model_selection import StratifiedKFold

RESULTS_DIR = Path(__file__).resolve().parents[1] / "results"
RESULTS_DIR.mkdir(exist_ok=True)


def cv_score(
    fit_predict: Callable,
    X: np.ndarray,
    y: np.ndarray,
    n_splits: int = 5,
    seed: int = 42,
) -> dict:
    """
    fit_predict(X_tr, y_tr, X_val, y_val) -> y_pred on X_val.

    Returns aggregated metrics across folds plus per-fold arrays.
    """
    skf = StratifiedKFold(n_splits=n_splits, shuffle=True, random_state=seed)
    n_classes = int(y.max()) + 1

    fold_acc, fold_prec, fold_rec, fold_f1 = [], [], [], []
    fold_per_class_f1 = []
    cm_total = np.zeros((n_classes, n_classes), dtype=np.int64)
    all_true, all_pred = [], []

    for tr_idx, val_idx in skf.split(X, y):
        y_pred = fit_predict(X[tr_idx], y[tr_idx], X[val_idx], y[val_idx])
        y_true = y[val_idx]

        fold_acc.append(accuracy_score(y_true, y_pred))
        fold_prec.append(precision_score(y_true, y_pred, average="macro",
                                         zero_division=0))
        fold_rec.append(recall_score(y_true, y_pred, average="macro",
                                     zero_division=0))
        fold_f1.append(f1_score(y_true, y_pred, average="macro",
                                zero_division=0))
        fold_per_class_f1.append(
            f1_score(y_true, y_pred, average=None, labels=list(range(n_classes)),
                     zero_division=0)
        )
        cm_total += confusion_matrix(y_true, y_pred,
                                     labels=list(range(n_classes)))
        all_true.append(y_true)
        all_pred.append(y_pred)

    return {
        "accuracy": float(np.mean(fold_acc)),
        "accuracy_std": float(np.std(fold_acc)),
        "precision_macro": float(np.mean(fold_prec)),
        "recall_macro": float(np.mean(fold_rec)),
        "f1_macro": float(np.mean(fold_f1)),
        "f1_macro_std": float(np.std(fold_f1)),
        "per_class_f1": np.mean(fold_per_class_f1, axis=0).tolist(),
        "confusion": cm_total.tolist(),
        "fold_accuracy": fold_acc,
        "fold_f1": fold_f1,
        "y_true": np.concatenate(all_true).tolist(),
        "y_pred": np.concatenate(all_pred).tolist(),
    }


def summarise(name: str, result: dict, classes: dict) -> dict:
    """Flat row suitable for a pandas DataFrame."""
    row = {
        "model": name,
        "accuracy": f"{result['accuracy']:.3f} ± {result['accuracy_std']:.3f}",
        "precision_macro": round(result["precision_macro"], 3),
        "recall_macro": round(result["recall_macro"], 3),
        "f1_macro": f"{result['f1_macro']:.3f} ± {result['f1_macro_std']:.3f}",
    }
    for i, name_i in classes.items():
        row[f"f1_{name_i}"] = round(result["per_class_f1"][i], 3)
    return row


def save_result(name: str, result: dict, classes: dict) -> Path:
    path = RESULTS_DIR / f"{name}.pkl"
    with path.open("wb") as f:
        pickle.dump({"name": name, "result": result, "classes": classes}, f)
    return path


def load_results() -> list[dict]:
    out = []
    for p in sorted(RESULTS_DIR.glob("*.pkl")):
        with p.open("rb") as f:
            out.append(pickle.load(f))
    return out
