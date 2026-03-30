# BCI EEG Inference Scripts

This directory contains scripts for running inference on trained EEGNet models for motor imagery classification.

---

## Overview

Three inference scripts are provided:

1. **classify_eeg.py** - Batch classification of GDF files
2. **online_classification.py** - Real-time streaming classification server
3. **bridge_server.py** - Enhanced production server with session management

---

## Installation

### Required Dependencies

Install additional packages for inference:

```bash
pip install websockets aiohttp scipy
```

All other dependencies are already included in the main `requirements.txt`.

### Verify Installation

```bash
python scripts/classify_eeg.py --help
python scripts/online_classification.py --help
python scripts/bridge_server.py --help
```

---

## 1. Batch Classification (classify_eeg.py)

Process GDF files and output predictions to CSV.

### Usage

```bash
python scripts/classify_eeg.py \
    --input data/raw/k3b.gdf \
    --model models/saved_models/fold_0_best.pth \
    --output predictions.csv
```

### Arguments

- `--input`, `-i` (required): Path to input GDF file
- `--model`, `-m` (required): Path to trained model checkpoint (.pth file)
- `--output`, `-o` (default: `predictions.csv`): Path to output CSV file
- `--batch-size`, `-b` (default: 32): Batch size for inference
- `--device`, `-d` (default: auto): Device to use (auto/cuda/cpu)

### Output Format

CSV file with columns:

| Column | Description |
|--------|-------------|
| `epoch_index` | Sequential epoch number |
| `timestamp` | Time in seconds from recording start |
| `predicted_class` | Predicted class index (0-3) |
| `predicted_label` | Predicted class label (left/right/down/up) |
| `confidence` | Confidence score (0-1) |
| `prob_left` | Probability for left class |
| `prob_right` | Probability for right class |
| `prob_down` | Probability for down class |
| `prob_up` | Probability for up class |

### Example Output

```csv
epoch_index,timestamp,predicted_class,predicted_label,confidence,prob_left,prob_right,prob_down,prob_up
0,5.2,0,left,0.8745,0.8745,0.0892,0.0231,0.0132
1,10.4,1,right,0.7234,0.1123,0.7234,0.0987,0.0656
2,15.6,3,up,0.9012,0.0234,0.0123,0.0631,0.9012
```

### Example

```bash
# Process subject k3b
python scripts/classify_eeg.py \
    --input data/raw/k3b.gdf \
    --model models/saved_models/fold_0_best.pth \
    --output results/k3b_predictions.csv

# Use GPU if available
python scripts/classify_eeg.py \
    --input data/raw/k3b.gdf \
    --model models/saved_models/fold_0_best.pth \
    --output results/k3b_predictions.csv \
    --device cuda
```

---

## 2. Real-time Streaming (online_classification.py)

WebSocket server for real-time EEG classification.

### Usage

```bash
python scripts/online_classification.py \
    --model models/saved_models/fold_0_best.pth \
    --port 8000
```

### Arguments

- `--model`, `-m` (required): Path to trained model checkpoint (.pth file)
- `--port`, `-p` (default: 8000): WebSocket server port
- `--host`, `-H` (default: 0.0.0.0): WebSocket server host
- `--threshold`, `-t` (default: 0.75): Confidence threshold for predictions
- `--device`, `-d` (default: auto): Device to use (auto/cuda/cpu)

### WebSocket Protocol

#### Client → Server (EEG Data)

```json
{
    "type": "eeg_data",
    "timestamp": 1234567890.123,
    "channels": 60,
    "samples": [
        [ch0_sample0, ch0_sample1, ...],
        [ch1_sample0, ch1_sample1, ...],
        ...
    ],
    "sample_rate": 250
}
```

**Fields:**
- `type`: Must be `"eeg_data"`
- `timestamp`: Unix timestamp (seconds)
- `channels`: Number of EEG channels (must be 60)
- `samples`: 2D array of shape (60, n_samples) with EEG data in Volts
- `sample_rate`: Sampling rate in Hz (should be 250)

#### Server → Client (Prediction)

```json
{
    "type": "prediction",
    "timestamp": 1234567890.123,
    "predicted_class": "left",
    "predicted_index": 0,
    "confidence": 0.8745,
    "probabilities": {
        "left": 0.8745,
        "right": 0.0892,
        "down": 0.0231,
        "up": 0.0132
    },
    "processing_time_ms": 45.2,
    "above_threshold": true
}
```

**Fields:**
- `type`: `"prediction"`
- `timestamp`: Echo of input timestamp
- `predicted_class`: Predicted label (left/right/down/up)
- `predicted_index`: Predicted class index (0-3)
- `confidence`: Maximum probability (0-1)
- `probabilities`: Probability for each class
- `processing_time_ms`: Processing latency in milliseconds
- `above_threshold`: Boolean indicating if confidence exceeds threshold

