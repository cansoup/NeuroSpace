#!/usr/bin/env python3
"""
BCI Competition IIIa - Model Evaluation Script

This script evaluates trained models:
1. Loads saved model checkpoints
2. Evaluates on validation data
3. Computes comprehensive metrics (accuracy, precision, recall, F1, confusion matrix)
4. Generates visualizations (confusion matrices, ROC curves)
5. Analyzes confidence distributions and misclassifications
"""

import os
import sys
from pathlib import Path
import yaml
import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.metrics import (
    accuracy_score, precision_recall_fscore_support,
    confusion_matrix, classification_report, roc_curve, auc
)
from sklearn.preprocessing import label_binarize

# Add project root to path
PROJECT_ROOT = Path(__file__).parent.parent
sys.path.append(str(PROJECT_ROOT))

from models.architectures.eegnet import EEGNet
from scripts.train_baseline import BCIDataset


def load_config(config_path: str = "configs/config.yaml") -> dict:
    """Load configuration from YAML file."""
    config_file = PROJECT_ROOT / config_path
    with open(config_file, 'r') as f:
        config = yaml.safe_load(f)
    return config


def load_model(checkpoint_path: Path, config: dict, device: torch.device) -> nn.Module:
    """Load a trained model from checkpoint."""
    print(f"\n📦 Loading model from {checkpoint_path.name}...")

    # Create model
    model = EEGNet(
        n_classes=config['model']['eegnet']['n_classes'],
        n_channels=config['model']['eegnet']['n_channels'],
        n_timepoints=config['model']['eegnet']['n_timepoints'],
        F1=config['model']['eegnet']['F1'],
        D=config['model']['eegnet']['D'],
        F2=config['model']['eegnet']['F2'],
        kernel_length=config['model']['eegnet']['kernel_length'],
        dropout=config['model']['eegnet']['dropout'],
        pool_size=config['model']['eegnet']['pool_size']
    ).to(device)

    # Load checkpoint
    checkpoint = torch.load(checkpoint_path, map_location=device)
    model.load_state_dict(checkpoint['model_state_dict'])
    model.eval()

    print(f"   Model loaded (epoch {checkpoint['epoch']+1})")
    print(f"   Checkpoint Val Acc: {checkpoint['val_acc']:.4f}")

    return model, checkpoint


def evaluate_model(model: nn.Module, dataloader: DataLoader,
                   device: torch.device) -> dict:
    """
    Evaluate model and return predictions, probabilities, and labels.

    Returns:
        Dictionary with predictions, probabilities, labels, and metrics
    """
    model.eval()
    all_preds = []
    all_probs = []
    all_labels = []

    with torch.no_grad():
        for inputs, labels in dataloader:
            inputs = inputs.to(device)

            # Forward pass
            outputs = model(inputs)
            probs = torch.softmax(outputs, dim=1)

            # Get predictions
            _, preds = torch.max(outputs, 1)

            all_preds.extend(preds.cpu().numpy())
            all_probs.extend(probs.cpu().numpy())
            all_labels.extend(labels.numpy())

    all_preds = np.array(all_preds)
    all_probs = np.array(all_probs)
    all_labels = np.array(all_labels)

    # Compute metrics
    accuracy = accuracy_score(all_labels, all_preds)
    precision, recall, f1, _ = precision_recall_fscore_support(
        all_labels, all_preds, average='macro', zero_division=0
    )

    return {
        'predictions': all_preds,
        'probabilities': all_probs,
        'labels': all_labels,
        'accuracy': accuracy,
        'precision': precision,
        'recall': recall,
        'f1': f1
    }


def plot_confusion_matrix(labels: np.ndarray, predictions: np.ndarray,
                          class_names: list, save_path: Path):
    """Plot and save confusion matrix."""
    cm = confusion_matrix(labels, predictions)

    # Normalize
    cm_normalized = cm.astype('float') / cm.sum(axis=1)[:, np.newaxis]

    plt.figure(figsize=(10, 8))
    sns.heatmap(
        cm_normalized,
        annot=True,
        fmt='.2f',
        cmap='Blues',
        xticklabels=class_names,
        yticklabels=class_names,
        cbar_kws={'label': 'Normalized Count'}
    )
    plt.title('Confusion Matrix (Normalized)', fontsize=14, fontweight='bold')
    plt.ylabel('True Label', fontsize=12)
    plt.xlabel('Predicted Label', fontsize=12)
    plt.tight_layout()

    save_path.parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(save_path, dpi=300, bbox_inches='tight')
    plt.close()

    print(f"   Confusion matrix saved to {save_path}")


