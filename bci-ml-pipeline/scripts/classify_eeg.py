#!/usr/bin/env python3
"""
BCI EEG Classification Script - Batch Processing

This script loads a trained EEGNet model and classifies motor imagery epochs
from GDF files. It processes all epochs in a file and outputs predictions
with confidence scores.

Usage:
    python classify_eeg.py --input data/raw/k3b.gdf --model models/saved_models/fold_0_best.pth --output predictions.csv

Output CSV Format:
    epoch_index, timestamp, predicted_class, predicted_label, confidence, prob_left, prob_right, prob_down, prob_up
"""

import os
import sys
from pathlib import Path
import argparse
import yaml
import numpy as np
import pandas as pd
import torch
import torch.nn.functional as F
import mne
from tqdm import tqdm

# Add project root to path
PROJECT_ROOT = Path(__file__).parent.parent
sys.path.append(str(PROJECT_ROOT))

from models.architectures.eegnet import EEGNet


def load_config(config_path: str = "configs/config.yaml") -> dict:
    """Load configuration from YAML file."""
    config_file = PROJECT_ROOT / config_path
    with open(config_file, 'r') as f:
        config = yaml.safe_load(f)
    return config


def load_model(checkpoint_path: str, config: dict, device: torch.device) -> torch.nn.Module:
    """
    Load trained EEGNet model from checkpoint.

    Args:
        checkpoint_path: Path to model checkpoint file
        config: Configuration dictionary
        device: Device to load model on

    Returns:
        Loaded model in evaluation mode
    """
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

    print(f"[OK] Loaded model from {checkpoint_path}")
    print(f"  Checkpoint epoch: {checkpoint['epoch']}")
    print(f"  Validation accuracy: {checkpoint['val_acc']:.4f}")

    return model


def preprocess_gdf(gdf_path: str, config: dict) -> tuple:
    """
    Load and preprocess GDF file.

    Args:
        gdf_path: Path to GDF file
        config: Configuration dictionary

    Returns:
        Tuple of (epochs_data, timestamps, event_labels)
    """
    print(f"\nPreprocessing {Path(gdf_path).name}...")

    # Load raw GDF file
    raw = mne.io.read_raw_gdf(gdf_path, preload=True, verbose=False)

    # Get events and event IDs
    events, event_id = mne.events_from_annotations(raw, verbose=False)

    # Find motor imagery events (769, 770, 771, 772)
    # MNE stores them as strings and maps them to integer codes
    motor_imagery_events = {}
    code_to_class = {}  # Map MNE codes to our class indices (0, 1, 2, 3)

    for event_name, event_code in event_id.items():
        name_str = str(event_name)

        if '769' in name_str:
            motor_imagery_events[event_name] = event_code
            code_to_class[event_code] = 0  # left hand
        elif '770' in name_str:
            motor_imagery_events[event_name] = event_code
            code_to_class[event_code] = 1  # right hand
        elif '771' in name_str:
            motor_imagery_events[event_name] = event_code
            code_to_class[event_code] = 2  # foot
        elif '772' in name_str:
            motor_imagery_events[event_name] = event_code
            code_to_class[event_code] = 3  # tongue

    if not motor_imagery_events:
        raise ValueError(f"No motor imagery events found. Available events: {list(event_id.keys())}")

    # Apply bandpass filter
    raw.filter(
        l_freq=config['preprocessing']['bandpass']['low'],
        h_freq=config['preprocessing']['bandpass']['high'],
        picks='eeg',
        verbose=False
    )

    # Apply notch filter
    raw.notch_filter(
        freqs=config['preprocessing']['notch']['freq'],
        picks='eeg',
        verbose=False
    )

    # Extract epochs using MNE event codes
    epochs = mne.Epochs(
        raw,
        events,
        event_id=motor_imagery_events,  # Use original MNE codes
        tmin=config['preprocessing']['epoch']['tmin'],
        tmax=config['preprocessing']['epoch']['tmax'],
        baseline=tuple(config['preprocessing']['epoch']['baseline']),
        preload=True,
        verbose=False
    )

    # Get epochs data: (n_epochs, n_channels, n_timepoints)
    epochs_data = epochs.get_data()

    # Scale to microvolts (CRITICAL: matches training preprocessing)
    epochs_data = epochs_data * 1e6

    # Get timestamps and MNE's event codes
    timestamps = epochs.events[:, 0] / raw.info['sfreq']  # Convert to seconds
    mne_event_codes = epochs.events[:, 2]  # MNE's codes (e.g., 3, 4, 5, 6)

    # Remap MNE codes to our class indices (0, 1, 2, 3)
    event_labels = np.array([code_to_class[code] for code in mne_event_codes])

    print(f"[OK] Preprocessed {len(epochs_data)} epochs")
    print(f"  Shape: {epochs_data.shape}")
    print(f"  Data range: [{epochs_data.min():.2f}, {epochs_data.max():.2f}] uV")

    return epochs_data, timestamps, event_labels


