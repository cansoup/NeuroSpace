# BCI ML Pipeline - Motor Imagery Classification

Complete machine learning pipeline for 4-class motor imagery classification using EEGNet. This pipeline powers the Neurospace visionOS BCI game by decoding EEG signals into spatial control commands.

---

## 🎯 Quick Start for Industry Partners

### Running the Inference Server

```bash
# 1. Install dependencies
pip install -r requirements.txt

# 2. Start the production server
python scripts/bridge_server.py \
    --model models/saved_models/k3b_best.pth \
    --ws-port 8765 \
    --http-port 8080

# 3. Check server health
curl http://localhost:8080/health

# 4. Connect your visionOS app to ws://[server-ip]:8765
```

**Server Features:**
- Real-time EEG classification (<100ms latency)
- Multiple concurrent client connections
- Session management and health monitoring
- Automatic error recovery

See [scripts/README_INFERENCE.md](scripts/README_INFERENCE.md) for complete integration guide with Swift code examples.

---

## 📊 Model Performance

**Trained Model**: `models/saved_models/k3b_best.pth`

| Metric | Value |
|--------|-------|
| Architecture | EEGNet (3,028 parameters) |
| Dataset | BCI Competition IIIa (k3b subject) |
| Training samples | 144 epochs |
| Validation samples | 36 epochs |
| **Validation Accuracy** | **88.89%** |
| Training epochs | 76 |
| Per-class performance | Balanced across all 4 classes |

**Output Classes** (Motor Imagery → UI Control):
- **Class 0 (left)**: Left hand imagery → Navigate left
- **Class 1 (right)**: Right hand imagery → Navigate right
- **Class 2 (down)**: Foot imagery → Navigate down
- **Class 3 (up)**: Tongue imagery → Navigate up

---

## 📁 Project Structure

```
bci-ml-pipeline/
├── models/
│   ├── architectures/
│   │   ├── __init__.py
│   │   └── eegnet.py              # EEGNet PyTorch implementation
│   └── saved_models/
│       └── k3b_best.pth           # ✅ Trained model (88.89% acc)
├── scripts/
│   ├── classify_eeg.py            # 🆕 Batch classification
│   ├── online_classification.py   # 🆕 Real-time WebSocket server
│   ├── bridge_server.py           # 🆕 Production integration server
│   ├── README_INFERENCE.md        # 🆕 Complete integration guide
│   ├── 1_preprocess_data.py       # Data preprocessing pipeline
│   ├── 2_train_baseline.py        # Model training script
│   ├── 3_evaluate_model.py        # Evaluation script
│   └── gpu_utils.py               # GPU utilities
├── notebooks/
│   ├── 00_preprocess_data.ipynb   # ✨ Professional data preprocessing
│   ├── 01_data_exploration.ipynb  # ✨ EDA and visualization
│   ├── 02_train_model.ipynb       # ✨ Training workflow
│   ├── 03_evaluate_results.ipynb  # ✨ Evaluation with AUC-ROC
│   └── 04_model_inference.ipynb   # ✨ Inference demo
├── configs/
│   └── config.yaml                # All hyperparameters
├── data/
│   ├── raw/                       # Place GDF files here (gitignored)
│   ├── processed/                 # Preprocessed .npz files (gitignored)
│   └── interim/                   # Temporary files (gitignored)
├── results/
│   └── k3b/
│       └── training_history.npz   # Training metrics
├── requirements.txt               # Python dependencies
├── GPU_SETUP_GUIDE.md             # GPU setup instructions
├── .gitignore                     # Excludes large data files
└── README.md                      # This file
```

---

## 🚀 Three Ways to Use This Pipeline

### 1. **Real-time Inference** (Production - for visionOS integration)

```bash
# Start production server with session management
python scripts/bridge_server.py \
    --model models/saved_models/k3b_best.pth \
    --ws-port 8765 \
    --http-port 8080
```

Features: Health checks, multiple clients, session tracking, logging

### 2. **Streaming Classification** (Development)

```bash
# Start basic WebSocket server for testing
python scripts/online_classification.py \
    --model models/saved_models/k3b_best.pth \
    --port 8000
```

Features: Real-time sliding window buffer, <100ms latency

### 3. **Batch Processing** (Analysis)

```bash
# Process entire GDF files
python scripts/classify_eeg.py \
    --input data/raw/k3b.gdf \
    --model models/saved_models/k3b_best.pth \
    --output predictions.csv
```

Features: CSV output with predictions and confidence scores

---

## 🔗 visionOS Integration

The Neurospace visionOS app connects to the BCI server via WebSocket. The server receives EEG data, runs inference, and returns motor imagery classifications.

### Connection Flow

```
EEG Device → Python Server → WebSocket → visionOS App → 3D Game Control
             (this pipeline)    (port 8765)  (Neurospace)
```

### Swift Integration

See [scripts/README_INFERENCE.md](scripts/README_INFERENCE.md) for:
- Complete Swift WebSocket client code
- visionOS SwiftUI integration examples
- Protocol specification
- Troubleshooting guide

---

## 📝 Notebooks (Professional & Publication-Ready)

All notebooks include:
- ✅ Professional documentation
- ✅ Clear visualizations
- ✅ AUC-ROC metrics
- ✅ Class mapping (left/right/down/up)
- ✅ Ready for stakeholder review

