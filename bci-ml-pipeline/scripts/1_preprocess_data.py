#!/usr/bin/env python3
"""
BCI Competition IIIa Data Preprocessing Script

This script processes raw GDF files from the BCI Competition IIIa dataset:
1. Loads GDF files using MNE-Python
2. Applies bandpass and notch filters
3. Extracts epochs based on motor imagery event codes
4. Performs baseline correction
5. Saves preprocessed data as NumPy arrays

Event code mapping:
- 769: Left hand  → class 0 → "focus_left"
- 770: Right hand → class 1 → "focus_right"
- 771: Foot       → class 2 → "down"
- 772: Tongue     → class 3 → "up"
"""

import os
import sys
from pathlib import Path
import yaml
import numpy as np
import mne
from sklearn.model_selection import train_test_split
from tqdm import tqdm

# Add project root to path
PROJECT_ROOT = Path(__file__).parent.parent
sys.path.append(str(PROJECT_ROOT))


def load_config(config_path: str = "configs/config.yaml") -> dict:
    """Load configuration from YAML file."""
    config_file = PROJECT_ROOT / config_path
    with open(config_file, 'r') as f:
        config = yaml.safe_load(f)
    return config


def load_gdf_file(file_path: Path, config: dict) -> tuple:
    """
    Load a GDF file and extract raw EEG data.

    Args:
        file_path: Path to the GDF file
        config: Configuration dictionary

    Returns:
        Tuple of (raw, events, event_id)
    """
    print(f"\nLoading {file_path.name}...")

    # Load raw GDF file
    raw = mne.io.read_raw_gdf(
        file_path,
        preload=True,
        verbose=False
    )

    # Get events from annotations
    events, event_id = mne.events_from_annotations(raw, verbose=False)

    print(f"   Loaded {len(raw.ch_names)} channels, {raw.n_times} timepoints")
    print(f"   Sampling rate: {raw.info['sfreq']} Hz")
    print(f"   Duration: {raw.times[-1]:.2f} seconds")
    print(f"   Found {len(events)} events")

    return raw, events, event_id


def preprocess_raw(raw: mne.io.Raw, config: dict) -> mne.io.Raw:
    """
    Apply filtering to raw EEG data.

    Args:
        raw: MNE Raw object
        config: Configuration dictionary

    Returns:
        Filtered Raw object
    """
    print("\n🔧 Applying filters...")

    # Bandpass filter (8-30 Hz for motor imagery)
    raw.filter(
        l_freq=config['preprocessing']['bandpass']['low'],
        h_freq=config['preprocessing']['bandpass']['high'],
        fir_design='firwin',
        verbose=False
    )
    print(f"   Bandpass filter: {config['preprocessing']['bandpass']['low']}-"
          f"{config['preprocessing']['bandpass']['high']} Hz")

    # Notch filter (50 Hz powerline noise)
    raw.notch_filter(
        freqs=config['preprocessing']['notch']['freq'],
        verbose=False
    )
    print(f"   Notch filter: {config['preprocessing']['notch']['freq']} Hz")

    return raw


def extract_epochs(raw: mne.io.Raw, events: np.ndarray, event_id: dict,
                   config: dict) -> tuple:
    """
    Extract epochs from raw data based on event codes.

    Args:
        raw: MNE Raw object
        events: Event array
        event_id: Event ID dictionary
        config: Configuration dictionary

    Returns:
        Tuple of (epochs_data, labels)
    """
    print("\n📊 Extracting epochs...")

    # Map event names to standardized codes
    # BCI IIIa uses codes like '769', '770', '771', '772'
    event_mapping = {}
    target_codes = config['preprocessing']['event_codes']

    # Find the correct event IDs in the file
    for event_name, event_code in event_id.items():
        if '769' in event_name or event_code == 769:
            event_mapping[event_name] = 0  # left_hand
        elif '770' in event_name or event_code == 770:
            event_mapping[event_name] = 1  # right_hand
        elif '771' in event_name or event_code == 771:
            event_mapping[event_name] = 2  # foot
        elif '772' in event_name or event_code == 772:
            event_mapping[event_name] = 3  # tongue

    if not event_mapping:
        print("   [WARNING] No motor imagery events found in standard format")
        print(f"   Available events: {event_id}")
        # Fallback: try to find events by numeric code
        reverse_event_id = {v: k for k, v in event_id.items()}
        for code, class_idx in zip([769, 770, 771, 772], range(4)):
            if code in reverse_event_id:
                event_mapping[reverse_event_id[code]] = class_idx

    print(f"   Event mapping: {event_mapping}")

    # Create epochs
    tmin = config['preprocessing']['epoch']['tmin']
    tmax = config['preprocessing']['epoch']['tmax']
    baseline = tuple(config['preprocessing']['epoch']['baseline'])

    epochs = mne.Epochs(
        raw,
        events,
        event_id=event_mapping,
        tmin=tmin,
        tmax=tmax,
        baseline=baseline,
        preload=True,
        verbose=False
    )

    # Get data and labels
    epochs_data = epochs.get_data()  # Shape: (n_epochs, n_channels, n_times)
    labels = epochs.events[:, -1]  # Last column contains event IDs (0, 1, 2, 3)

    print(f"   Extracted {len(epochs_data)} epochs")
    print(f"   Epoch shape: {epochs_data.shape}")
    print(f"   Time window: [{tmin}, {tmax}] seconds")

    # Print class distribution
    unique, counts = np.unique(labels, return_counts=True)
    class_names = config['preprocessing']['class_mapping']
    print(f"\n   Class distribution:")
    for cls, count in zip(unique, counts):
        print(f"      Class {cls} ({class_names[cls]}): {count} trials")

    return epochs_data, labels