#### Client → Server (Reset Buffer)

```json
{
    "type": "reset"
}
```

Clears the sliding window buffer.

#### Error Response

```json
{
    "type": "error",
    "message": "Error description"
}
```

### Example (Python Client)

```python
import asyncio
import websockets
import json
import numpy as np

async def stream_eeg():
    uri = "ws://localhost:8000"
    async with websockets.connect(uri) as websocket:
        # Simulate EEG data (60 channels, 10 samples)
        eeg_data = np.random.randn(60, 10) * 1e-6  # Volts

        message = {
            "type": "eeg_data",
            "timestamp": time.time(),
            "channels": 60,
            "samples": eeg_data.tolist(),
            "sample_rate": 250
        }

        await websocket.send(json.dumps(message))
        response = await websocket.recv()

        result = json.loads(response)
        if result['type'] == 'prediction':
            print(f"Predicted: {result['predicted_class']}")
            print(f"Confidence: {result['confidence']:.2%}")
            print(f"Latency: {result['processing_time_ms']:.1f} ms")

asyncio.run(stream_eeg())
```

### Example (JavaScript/TypeScript for visionOS)

See section below for Swift integration.

---

## 3. Bridge Server (bridge_server.py)

Enhanced production server with session management and health monitoring.

### Usage

```bash
python scripts/bridge_server.py \
    --model models/saved_models/fold_0_best.pth \
    --ws-port 8765 \
    --http-port 8080
```

### Arguments

- `--model`, `-m` (required): Path to trained model checkpoint (.pth file)
- `--ws-port`, `-p` (default: 8765): WebSocket server port
- `--http-port`, `-P` (default: 8080): HTTP health check port
- `--host`, `-H` (default: 0.0.0.0): Server host
- `--threshold`, `-t` (default: 0.75): Confidence threshold for predictions
- `--device`, `-d` (default: auto): Device to use (auto/cuda/cpu)

### Features

#### Session Management
- Multiple concurrent client connections
- Per-client EEG buffers
- Session tracking and statistics

#### Health Check Endpoint

```bash
curl http://localhost:8080/health
```

Response:
```json
{
    "status": "running",
    "uptime_seconds": 3600.5,
    "uptime_formatted": "1:00:00",
    "active_sessions": 3,
    "total_predictions": 15234,
    "total_errors": 12,
    "model_path": "models/saved_models/fold_0_best.pth",
    "device": "cuda:0",
    "confidence_threshold": 0.75
}
```

#### Additional WebSocket Commands

**Ping/Pong**
```json
// Client sends:
{"type": "ping"}

// Server responds:
{
    "type": "pong",
    "timestamp": 1234567890.123,
    "session_id": "session_140735268239616_1234567890"
}
```

**Session Statistics**
```json
// Client sends:
{"type": "stats"}

// Server responds:
{
    "type": "stats",
    "session_id": "session_140735268239616_1234567890",
    "uptime_seconds": 120.5,
    "predictions_count": 54,
    "errors_count": 0,
    "buffer_ready": true,
    "last_activity": 1234567890.123
}
```

### Example

```bash
# Start bridge server
python scripts/bridge_server.py \
    --model models/saved_models/fold_0_best.pth \
    --ws-port 8765 \
    --http-port 8080 \
    --threshold 0.75

# Check health (in another terminal)
curl http://localhost:8080/health

# Connect WebSocket client
# ws://localhost:8765
```

---

## visionOS Integration

### Swift WebSocket Client