**Recommended Reading Order:**
1. [00_preprocess_data.ipynb](notebooks/00_preprocess_data.ipynb) - Data pipeline
2. [01_data_exploration.ipynb](notebooks/01_data_exploration.ipynb) - Dataset analysis
3. [02_train_model.ipynb](notebooks/02_train_model.ipynb) - Model training
4. [03_evaluate_results.ipynb](notebooks/03_evaluate_results.ipynb) - Performance metrics
5. [04_model_inference.ipynb](notebooks/04_model_inference.ipynb) - Inference demo

---

## 🛠️ Setup & Installation

### Prerequisites

- Python 3.8+
- (Optional) CUDA-capable GPU for faster training

### Install Dependencies

```bash
cd bci-ml-pipeline
pip install -r requirements.txt

# For inference servers (WebSocket support)
pip install websockets aiohttp
```

### Download Dataset (Optional - for retraining)

The trained model is included, but if you want to retrain or experiment:

1. Download BCI Competition IIIa dataset from: https://www.bbci.de/competition/iii/
2. Place GDF files in `data/raw/`:
   - `k3b.gdf`
   - `k6b.gdf` (optional)
   - `l1b.gdf` (optional)

---

## 🔬 Training Your Own Model

```bash
# 1. Preprocess data
python scripts/1_preprocess_data.py

# 2. Train model
python scripts/2_train_baseline.py

# 3. Evaluate
python scripts/3_evaluate_model.py
```

Or use the interactive notebooks for a guided workflow.

---

## 📈 Training Results

**Subject k3b** (Best Performance):
- Final validation accuracy: 88.89%
- Training epochs: 76
- Model size: 3,028 parameters (compact & efficient)
- Per-class accuracy: Balanced

Training history is saved in `results/k3b/training_history.npz`.

---

## 🧪 Testing the Pipeline

### Test Batch Classification

```bash
# Process test file
python scripts/classify_eeg.py \
    --input data/raw/k3b.gdf \
    --model models/saved_models/k3b_best.pth \
    --output test_predictions.csv

# Check output
head test_predictions.csv
```

Expected output: CSV with 180 epochs, ~94% average confidence

### Test Real-time Server

**Terminal 1** (Start server):
```bash
python scripts/online_classification.py \
    --model models/saved_models/k3b_best.pth \
    --port 8000
```

**Terminal 2** (Check connection):
```bash
# Test with your visionOS app or use the Python test client
# See scripts/README_INFERENCE.md for examples
```

---

## 🎓 Technical Details

### Dataset

**BCI Competition IIIa**:
- 3 subjects (k3b, k6b, l1b)
- 60 EEG channels
- 250 Hz sampling rate
- 4 motor imagery classes

### Preprocessing

- Bandpass filter: 8-30 Hz (motor imagery band)
- Notch filter: 50 Hz (powerline noise)
- Epoch window: -0.5 to 3.5 seconds around cue
- Baseline correction: -0.5 to 0 seconds
- Scaling: Volts → microvolts (critical for performance)

### Model Architecture

**EEGNet**: Compact CNN designed for EEG-based BCIs

- Temporal convolution (capture frequency features)
- Depthwise convolution (spatial filters per frequency)
- Separable convolution (efficient feature extraction)
- Total parameters: 3,028 (lightweight for edge deployment)

Reference: [Lawhern et al. 2018](https://arxiv.org/abs/1611.08024)

---

## 🤝 Collaboration

### For Team Members

- **Notebooks**: Run notebooks in order for full pipeline walkthrough
- **Scripts**: Use scripts for automated training/inference
- **Config**: Modify `configs/config.yaml` for hyperparameter tuning

### For Industry Partner (Stanley Lam)

- **Quick Start**: See top of this README
- **Integration**: See [scripts/README_INFERENCE.md](scripts/README_INFERENCE.md)
- **Support**: Trained model and servers ready for deployment

---

## 📚 Additional Resources

- [GPU Setup Guide](GPU_SETUP_GUIDE.md) - CUDA installation and troubleshooting
- [Inference Guide](scripts/README_INFERENCE.md) - Complete integration documentation
- [BCI Competition IIIa](https://www.bbci.de/competition/iii/) - Original dataset
- [EEGNet Paper](https://arxiv.org/abs/1611.08024) - Architecture reference

---

## 📄 License

This project is part of the Neurospace visionOS BCI game developed by Team 5 - VisionStudio.

---

## 🎮 Integration with Neurospace

This ML pipeline powers the [Neurospace visionOS game](../README.md) - a BCI-controlled mixed-reality bubble popping game designed for upper-limb amputee rehabilitation.

**Pipeline → Game Flow:**
1. User imagines motor movements (left hand, right hand, foot, tongue)
2. EEG signals captured by BCI device
3. Signals sent to this Python pipeline via WebSocket
4. EEGNet model classifies intent (88.89% accuracy)
5. Classification sent back to visionOS app
6. Virtual arm moves in 3D space to pop bubbles

**Performance**: <100ms end-to-end latency for responsive gameplay.

---

**Last Updated**: March 2024
**Pipeline Version**: 1.0
**Model**: EEGNet (BCI Competition IIIa)
**Team**: VisionStudio Team 5