def plot_roc_curves(labels: np.ndarray, probabilities: np.ndarray,
                    class_names: list, n_classes: int, save_path: Path):
    """Plot ROC curves for multi-class classification (one-vs-rest)."""
    # Binarize labels
    labels_bin = label_binarize(labels, classes=list(range(n_classes)))

    # Compute ROC curve and AUC for each class
    fpr = dict()
    tpr = dict()
    roc_auc = dict()

    for i in range(n_classes):
        fpr[i], tpr[i], _ = roc_curve(labels_bin[:, i], probabilities[:, i])
        roc_auc[i] = auc(fpr[i], tpr[i])

    # Plot
    plt.figure(figsize=(10, 8))
    colors = ['blue', 'red', 'green', 'orange']

    for i in range(n_classes):
        plt.plot(
            fpr[i], tpr[i],
            color=colors[i],
            lw=2,
            label=f'{class_names[i]} (AUC = {roc_auc[i]:.3f})'
        )

    plt.plot([0, 1], [0, 1], 'k--', lw=2, label='Random (AUC = 0.500)')
    plt.xlim([0.0, 1.0])
    plt.ylim([0.0, 1.05])
    plt.xlabel('False Positive Rate', fontsize=12)
    plt.ylabel('True Positive Rate', fontsize=12)
    plt.title('ROC Curves (One-vs-Rest)', fontsize=14, fontweight='bold')
    plt.legend(loc="lower right", fontsize=10)
    plt.grid(alpha=0.3)
    plt.tight_layout()

    save_path.parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(save_path, dpi=300, bbox_inches='tight')
    plt.close()

    print(f"   ROC curves saved to {save_path}")

    return roc_auc


def plot_confidence_distribution(probabilities: np.ndarray, predictions: np.ndarray,
                                  labels: np.ndarray, class_names: list,
                                  save_path: Path):
    """Plot confidence distribution for correct vs incorrect predictions."""
    # Get max probabilities (confidence)
    confidences = np.max(probabilities, axis=1)
    correct = predictions == labels

    plt.figure(figsize=(12, 5))

    # Subplot 1: Overall confidence distribution
    plt.subplot(1, 2, 1)
    plt.hist(confidences[correct], bins=30, alpha=0.7, label='Correct', color='green')
    plt.hist(confidences[~correct], bins=30, alpha=0.7, label='Incorrect', color='red')
    plt.xlabel('Confidence', fontsize=12)
    plt.ylabel('Count', fontsize=12)
    plt.title('Confidence Distribution', fontsize=13, fontweight='bold')
    plt.legend()
    plt.grid(alpha=0.3)

    # Subplot 2: Per-class confidence
    plt.subplot(1, 2, 2)
    for i, class_name in enumerate(class_names):
        class_mask = labels == i
        class_confidences = confidences[class_mask]
        plt.hist(class_confidences, bins=20, alpha=0.5, label=class_name)

    plt.xlabel('Confidence', fontsize=12)
    plt.ylabel('Count', fontsize=12)
    plt.title('Per-Class Confidence', fontsize=13, fontweight='bold')
    plt.legend()
    plt.grid(alpha=0.3)

    plt.tight_layout()
    save_path.parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(save_path, dpi=300, bbox_inches='tight')
    plt.close()

    print(f"   Confidence distribution saved to {save_path}")


def analyze_misclassifications(labels: np.ndarray, predictions: np.ndarray,
                               probabilities: np.ndarray, class_names: list):
    """Analyze misclassified samples."""
    misclassified = labels != predictions
    n_misclassified = misclassified.sum()

    if n_misclassified == 0:
        print("\nNo misclassifications")
        return

    print(f"\nMisclassification Analysis")
    print(f"   Total misclassified: {n_misclassified} / {len(labels)} "
          f"({100*n_misclassified/len(labels):.2f}%)")

    # Most common misclassifications
    misclass_pairs = list(zip(labels[misclassified], predictions[misclassified]))
    from collections import Counter
    common_errors = Counter(misclass_pairs).most_common(5)

    print(f"\n   Most common errors:")
    for (true_label, pred_label), count in common_errors:
        print(f"      {class_names[true_label]} → {class_names[pred_label]}: "
              f"{count} times")

    # Average confidence on misclassifications
    misclass_confidences = np.max(probabilities[misclassified], axis=1)
    print(f"\n   Avg confidence on errors: {misclass_confidences.mean():.3f} "
          f"± {misclass_confidences.std():.3f}")