```swift
import Foundation

class BCIWebSocketClient: NSObject, URLSessionWebSocketDelegate {
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!

    // Configuration
    let serverURL = URL(string: "ws://192.168.1.100:8765")!
    let confidenceThreshold: Float = 0.75

    override init() {
        super.init()
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    // MARK: - Connection

    func connect() {
        webSocketTask = urlSession.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        receiveMessage()
        print("WebSocket connected")
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        print("WebSocket disconnected")
    }

    // MARK: - Send EEG Data

    func sendEEGData(channels: [[Double]], timestamp: Double) {
        let message: [String: Any] = [
            "type": "eeg_data",
            "timestamp": timestamp,
            "channels": 60,
            "samples": channels,
            "sample_rate": 250
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("Failed to serialize EEG data")
            return
        }

        let message = URLSessionWebSocketTask.Message.string(jsonString)
        webSocketTask?.send(message) { error in
            if let error = error {
                print("WebSocket send error: \\(error)")
            }
        }
    }

    // MARK: - Receive Predictions

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                @unknown default:
                    break
                }

                // Continue receiving
                self?.receiveMessage()

            case .failure(let error):
                print("WebSocket receive error: \\(error)")
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        if type == "prediction" {
            handlePrediction(json)
        } else if type == "error" {
            if let errorMessage = json["message"] as? String {
                print("Server error: \\(errorMessage)")
            }
        }
    }

    private func handlePrediction(_ json: [String: Any]) {
        guard let predictedClass = json["predicted_class"] as? String,
              let confidence = json["confidence"] as? Double,
              let aboveThreshold = json["above_threshold"] as? Bool,
              let probabilities = json["probabilities"] as? [String: Double] else {
            return
        }

        // Only process high-confidence predictions
        if aboveThreshold {
            DispatchQueue.main.async {
                self.triggerUIAction(direction: predictedClass, confidence: confidence)
            }
        }

        // Log all predictions for monitoring
        print("Prediction: \\(predictedClass) (\\(String(format: "%.1f%%", confidence * 100)))")
    }

    // MARK: - UI Integration

    private func triggerUIAction(direction: String, confidence: Double) {
        // Map motor imagery to UI actions
        switch direction {
        case "left":
            // Trigger UI left action
            NotificationCenter.default.post(name: .bciNavigateLeft, object: nil)
        case "right":
            // Trigger UI right action
            NotificationCenter.default.post(name: .bciNavigateRight, object: nil)
        case "down":
            // Trigger UI down action
            NotificationCenter.default.post(name: .bciNavigateDown, object: nil)
        case "up":
            // Trigger UI up action
            NotificationCenter.default.post(name: .bciNavigateUp, object: nil)
        default:
            break
        }
    }
}

// Notification names for BCI control
extension Notification.Name {
    static let bciNavigateLeft = Notification.Name("bciNavigateLeft")
    static let bciNavigateRight = Notification.Name("bciNavigateRight")
    static let bciNavigateDown = Notification.Name("bciNavigateDown")
    static let bciNavigateUp = Notification.Name("bciNavigateUp")
}
```

### Usage in SwiftUI

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var bciClient = BCIWebSocketClient()
    @State private var lastCommand: String = "None"

    var body: some View {
        VStack {
            Text("BCI Control Active")
                .font(.largeTitle)

            Text("Last Command: \\(lastCommand)")
                .font(.headline)
                .padding()

            // Your UI elements here
        }
        .onAppear {
            bciClient.connect()
            setupNotifications()
        }
        .onDisappear {
            bciClient.disconnect()
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .bciNavigateLeft,
            object: nil,
            queue: .main
        ) { _ in
            lastCommand = "Left"
            // Handle left navigation
        }

        NotificationCenter.default.addObserver(
            forName: .bciNavigateRight,
            object: nil,
            queue: .main
        ) { _ in
            lastCommand = "Right"
            // Handle right navigation
        }

        NotificationCenter.default.addObserver(
            forName: .bciNavigateDown,
            object: nil,
            queue: .main
        ) { _ in
            lastCommand = "Down"
            // Handle down navigation
        }

        NotificationCenter.default.addObserver(
            forName: .bciNavigateUp,
            object: nil,
            queue: .main
        ) { _ in
            lastCommand = "Up"
            // Handle up navigation
        }
    }
}
```

---

## Performance Optimization

### GPU Acceleration

All scripts support GPU acceleration. Use `--device cuda` to force GPU usage or `--device auto` (default) for automatic detection.

```bash
# Check CUDA availability
python scripts/gpu_utils.py

# Run with GPU
python scripts/online_classification.py \
    --model models/saved_models/fold_0_best.pth \
    --device cuda
```

### Latency Optimization

Expected latencies (GPU):
- **Preprocessing**: ~5-10 ms
- **Model inference**: ~2-5 ms
- **Total**: <20 ms

Expected latencies (CPU):
- **Preprocessing**: ~15-25 ms
- **Model inference**: ~20-30 ms
- **Total**: ~50 ms

### Network Optimization

For production deployment:
1. Use wired Ethernet instead of Wi-Fi
2. Place server close to EEG acquisition device
3. Monitor network latency with ping tests
4. Consider local deployment on edge device

---

## Troubleshooting

### Issue: "Model checkpoint not found"

**Solution**: Verify model path exists
```bash
ls -lh models/saved_models/
```

### Issue: "CUDA out of memory"

**Solution**: Use CPU for inference
```bash
python scripts/online_classification.py \
    --model models/saved_models/fold_0_best.pth \
    --device cpu
