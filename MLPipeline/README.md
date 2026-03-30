# EEG Motor Imagery Pipeline — VisionStudio Team 5

End-to-end pipeline that reads EEG, classifies left/right hand motor imagery with **EEGNet**, and streams predictions to the visionOS bubble-popping app via LSL → TCP.

```
EEG headset
    │  LSL stream (type=EEG, 8ch @ 250 Hz)
    ▼
eeg_classifier.py          ← ML pipeline (EEGNet + sliding window + majority vote)
    │  LSL stream (EEG_Prediction, int32: 0=idle 1=left 2=right)
    ▼
lsl_to_tcp_bridge.py       ← converts LSL → TCP JSON for Swift
    │  TCP :12345  {"prediction":1,"label":"left"}
    ▼
EEGPredictionBridge.swift  ← SwiftUI @Observable, publishes EEGPrediction
    │
    ▼
ArmMovementController      ← animates RealityKit arm entities
    │
    ▼
BubbleGameView             ← visionOS game scene
```

---

## Files

| File | Description |
|------|-------------|
| `eeg_classifier.py` | Main ML pipeline. EEGNet training + online classification |
| `lsl_to_tcp_bridge.py` | Bridge server: LSL → TCP JSON (goes in `/scripts`) |
| `EEGPredictionBridge.swift` | Swift bridge + `ArmMovementController` |
| `BubbleGameView.swift` | Full visionOS RealityView integration example |
| `requirements.txt` | Python dependencies |

---

## Quick start

### 1 — Install Python dependencies
```bash
pip install -r requirements.txt
# Also install liblsl:  brew install labstreaminglayer/tap/lsl
```

### 2 — Train EEGNet on the XDF recording
```bash
python eeg_classifier.py --train --xdf bci-mi-n-100.xdf
# Runs 40 epochs, saves weights to eegnet_weights.pt
# Expected val_acc: ~0.60–0.70 (real BCI data, single subject)
```

### 3 — Start the classifier (offline replay for testing)
```bash
python eeg_classifier.py --xdf bci-mi-n-100.xdf --speed 1.0
# Replays the XDF at real-time speed, streaming predictions over LSL
```

### 4 — Start the TCP bridge (in a second terminal)
```bash
python lsl_to_tcp_bridge.py
# Listens on :12345, forwards predictions as JSON to Swift
```

### 5 — Run the visionOS app
The `EEGPredictionBridge` in Swift connects to `127.0.0.1:12345` automatically.
Set `bridge.demoMode = true` to test the UI without the Python pipeline running.

---

## Dataset notes (bci-mi-n-100.xdf)

| Property | Value |
|----------|-------|
| Channels | 8 (ch0,1,2,4,6,7 = EEG; ch3,5 = reference) |
| Sample rate | 250 Hz |
| Duration | ~28 min |
| Left MI trials | 200 |
| Right MI trials | 100 |
| Foot MI trials | 100 |
| Units | Raw hardware counts (not µV) — handled by per-epoch z-score |

**Class imbalance:** 2:1 left vs right. EEGNet training uses inverse-frequency class weights automatically.

---

## How the pipeline works

### Pre-processing (per sliding window)
1. Extract 2-second window from 8→6 EEG channels (drop ch3, ch5)
2. 4th-order Butterworth bandpass 8–30 Hz (mu + beta bands — MI-relevant)
3. Per-channel z-score normalisation

### EEGNet
Standard architecture from Lawhern et al. (2018):
- Block 1: temporal convolution (1×64) → depthwise spatial (C×1)
- Block 2: separable convolution (1×16)
- Classifier: linear → 3 classes (idle / left / right)

### Post-processing
- **Sliding window:** 2 s window, 0.25 s step → 4 Hz raw prediction rate
- **Majority vote:** smooth over last 5 predictions → final output rate 4 Hz

### Output
Integer label pushed to LSL stream `EEG_Prediction`:
- `0` = idle
- `1` = left hand MI  → Swift raises left arm
- `2` = right hand MI → Swift raises right arm

---

## Improving accuracy

The current ~60–65% accuracy is typical for a single-subject dataset without:
- Subject-specific electrode placement tuning
- Longer calibration recording
- Richer features (e.g. CSP spatial filter pre-trained per-subject)

For production, collect a short calibration run (5–10 min) with the actual headset and retrain:
```bash
python eeg_classifier.py --train --xdf calibration_run.xdf --epochs 60
```
