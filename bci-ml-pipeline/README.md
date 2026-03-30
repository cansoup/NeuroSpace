# BCI ML Pipeline

Machine learning pipeline for classifying motor imagery from EEG signals using the BCI Competition IIIa dataset.

## Overview

This pipeline implements an EEGNet model to classify EEG signals into 4 motor imagery classes:
- **Left** - Left hand motor imagery
- **Right** - Right hand motor imagery  
- **Down** - Foot motor imagery
- **Up** - Tongue motor imagery

## Model Performance

- **Architecture**: EEGNet (3,028 parameters)
- **Dataset**: BCI Competition IIIa (subject k3b)
- **Validation Accuracy**: 88.89%
- **Training samples**: 144 epochs
- **Validation samples**: 36 epochs
- **Training epochs**: 76

## Project Structure

```
bci-ml-pipeline/
├── models/
│   ├── architectures/
│   │   └── eegnet.py              # EEGNet PyTorch implementation
│   └── saved_models/
│       └── k3b_best.pth           # Trained model checkpoint
├── scripts/
│   ├── 1_preprocess_data.py       # Data preprocessing pipeline
│   ├── 2_train_baseline.py        # Model training script
│   ├── 3_evaluate_model.py        # Evaluation script
│   ├── classify_eeg.py            # Batch classification script
│   ├── online_classification.py   # Real-time WebSocket server
│   ├── bridge_server.py           # Production server with session management
│   └── README_INFERENCE.md        # Server documentation
├── notebooks/
│   ├── 00_preprocess_data.ipynb   # Data preprocessing
│   ├── 01_data_exploration.ipynb  # Exploratory data analysis
│   ├── 02_train_model.ipynb       # Model training
│   ├── 03_evaluate_results.ipynb  # Model evaluation with AUC-ROC
│   └── 04_model_inference.ipynb   # Inference examples
├── configs/
│   └── config.yaml                # Configuration file
├── data/
│   ├── raw/                       # Raw GDF files (not included)
│   └── processed/                 # Preprocessed data (not included)
├── results/
│   └── k3b/
│       └── training_history.npz   # Training metrics
└── requirements.txt
```

## Installation

```bash
pip install -r requirements.txt
```

## Dataset

The model was trained on the BCI Competition IIIa dataset:
- 3 subjects (k3b, k6b, l1b)
- 60 EEG channels
- 250 Hz sampling rate
- 4 motor imagery classes per subject

Download from: https://www.bbci.de/competition/iii/

Place GDF files in `data/raw/` to retrain or test.

## Usage

### Batch Classification

Process GDF files and output predictions:

```bash
python scripts/classify_eeg.py \
    --input data/raw/k3b.gdf \
    --model models/saved_models/k3b_best.pth \
    --output predictions.csv
```

Output CSV contains:
- Epoch index and timestamp
- Predicted class and label
- Confidence score
- Probability distribution across all classes

### Real-time Classification Server

Run a WebSocket server for real-time classification:

```bash
python scripts/bridge_server.py \
    --model models/saved_models/k3b_best.pth \
    --ws-port 8765
```

The server accepts EEG data via WebSocket and returns classification results.

See `scripts/README_INFERENCE.md` for protocol details.

### Training

Train a new model on the dataset:

```bash
# 1. Preprocess raw data
python scripts/1_preprocess_data.py

# 2. Train model
python scripts/2_train_baseline.py

# 3. Evaluate model
python scripts/3_evaluate_model.py
```

Alternatively, use the Jupyter notebooks for an interactive workflow.

## Configuration

Edit `configs/config.yaml` to modify:
- **Preprocessing**: Filter frequencies, epoch windows, baseline correction
- **Model architecture**: Dropout rate, kernel sizes, number of filters
- **Training**: Learning rate, batch size, number of epochs

## Preprocessing Pipeline

1. **Bandpass filter** (8-30 Hz) - Isolates motor imagery frequency range
2. **Notch filter** (50 Hz) - Removes powerline noise
3. **Epoch extraction** (-0.5 to 3.5 seconds around cue)
4. **Baseline correction** (using -0.5 to 0 seconds)
5. **Scaling** to microvolts

## Model Architecture

EEGNet is a compact convolutional neural network designed for EEG classification:

1. **Temporal convolution** - Learns frequency filters across time
2. **Depthwise spatial convolution** - Learns spatial filters per frequency
3. **Separable convolution** - Efficient feature extraction
4. **Classification head** - Dense layer with softmax output

Total parameters: 3,028 (compact and efficient)

## WebSocket Protocol

### Client → Server

```json
{
    "type": "eeg_data",
    "timestamp": 1234567890.123,
    "channels": 60,
    "samples": [[ch0_vals], [ch1_vals], ...],
    "sample_rate": 250
}
```

### Server → Client

```json
{
    "type": "prediction",
    "predicted_class": "left",
    "predicted_index": 0,
    "confidence": 0.8745,
    "probabilities": {
        "left": 0.8745,
        "right": 0.0892,
        "down": 0.0231,
        "up": 0.0132
    },
    "processing_time_ms": 45.2
}
```

## Results

Per-class validation accuracy (k3b subject):
- Balanced performance across all 4 classes
- Macro-averaged accuracy: 88.89%
- AUC-ROC scores available in evaluation notebook

Training history stored in `results/k3b/training_history.npz`.

## Files

- **Trained model**: `models/saved_models/k3b_best.pth`
- **Model architecture**: `models/architectures/eegnet.py`
- **Configuration**: `configs/config.yaml`
- **Training results**: `results/k3b/training_history.npz`

## Reference

EEGNet architecture based on:

Lawhern, V. J., Solon, A. J., Waytowich, N. R., Gordon, S. M., Hung, C. P., & Lance, B. J. (2018). EEGNet: a compact convolutional neural network for EEG-based brain–computer interfaces. Journal of Neural Engineering, 15(5), 056013.
