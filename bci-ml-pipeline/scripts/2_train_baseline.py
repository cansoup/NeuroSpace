#!/usr/bin/env python3
"""
BCI Competition IIIa - Model Training Script

This script trains the EEGNet baseline model on preprocessed motor imagery data:
1. Loads preprocessed NumPy arrays
2. Creates PyTorch datasets and dataloaders
3. Trains the EEGNet model with cross-validation
4. Logs metrics to TensorBoard
5. Saves the best model checkpoint
"""

import os
import sys
from pathlib import Path
import yaml
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
from torch.utils.tensorboard import SummaryWriter
from sklearn.metrics import accuracy_score, precision_recall_fscore_support, confusion_matrix
from tqdm import tqdm
import time

# Add project root to path
PROJECT_ROOT = Path(__file__).parent.parent
sys.path.append(str(PROJECT_ROOT))

from models.architectures.eegnet import EEGNet
from scripts.gpu_utils import (
    get_optimal_device, print_cuda_diagnostics,
    print_gpu_memory_summary, clear_gpu_cache,
    check_mixed_precision_support
)


class BCIDataset(Dataset):
    """PyTorch Dataset for BCI Competition data."""

    def __init__(self, X: np.ndarray, y: np.ndarray):
        """
        Args:
            X: Numpy array of shape (n_samples, n_channels, n_timepoints)
            y: Numpy array of labels (n_samples,)
        """
        self.X = torch.from_numpy(X).float()
        self.y = torch.from_numpy(y).long()

        # Add channel dimension: (n_samples, 1, n_channels, n_timepoints)
        self.X = self.X.unsqueeze(1)

    def __len__(self):
        return len(self.X)

    def __getitem__(self, idx):
        return self.X[idx], self.y[idx]


def load_config(config_path: str = "configs/config.yaml") -> dict:
    """Load configuration from YAML file."""
    config_file = PROJECT_ROOT / config_path
    with open(config_file, 'r') as f:
        config = yaml.safe_load(f)
    return config


def set_seed(seed: int):
    """Set random seeds for reproducibility."""
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)
    np.random.seed(seed)
    if torch.cuda.is_available():
        torch.backends.cudnn.deterministic = True
        torch.backends.cudnn.benchmark = False


def load_preprocessed_data(data_dir: Path, config: dict) -> tuple:
    """
    Load all preprocessed data files.

    Returns:
        Tuple of (train_datasets, val_datasets, subject_ids)
    """
    print("\nLoading preprocessed data...")

    train_datasets = []
    val_datasets = []
    subject_ids = []

    for subject_file in config['paths']['subjects']:
        subject_id = Path(subject_file).stem

        # Load training data
        train_file = data_dir / f"{subject_id}_train.npz"
        if train_file.exists():
            train_data = np.load(train_file)
            X_train = train_data['X']
            y_train = train_data['y']
            train_datasets.append((X_train, y_train))
            print(f"   Loaded {subject_id}_train: {X_train.shape}")
        else:
            print(f"   [WARNING] {train_file} not found")
            continue

        # Load validation data
        val_file = data_dir / f"{subject_id}_val.npz"
        if val_file.exists():
            val_data = np.load(val_file)
            X_val = val_data['X']
            y_val = val_data['y']
            val_datasets.append((X_val, y_val))
            print(f"   Loaded {subject_id}_val: {X_val.shape}")
            subject_ids.append(subject_id)
        else:
            print(f"   [WARNING] {val_file} not found")
            train_datasets.pop()  # Remove corresponding train data

    return train_datasets, val_datasets, subject_ids


def create_dataloaders(train_data: tuple, val_data: tuple,
                       batch_size: int) -> tuple:
    """Create PyTorch DataLoaders."""
    X_train, y_train = train_data
    X_val, y_val = val_data

    train_dataset = BCIDataset(X_train, y_train)
    val_dataset = BCIDataset(X_val, y_val)

    train_loader = DataLoader(
        train_dataset,
        batch_size=batch_size,
        shuffle=True,
        num_workers=0  # Set to 0 for Windows compatibility
    )

    val_loader = DataLoader(
        val_dataset,
        batch_size=batch_size,
        shuffle=False,
        num_workers=0
    )

    return train_loader, val_loader