def classify_epochs(model: torch.nn.Module, epochs_data: np.ndarray,
                    device: torch.device, batch_size: int = 32) -> tuple:
    """
    Classify all epochs using the trained model.

    Args:
        model: Trained EEGNet model
        epochs_data: Numpy array of shape (n_epochs, n_channels, n_timepoints)
        device: Device to run inference on
        batch_size: Batch size for inference

    Returns:
        Tuple of (predictions, probabilities)
    """
    all_predictions = []
    all_probabilities = []

    # Convert to tensor and add channel dimension
    X = torch.from_numpy(epochs_data).float().unsqueeze(1)  # (n_epochs, 1, n_channels, n_timepoints)

    # Process in batches
    n_epochs = len(X)
    n_batches = (n_epochs + batch_size - 1) // batch_size

    with torch.no_grad():
        for i in tqdm(range(n_batches), desc="Classifying", unit="batch"):
            start_idx = i * batch_size
            end_idx = min((i + 1) * batch_size, n_epochs)

            batch = X[start_idx:end_idx].to(device)

            # Forward pass
            outputs = model(batch)
            probabilities = F.softmax(outputs, dim=1)
            predictions = torch.argmax(probabilities, dim=1)

            all_predictions.extend(predictions.cpu().numpy())
            all_probabilities.extend(probabilities.cpu().numpy())

    return np.array(all_predictions), np.array(all_probabilities)


def save_predictions(output_path: str, predictions: np.ndarray,
                    probabilities: np.ndarray, timestamps: np.ndarray,
                    config: dict):
    """
    Save predictions to CSV file.

    Args:
        output_path: Path to output CSV file
        predictions: Array of predicted class indices
        probabilities: Array of class probabilities
        timestamps: Array of epoch timestamps
        config: Configuration dictionary
    """
    # Get class labels
    class_mapping = config['preprocessing']['class_mapping']
    class_labels = [class_mapping[i] for i in predictions]

    # Get confidence scores (max probability)
    confidences = np.max(probabilities, axis=1)

    # Create DataFrame
    df = pd.DataFrame({
        'epoch_index': range(len(predictions)),
        'timestamp': timestamps,
        'predicted_class': predictions,
        'predicted_label': class_labels,
        'confidence': confidences,
        'prob_left': probabilities[:, 0],
        'prob_right': probabilities[:, 1],
        'prob_down': probabilities[:, 2],
        'prob_up': probabilities[:, 3]
    })

    # Save to CSV
    df.to_csv(output_path, index=False)
    print(f"\n[OK] Saved predictions to {output_path}")

    # Print summary statistics
    print("\nPrediction Summary:")
    print(f"  Total epochs: {len(predictions)}")
    print(f"  Average confidence: {confidences.mean():.4f}")
    print(f"  Min confidence: {confidences.min():.4f}")
    print(f"  Max confidence: {confidences.max():.4f}")

    print("\nClass Distribution:")
    for i in range(4):
        label = class_mapping[i]
        count = np.sum(predictions == i)
        percentage = count / len(predictions) * 100
        print(f"  {label}: {count} ({percentage:.1f}%)")


def main():
    """Main classification pipeline."""
    parser = argparse.ArgumentParser(
        description="Classify motor imagery epochs from GDF files using trained EEGNet model"
    )
    parser.add_argument(
        '--input', '-i',
        type=str,
        required=True,
        help='Path to input GDF file'
    )
    parser.add_argument(
        '--model', '-m',
        type=str,
        required=True,
        help='Path to trained model checkpoint (.pth file)'
    )
    parser.add_argument(
        '--output', '-o',
        type=str,
        default='predictions.csv',
        help='Path to output CSV file (default: predictions.csv)'
    )
    parser.add_argument(
        '--batch-size', '-b',
        type=int,
        default=32,
        help='Batch size for inference (default: 32)'
    )
    parser.add_argument(
        '--device', '-d',
        type=str,
        default='auto',
        choices=['auto', 'cuda', 'cpu'],
        help='Device to use for inference (default: auto)'
    )

    args = parser.parse_args()

    print("=" * 60)
    print("BCI EEG Classification - Batch Processing")
    print("=" * 60)

    # Validate input paths
    if not Path(args.input).exists():
        print(f"\n[ERROR] Input file not found: {args.input}")
        return

    if not Path(args.model).exists():
        print(f"\n[ERROR] Model checkpoint not found: {args.model}")
        return

    # Load configuration
    config = load_config()

    # Set device
    if args.device == 'auto':
        device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    else:
        device = torch.device(args.device)
    print(f"\nUsing device: {device}")

    # Load model
    model = load_model(args.model, config, device)

    # Preprocess GDF file
    epochs_data, timestamps, event_labels = preprocess_gdf(args.input, config)

    # Classify epochs
    print("\nRunning inference...")
    predictions, probabilities = classify_epochs(
        model, epochs_data, device, args.batch_size
    )

    # Save predictions
    save_predictions(args.output, predictions, probabilities, timestamps, config)

    print("\n" + "=" * 60)
    print("Classification complete!")
    print("=" * 60)


if __name__ == "__main__":
    main()