def main():
    """Main evaluation pipeline."""
    print("\n" + "="*60)
    print("BCI Competition IIIa - Model Evaluation Pipeline")
    print("="*60)

    # Load configuration
    config = load_config()

    # Set device
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"\nUsing device: {device}")

    # Get class names
    class_mapping = config['preprocessing']['class_mapping']
    class_names = [class_mapping[i] for i in range(len(class_mapping))]
    n_classes = len(class_names)

    # Find model checkpoints
    checkpoint_dir = PROJECT_ROOT / config['paths']['model_checkpoints']
    checkpoints = list(checkpoint_dir.glob("fold_*_best.pth"))

    if not checkpoints:
        print(f"\n[ERROR] No model checkpoints found in {checkpoint_dir}")
        print(f"   Please run 2_train_baseline.py first.")
        return

    print(f"\nFound {len(checkpoints)} model checkpoints")

    # Evaluate each fold
    all_results = []

    for checkpoint_path in sorted(checkpoints):
        fold_idx = int(checkpoint_path.stem.split('_')[1])
        print(f"\n{'='*60}")
        print(f"Evaluating Fold {fold_idx}")
        print(f"{'='*60}")

        # Load model
        model, checkpoint = load_model(checkpoint_path, config, device)

        # Load corresponding validation data
        subject_id = config['paths']['subjects'][fold_idx].replace('.gdf', '')
        data_dir = PROJECT_ROOT / config['paths']['processed_data']
        val_file = data_dir / f"{subject_id}_val.npz"

        if not val_file.exists():
            print(f"   [WARNING] Validation data not found: {val_file}")
            continue

        val_data = np.load(val_file)
        X_val = val_data['X']
        y_val = val_data['y']

        # Create dataloader
        val_dataset = BCIDataset(X_val, y_val)
        val_loader = DataLoader(val_dataset, batch_size=32, shuffle=False)

        # Evaluate
        print(f"\nEvaluating on {len(val_dataset)} samples...")
        results = evaluate_model(model, val_loader, device)

        # Print metrics
        print(f"\nMetrics:")
        print(f"   Accuracy:  {results['accuracy']:.4f}")
        print(f"   Precision: {results['precision']:.4f}")
        print(f"   Recall:    {results['recall']:.4f}")
        print(f"   F1 Score:  {results['f1']:.4f}")

        # Classification report
        print(f"\n   Per-class metrics:")
        print(classification_report(
            results['labels'],
            results['predictions'],
            target_names=class_names,
            digits=3
        ))

        # Generate visualizations
        print(f"\nGenerating visualizations...")
        viz_dir = PROJECT_ROOT / "results" / f"fold_{fold_idx}"

        # Confusion matrix
        plot_confusion_matrix(
            results['labels'],
            results['predictions'],
            class_names,
            viz_dir / "confusion_matrix.png"
        )

        # ROC curves
        roc_auc = plot_roc_curves(
            results['labels'],
            results['probabilities'],
            class_names,
            n_classes,
            viz_dir / "roc_curves.png"
        )

        # Confidence distribution
        plot_confidence_distribution(
            results['probabilities'],
            results['predictions'],
            results['labels'],
            class_names,
            viz_dir / "confidence_distribution.png"
        )

        # Misclassification analysis
        analyze_misclassifications(
            results['labels'],
            results['predictions'],
            results['probabilities'],
            class_names
        )

        all_results.append({
            'fold': fold_idx,
            'subject': subject_id,
            'accuracy': results['accuracy'],
            'f1': results['f1'],
            'roc_auc': roc_auc
        })

    # Overall summary
    print("\n" + "="*60)
    print("Overall Evaluation Summary")
    print("="*60)

    for result in all_results:
        print(f"\nFold {result['fold']} ({result['subject']}):")
        print(f"   Accuracy: {result['accuracy']:.4f}")
        print(f"   F1 Score: {result['f1']:.4f}")
        print(f"   ROC AUC per class:")
        for i, class_name in enumerate(class_names):
            print(f"      {class_name}: {result['roc_auc'][i]:.3f}")

    # Average metrics
    avg_acc = np.mean([r['accuracy'] for r in all_results])
    std_acc = np.std([r['accuracy'] for r in all_results])
    avg_f1 = np.mean([r['f1'] for r in all_results])
    std_f1 = np.std([r['f1'] for r in all_results])

    print(f"\nCross-Validation Results:")
    print(f"   Average Accuracy: {avg_acc:.4f} ± {std_acc:.4f}")
    print(f"   Average F1 Score: {avg_f1:.4f} ± {std_f1:.4f}")

    print("\nEvaluation complete")
    print("="*60 + "\n")


if __name__ == "__main__":
    main()