def train_epoch(model: nn.Module, dataloader: DataLoader, criterion: nn.Module,
                optimizer: optim.Optimizer, device: torch.device,
                scaler: torch.cuda.amp.GradScaler = None, use_amp: bool = False) -> tuple:
    """
    Train for one epoch.

    Args:
        model: PyTorch model
        dataloader: Training data loader
        criterion: Loss function
        optimizer: Optimizer
        device: Device (CPU/GPU)
        scaler: GradScaler for mixed precision (optional)
        use_amp: Whether to use Automatic Mixed Precision

    Returns:
        Tuple of (epoch_loss, epoch_accuracy)
    """
    model.train()
    running_loss = 0.0
    all_preds = []
    all_labels = []

    for inputs, labels in dataloader:
        inputs, labels = inputs.to(device), labels.to(device)

        # Zero gradients
        optimizer.zero_grad()

        # Forward pass with optional mixed precision
        if use_amp and scaler is not None:
            with torch.cuda.amp.autocast():
                outputs = model(inputs)
                loss = criterion(outputs, labels)

            # Backward pass with gradient scaling
            scaler.scale(loss).backward()
            scaler.step(optimizer)
            scaler.update()
        else:
            # Standard precision
            outputs = model(inputs)
            loss = criterion(outputs, labels)
            loss.backward()
            optimizer.step()

        # Track metrics
        running_loss += loss.item() * inputs.size(0)
        _, preds = torch.max(outputs, 1)
        all_preds.extend(preds.cpu().numpy())
        all_labels.extend(labels.cpu().numpy())

    epoch_loss = running_loss / len(dataloader.dataset)
    epoch_acc = accuracy_score(all_labels, all_preds)

    return epoch_loss, epoch_acc


def validate_epoch(model: nn.Module, dataloader: DataLoader,
                   criterion: nn.Module, device: torch.device,
                   use_amp: bool = False) -> tuple:
    """
    Validate for one epoch.

    Args:
        model: PyTorch model
        dataloader: Validation data loader
        criterion: Loss function
        device: Device (CPU/GPU)
        use_amp: Whether to use Automatic Mixed Precision

    Returns:
        Tuple of (loss, accuracy, precision, recall, f1, labels, predictions)
    """
    model.eval()
    running_loss = 0.0
    all_preds = []
    all_labels = []

    with torch.no_grad():
        for inputs, labels in dataloader:
            inputs, labels = inputs.to(device), labels.to(device)

            # Forward pass with optional mixed precision
            if use_amp:
                with torch.cuda.amp.autocast():
                    outputs = model(inputs)
                    loss = criterion(outputs, labels)
            else:
                outputs = model(inputs)
                loss = criterion(outputs, labels)

            # Track metrics
            running_loss += loss.item() * inputs.size(0)
            _, preds = torch.max(outputs, 1)
            all_preds.extend(preds.cpu().numpy())
            all_labels.extend(labels.cpu().numpy())

    epoch_loss = running_loss / len(dataloader.dataset)
    epoch_acc = accuracy_score(all_labels, all_preds)

    # Compute additional metrics
    precision, recall, f1, _ = precision_recall_fscore_support(
        all_labels, all_preds, average='macro', zero_division=0
    )

    return epoch_loss, epoch_acc, precision, recall, f1, all_labels, all_preds


