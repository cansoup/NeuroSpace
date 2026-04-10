# NeuroSpace — BCI ML Pipeline

Python ML pipeline for the NeuroSpace Apple Vision Pro BCI project.  
Reads EEG Motor Imagery data, trains EEGNet, and streams predictions to the visionOS app over WebSocket.

---

## Architecture

```
OpenBCI headset
      │ LSL stream (obci_eeg1 @ 250 Hz)
      ▼
┌─────────────────────────────────────────────────────┐
│                  bridge_server.py                   │
│                                                     │
│  [XDF / LSL]  →  preprocessing.py  →  EEGNet       │
│                   bandpass 8–30 Hz    (eegnet.py)   │
│                   baseline correct                  │
│                   normalise                         │
│                                                     │
│  Prediction  →  JSON over WebSocket ws://host:8765  │
└─────────────────────────────────────────────────────┘
      │ WebSocket
      ▼
BCIWebSocketReceiver.swift  →  BCIArmMapper  →  BubbleGameController
```

---

## Files

| File | Purpose |
|---|---|
| `eegnet.py` | EEGNet CNN architecture (PyTorch) |
| `preprocessing.py` | Load `.xdf`, bandpass, epoch, baseline-correct, normalise |
| `augment.py` | Data augmentation (noise, warp, scale, crop, channel dropout) |
| `train.py` | Single train/val/test split training |
| `train_cv.py` | 5-fold cross-validated training with augmentation (**recommended**) |
| `bridge_server.py` | WebSocket server — offline replay or live LSL inference |
| `requirements.txt` | Python dependencies |
| `model.pt` | Trained EEGNet weights (generated after training) |

---

## Quick Start

### 1. Install dependencies

```bash
pip install -r requirements.txt
```

### 2. Train the model

**Recommended — cross-validated with augmentation:**
```bash
python train_cv.py \
    --xdf bci-mi-n-100.xdf \
    --save model.pt \
    --folds 5 \
    --epochs 300 \
    --augments 4
```

**Simple single-split (faster):**
```bash
python train.py \
    --xdf bci-mi-n-100.xdf \
    --save model.pt \
    --epochs 150
```

Expected accuracy on this N=200 single-session dataset: **~65–72%** (literature baseline for EEGNet on similar datasets is 68–76%).

### 3. Run the bridge server

**Offline demo (replay .xdf through model, no headset needed):**
```bash
python bridge_server.py \
    --mode offline \
    --model model.pt \
    --xdf bci-mi-n-100.xdf \
    --fps 5
```

**Live EEG (OpenBCI headset streaming via LSL):**
```bash
python bridge_server.py \
    --mode live \
    --model model.pt \
    --lsl-stream obci_eeg1 \
    --window 2.0 \
    --step 0.2
```

### 4. Connect the visionOS app

In the Neurospace app lobby, enter the host IP of the machine running `bridge_server.py` and tap **Connect**.  
The default port is `8765`.

---

## WebSocket Message Format

The bridge broadcasts JSON matching `BCIWebSocketReceiver.swift`:

**Intent message** (sent after each prediction):
```json
{
  "type":         "intent",
  "intent":       "moveLeft",
  "confidence":   0.82,
  "timestamp_ms": 1712701234567,
  "seq":          42,
  "source":       "eegnet"
}
```

**Intent values** (matching `BCIIntent.swift`):

| Value | Meaning |
|---|---|
| `moveLeft` | Left-hand Motor Imagery detected |
| `moveRight` | Right-hand Motor Imagery detected |
| `idle` | Confidence below threshold — no action |

**Status message** (on connect / mode change):
```json
{
  "type":         "status",
  "state":        "connected",
  "message":      "BCI bridge connected (EEGNet)",
  "timestamp_ms": 1712701234567
}
```

---

## Preprocessing Details

| Step | Parameters |
|---|---|
| Bandpass filter | 8–30 Hz (mu + beta band), Butterworth order 5, zero-phase |
| Epoch window | 0.5 s → 2.5 s post-cue onset (2 s of Motor Imagery) |
| Baseline correction | −0.5 s → 0 s pre-cue mean subtracted |
| Normalisation | Per-channel, per-trial z-score |
| Input shape | `(N, 1, 8, 500)` — batch × 1 × channels × time |

**Marker codes** (GRAZ BCI standard, used in bci-mi-n-100.xdf):

| Code | Meaning |
|---|---|
| 768 | Cue onset (trial start) |
| 769 | Left-hand MI label |
| 770 | Right-hand MI label |
| 782 | Trial end |
| 32766 | Session start |

---

## EEGNet Architecture

```
Input: (batch, 1, 8, 500)
  │
  ├─ Block 1
  │   Conv2D  (1 → F1=8, kernel (1×64), temporal)
  │   BatchNorm
  │   DepthwiseConv2D  (F1 → F1×D=16, kernel (C×1), spatial)
  │   BatchNorm → ELU → AvgPool(1×4) → Dropout(0.3)
  │
  ├─ Block 2
  │   SeparableConv2D  (16 filters, kernel (1×16))
  │   BatchNorm → ELU → AvgPool(1×8) → Dropout(0.3)
  │
  └─ Classifier
      Flatten → Linear(→ 2)

Total parameters: ~1,700
Inference time: < 5 ms on CPU
```

---

## Data Augmentation (train_cv.py)

Applied only to training folds — never to validation or test data:

| Technique | Effect |
|---|---|
| Gaussian noise (SNR 15–25 dB) | Simulates electrode noise |
| Amplitude scaling (×0.8–1.2) | Session-to-session amplitude variability |
| Time warping (±10%) | Timing jitter in MI onset |
| Channel dropout (p=0.1) | Robustness to electrode contact loss |
| Random crop (80–95%) + resample | Shift-invariance in trial timing |

---

## Known Limitations & Mitigations

| Limitation | Impact | Mitigation |
|---|---|---|
| N=200 single-session recording | ~65–72% accuracy (vs chance 50%) | Add Nature multi-paradigm EEG dataset; transfer learning |
| 6-class labels not in dataset | 4 directions untrained | Binary left/right MVP; extend when more data collected |
| No subject-specific calibration | Inter-subject variability | Fine-tune on per-session calibration block |
| CPU inference only | ~5 ms/prediction | Acceptable for 5 Hz update rate; GPU not needed |

---

## Confidence Threshold

The bridge server applies a threshold of **0.65** before emitting an intent.  
Predictions below this are broadcast as `"intent": "idle"`.

- `BCIArmMapper.swift` applies a secondary threshold of 0.55 (lower — catches most bridge output).
- `BCIWebSocketReceiver.swift` applies 0.75 (more conservative, for UI display).

You can tune `CONFIDENCE_THRESHOLD` in `bridge_server.py` to balance sensitivity vs specificity.

---

## 6-Class Extension (Future)

When training data for up/down/forward/backward is available:

```bash
python train_cv.py --xdf extended_dataset.xdf --classes 6 --save model_6class.pt
python bridge_server.py --mode live --model model_6class.pt
```

The intent map in `bridge_server.py` and the `BCIIntent` enum in Swift are already structured for this extension.

---

## Integration with visionOS

The Python bridge replaces `BCIFakeInputService.swift` and `BCIJSONPlaybackService.swift` for live sessions.  
During development, JSON playback (`bci_test_data.json`) can still be used without running the bridge.

Connection flow:
1. Start `bridge_server.py` on the same local network as the Vision Pro.
2. Open the Neurospace lobby → enter the Python host IP → Connect.
3. Status changes to `Ready` when the WebSocket handshake completes.
4. Tap **Start Session** — the bridge begins streaming predictions.