```

### Issue: "Invalid channel count"

**Solution**: Ensure EEG data has exactly 60 channels. The model is trained on BCI Competition IIIa data with 60 EEG channels.

### Issue: "WebSocket connection refused"

**Solution**: Check if server is running
```bash
# Check if port is in use
netstat -an | grep 8000

# Start server
python scripts/online_classification.py \
    --model models/saved_models/fold_0_best.pth \
    --port 8000
```

### Issue: High latency (>100ms)

**Causes**:
1. Network latency (Wi-Fi)
2. CPU inference (use GPU)
3. Large batch sizes in preprocessing

**Solutions**:
```bash
# Use GPU
python scripts/online_classification.py \
    --model models/saved_models/fold_0_best.pth \
    --device cuda

# Reduce network latency
# - Use wired connection
# - Deploy server locally on edge device
```

### Issue: Low prediction accuracy

**Causes**:
1. Incorrect preprocessing (missing microvolts scaling)
2. Model-data mismatch
3. Poor EEG signal quality

**Solutions**:
1. Verify preprocessing matches training (scripts include scaling)
2. Ensure subject-specific model is used
3. Check EEG signal quality at acquisition

---

## Testing

### Test Batch Classification

```bash
# Process test file
python scripts/classify_eeg.py \
    --input data/raw/k3b.gdf \
    --model models/saved_models/fold_0_best.pth \
    --output test_predictions.csv

# Check output
head test_predictions.csv
```

### Test Online Server

**Terminal 1** (Start server):
```bash
python scripts/online_classification.py \
    --model models/saved_models/fold_0_best.pth \
    --port 8000
```

**Terminal 2** (Test client):
```python
# test_client.py
import asyncio
import websockets
import json
import numpy as np
import time

async def test():
    uri = "ws://localhost:8000"
    async with websockets.connect(uri) as ws:
        # Send test data
        eeg_data = np.random.randn(60, 10) * 1e-6
        message = {
            "type": "eeg_data",
            "timestamp": time.time(),
            "channels": 60,
            "samples": eeg_data.tolist(),
            "sample_rate": 250
        }
        await ws.send(json.dumps(message))

        # Receive response
        response = await ws.recv()
        print(json.loads(response))

asyncio.run(test())
```

### Test Bridge Server

**Terminal 1** (Start server):
```bash
python scripts/bridge_server.py \
    --model models/saved_models/fold_0_best.pth \
    --ws-port 8765 \
    --http-port 8080
```

**Terminal 2** (Health check):
```bash
curl http://localhost:8080/health
```

**Terminal 3** (WebSocket client):
```python
# Same as online_classification.py test, but use port 8765
```

---

## Deployment

### Local Deployment

For local testing with visionOS simulator:

```bash
# Start server on localhost
python scripts/bridge_server.py \
    --model models/saved_models/fold_0_best.pth \
    --host 127.0.0.1 \
    --ws-port 8765
```

Connect from visionOS: `ws://127.0.0.1:8765`

### Network Deployment

For deployment on local network:

```bash
# Find your IP address
# Windows: ipconfig
# macOS/Linux: ifconfig

# Start server on network interface
python scripts/bridge_server.py \
    --model models/saved_models/fold_0_best.pth \
    --host 0.0.0.0 \
    --ws-port 8765
```

Connect from visionOS: `ws://192.168.1.100:8765` (replace with your IP)

### Production Deployment

For production use:
1. Use `bridge_server.py` for robustness
2. Deploy on edge device close to EEG acquisition
3. Configure firewall to allow WebSocket port
4. Monitor health check endpoint
5. Set up logging and alerts

---

## Class Mapping

The model outputs 4 motor imagery classes mapped to directional UI control:

| Index | Class Label | Motor Imagery | UI Action |
|-------|-------------|---------------|-----------|
| 0 | `left` | Left hand | Navigate left |
| 1 | `right` | Right hand | Navigate right |
| 2 | `down` | Foot | Navigate down |
| 3 | `up` | Tongue | Navigate up |

---

## Additional Resources

- **Model Architecture**: See `models/architectures/eegnet.py`
- **Preprocessing**: See `notebooks/00_preprocess_data.ipynb`
- **Evaluation**: See `notebooks/03_evaluate_results.ipynb`
- **GPU Setup**: See `GPU_SETUP_GUIDE.md`

---

## Support

For issues or questions:
1. Check troubleshooting section above
2. Review main `README.md`
3. Check GPU setup guide: `GPU_SETUP_GUIDE.md`
4. Review training notebooks in `notebooks/`

---

**Last Updated**: 2024
**Pipeline Version**: 1.0
**Compatible Model**: EEGNet (BCI Competition IIIa)