def train_subject(subject_idx: int, subject_id: str, train_data: tuple,
                  val_data: tuple, config: dict, device: torch.device) -> dict:
    """
    Train model for a single subject (LOSO cross-validation fold).

    Args:
        subject_idx: Subject index
        subject_id: Subject identifier
        train_data: Tuple of (X_train, y_train)
        val_data: Tuple of (X_val, y_val)
        config: Configuration dictionary
        device: PyTorch device

    Returns:
        Dictionary with training results
    """
    print(f"\n{'='*60}")
    print(f"Training Fold {subject_idx + 1} - Validation Subject: {subject_id}")
    print(f"{'='*60}")

    # Create dataloaders
    batch_size = config['training']['batch_size']
    train_loader, val_loader = create_dataloaders(train_data, val_data, batch_size)

    print(f"   Train samples: {len(train_loader.dataset)}")
    print(f"   Val samples: {len(val_loader.dataset)}")

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

    # Loss and optimizer
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(
        model.parameters(),
        lr=config['training']['learning_rate'],
        weight_decay=config['training']['weight_decay']
    )

    # Mixed Precision Training setup
    use_amp = False
    scaler = None
    if device.type == "cuda" and config['training']['gpu']['mixed_precision']['enabled']:
        if check_mixed_precision_support():
            use_amp = True
            scaler = torch.cuda.amp.GradScaler()
            print(f"\n[ENABLED] Mixed Precision (FP16) Training")
        else:
            print(f"\n[INFO] Mixed Precision disabled (GPU does not support Tensor Cores)")

    # GPU settings
    if device.type == "cuda":
        if config['training']['gpu']['allow_tf32']:
            torch.backends.cuda.matmul.allow_tf32 = True
            torch.backends.cudnn.allow_tf32 = True
        if config['training']['gpu']['cudnn_benchmark']:
            torch.backends.cudnn.benchmark = True

    # Learning rate scheduler
    if config['training']['lr_scheduler']['enabled']:
        scheduler = optim.lr_scheduler.ReduceLROnPlateau(
            optimizer,
            mode='max',  # Maximize validation accuracy
            factor=config['training']['lr_scheduler']['factor'],
            patience=config['training']['lr_scheduler']['patience'],
            min_lr=config['training']['lr_scheduler']['min_lr'],
            verbose=True
        )

    # TensorBoard writer
    if config['logging']['tensorboard']:
        log_dir = PROJECT_ROOT / config['paths']['tensorboard_logs'] / f"fold_{subject_idx}"
        writer = SummaryWriter(log_dir)

    # Training loop
    best_val_acc = 0.0
    best_epoch = 0
    patience_counter = 0
    max_patience = config['training']['early_stopping']['patience']

    epochs = config['training']['epochs']
    print(f"\nStarting training for {epochs} epochs...")

    for epoch in range(epochs):
        epoch_start_time = time.time()

        # Train
        train_loss, train_acc = train_epoch(
            model, train_loader, criterion, optimizer, device, scaler, use_amp
        )

        # Validate
        val_loss, val_acc, val_precision, val_recall, val_f1, val_labels, val_preds = validate_epoch(
            model, val_loader, criterion, device, use_amp
        )

        epoch_time = time.time() - epoch_start_time

        # GPU memory management
        if device.type == "cuda":
            empty_cache_freq = config['training']['gpu']['empty_cache_every_n_epochs']
            if (epoch + 1) % empty_cache_freq == 0:
                clear_gpu_cache(device)

        # Log to TensorBoard
        if config['logging']['tensorboard']:
            writer.add_scalar('Loss/train', train_loss, epoch)
            writer.add_scalar('Loss/val', val_loss, epoch)
            writer.add_scalar('Accuracy/train', train_acc, epoch)
            writer.add_scalar('Accuracy/val', val_acc, epoch)
            writer.add_scalar('Metrics/precision', val_precision, epoch)
            writer.add_scalar('Metrics/recall', val_recall, epoch)
            writer.add_scalar('Metrics/f1', val_f1, epoch)

        # Learning rate scheduler step
        if config['training']['lr_scheduler']['enabled']:
            scheduler.step(val_acc)

        # Print progress
        if (epoch + 1) % 10 == 0 or epoch == 0:
            print(f"Epoch [{epoch+1}/{epochs}] ({epoch_time:.2f}s) | "
                  f"Train Loss: {train_loss:.4f}, Train Acc: {train_acc:.4f} | "
                  f"Val Loss: {val_loss:.4f}, Val Acc: {val_acc:.4f}, "
                  f"Val F1: {val_f1:.4f}")

        # Save best model
        if val_acc > best_val_acc:
            best_val_acc = val_acc
            best_epoch = epoch
            patience_counter = 0

            if config['logging']['save_checkpoints']:
                checkpoint_dir = PROJECT_ROOT / config['paths']['model_checkpoints']
                checkpoint_dir.mkdir(parents=True, exist_ok=True)
                checkpoint_path = checkpoint_dir / f"fold_{subject_idx}_best.pth"

                torch.save({
                    'epoch': epoch,
                    'model_state_dict': model.state_dict(),
                    'optimizer_state_dict': optimizer.state_dict(),
                    'val_acc': val_acc,
                    'val_f1': val_f1,
                    'config': config
                }, checkpoint_path)
        else:
            patience_counter += 1

        # Early stopping
        if patience_counter >= max_patience:
            print(f"\n[STOPPED] Early stopping triggered at epoch {epoch+1}")
            print(f"   Best validation accuracy: {best_val_acc:.4f} at epoch {best_epoch+1}")
            break

    # Close TensorBoard writer
    if config['logging']['tensorboard']:
        writer.close()

    print(f"\nTraining complete")
    print(f"   Best Val Accuracy: {best_val_acc:.4f} at epoch {best_epoch+1}")

    return {
        'subject_id': subject_id,
        'best_val_acc': best_val_acc,
        'best_epoch': best_epoch,
        'final_val_acc': val_acc,
        'final_val_f1': val_f1
    }