def save_preprocessed_data(epochs_data: np.ndarray, labels: np.ndarray,
                           subject_id: str, output_dir: Path, config: dict):
    """
    Split data into train/val and save as NumPy arrays.

    Args:
        epochs_data: Preprocessed epoch data
        labels: Class labels
        subject_id: Subject identifier (e.g., 'k3b')
        output_dir: Output directory
        config: Configuration dictionary
    """
    print("\nSaving preprocessed data...")

    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)

    # Train/validation split
    val_split = config['preprocessing']['validation_split']
    random_seed = config['preprocessing']['random_seed']

    X_train, X_val, y_train, y_val = train_test_split(
        epochs_data,
        labels,
        test_size=val_split,
        random_state=random_seed,
        stratify=labels  # Maintain class distribution
    )

    # Save training data
    train_file = output_dir / f"{subject_id}_train.npz"
    np.savez_compressed(
        train_file,
        X=X_train,
        y=y_train,
        sfreq=config['preprocessing']['sfreq'],
        ch_names=None  # We'll use channel indices
    )
    print(f"   Saved training data: {train_file}")
    print(f"      Shape: {X_train.shape}, Labels: {y_train.shape}")

    # Save validation data
    val_file = output_dir / f"{subject_id}_val.npz"
    np.savez_compressed(
        val_file,
        X=X_val,
        y=y_val,
        sfreq=config['preprocessing']['sfreq'],
        ch_names=None
    )
    print(f"   Saved validation data: {val_file}")
    print(f"      Shape: {X_val.shape}, Labels: {y_val.shape}")


def process_subject(subject_file: str, config: dict):
    """
    Process a single subject's GDF file.

    Args:
        subject_file: Filename of the GDF file
        config: Configuration dictionary
    """
    # Construct paths
    raw_dir = PROJECT_ROOT / config['paths']['raw_data']
    processed_dir = PROJECT_ROOT / config['paths']['processed_data']
    file_path = raw_dir / subject_file

    # Extract subject ID (e.g., 'k3b' from 'k3b.gdf')
    subject_id = Path(subject_file).stem

    print(f"\n{'='*60}")
    print(f"Processing Subject: {subject_id}")
    print(f"{'='*60}")

    # Check if file exists
    if not file_path.exists():
        print(f"[ERROR] File not found: {file_path}")
        return

    # Load GDF file
    raw, events, event_id = load_gdf_file(file_path, config)

    # Preprocess (filter)
    raw = preprocess_raw(raw, config)

    # Extract epochs
    epochs_data, labels = extract_epochs(raw, events, event_id, config)

    # Save preprocessed data
    save_preprocessed_data(epochs_data, labels, subject_id, processed_dir, config)

    print(f"\nSubject {subject_id} processed successfully")


def main():
    """Main preprocessing pipeline."""
    print("\n" + "="*60)
    print("BCI Competition IIIa - Data Preprocessing Pipeline")
    print("="*60)

    # Load configuration
    config = load_config()

    # Get subject files
    subjects = config['paths']['subjects']

    print(f"\nSubjects to process: {len(subjects)}")
    for i, subject in enumerate(subjects, 1):
        print(f"  {i}. {subject}")

    # Process each subject
    for subject_file in subjects:
        try:
            process_subject(subject_file, config)
        except Exception as e:
            print(f"\n[ERROR] Error processing {subject_file}: {e}")
            import traceback
            traceback.print_exc()
            continue

    print("\n" + "="*60)
    print("Preprocessing complete")
    print("="*60)

    # Summary
    processed_dir = PROJECT_ROOT / config['paths']['processed_data']
    processed_files = list(processed_dir.glob("*.npz"))
    print(f"\nProcessed files saved in: {processed_dir}")
    print(f"Total files: {len(processed_files)}")
    for f in sorted(processed_files):
        print(f"  - {f.name}")


if __name__ == "__main__":
    main()