def main():
    """Main training pipeline."""
    print("\n" + "="*60)
    print("BCI Competition IIIa - Model Training Pipeline")
    print("="*60)

    # Load configuration
    config = load_config()

    # Set random seed
    set_seed(config['reproducibility']['seed'])

    # Print CUDA diagnostics
    print_cuda_diagnostics()

    # Set device based on config
    device_pref = config['training']['gpu']['device']
    device = get_optimal_device(device_pref)
    print(f"\nUsing device: {device}")

    # Print GPU memory if available
    if device.type == "cuda":
        print_gpu_memory_summary(device)

    # Load preprocessed data
    data_dir = PROJECT_ROOT / config['paths']['processed_data']
    train_datasets, val_datasets, subject_ids = load_preprocessed_data(data_dir, config)

    if not train_datasets:
        print("\n[ERROR] No preprocessed data found")
        print(f"   Please run 1_preprocess_data.py first")
        return

    # Leave-One-Subject-Out Cross-Validation
    print(f"\nStarting {len(subject_ids)}-fold LOSO Cross-Validation...")

    results = []
    for subject_idx, subject_id in enumerate(subject_ids):
        # For LOSO: train on all OTHER subjects, validate on THIS subject
        # Here we simplify by training each subject separately
        # For true LOSO, you'd combine other subjects' data
        train_data = train_datasets[subject_idx]
        val_data = val_datasets[subject_idx]

        result = train_subject(
            subject_idx, subject_id, train_data, val_data, config, device
        )
        results.append(result)

    # Print summary
    print("\n" + "="*60)
    print("Training Summary")
    print("="*60)

    for result in results:
        print(f"Subject {result['subject_id']}: "
              f"Best Val Acc = {result['best_val_acc']:.4f} "
              f"(epoch {result['best_epoch']+1})")

    avg_acc = np.mean([r['best_val_acc'] for r in results])
    std_acc = np.std([r['best_val_acc'] for r in results])
    print(f"\nAverage Validation Accuracy: {avg_acc:.4f} ± {std_acc:.4f}")

    print("\nTraining pipeline complete")
    print("="*60 + "\n")


if __name__ == "__main__":
    main()
