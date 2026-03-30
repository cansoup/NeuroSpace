#!/usr/bin/env python3
"""
BCI EEG Online Classification Server - Real-time Streaming

This script implements a WebSocket server for real-time motor imagery classification.
It receives continuous EEG data from clients, maintains a sliding window buffer,
and returns predictions with low latency (<100ms).

Usage:
    python online_classification.py --model models/saved_models/fold_0_best.pth --port 8000

WebSocket Protocol:
    Client sends:
        {
            "type": "eeg_data",
            "timestamp": 1234567890.123,
            "channels": 60,
            "samples": [[ch1_vals...], [ch2_vals...], ...],  # Shape: (60, n_samples)
            "sample_rate": 250
        }

    Server responds:
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
            "processing_time_ms": 45.2
        }
"""

import asyncio
import json
import time
import argparse
from pathlib import Path
from collections import deque
import numpy as np
import yaml
import torch
import torch.nn.functional as F
from scipy import signal
import sys

# WebSocket server
try:
    import websockets
except ImportError:
    print("[ERROR] websockets package not found. Install with: pip install websockets")
    sys.exit(1)

# Add project root to path
PROJECT_ROOT = Path(__file__).parent.parent
sys.path.append(str(PROJECT_ROOT))

from models.architectures.eegnet import EEGNet


class EEGBuffer:
    """Sliding window buffer for continuous EEG data."""

    def __init__(self, n_channels: int, window_samples: int, sample_rate: int):
        """
        Initialize EEG buffer.

        Args:
            n_channels: Number of EEG channels
            window_samples: Number of samples in the sliding window
            sample_rate: Sampling rate in Hz
        """
        self.n_channels = n_channels
        self.window_samples = window_samples
        self.sample_rate = sample_rate
        self.buffer = deque(maxlen=window_samples)
        self.is_ready = False

    def add_samples(self, samples: np.ndarray):
        """
        Add new samples to the buffer.

        Args:
            samples: Array of shape (n_channels, n_samples)
        """
        # Add each time point to the buffer
        for i in range(samples.shape[1]):
            self.buffer.append(samples[:, i])

        # Mark buffer as ready when filled
        if len(self.buffer) >= self.window_samples:
            self.is_ready = True

    def get_window(self) -> np.ndarray:
        """
        Get current window of data.

        Returns:
            Array of shape (n_channels, window_samples) or None if not ready
        """
        if not self.is_ready:
            return None

        # Convert buffer to numpy array
        data = np.array(list(self.buffer))  # Shape: (window_samples, n_channels)
        data = data.T  # Transpose to (n_channels, window_samples)

        return data

    def reset(self):
        """Clear the buffer."""
        self.buffer.clear()
        self.is_ready = False


class OnlinePreprocessor:
    """Real-time preprocessing pipeline for EEG data."""

    def __init__(self, config: dict):
        """
        Initialize preprocessor.

        Args:
            config: Configuration dictionary
        """
        self.config = config
        self.sample_rate = config['preprocessing']['sfreq']

        # Design bandpass filter
        nyquist = self.sample_rate / 2
        low = config['preprocessing']['bandpass']['low'] / nyquist
        high = config['preprocessing']['bandpass']['high'] / nyquist
        self.sos_bandpass = signal.butter(4, [low, high], btype='band', output='sos')

        # Design notch filter
        notch_freq = config['preprocessing']['notch']['freq']
        Q = 30.0  # Quality factor
        b_notch, a_notch = signal.iirnotch(notch_freq, Q, self.sample_rate)
        self.b_notch = b_notch
        self.a_notch = a_notch

        # Baseline window
        self.baseline_window = config['preprocessing']['epoch']['baseline']

    def preprocess(self, data: np.ndarray) -> np.ndarray:
        """
        Apply preprocessing to EEG window.

        Args:
            data: Array of shape (n_channels, n_timepoints)

        Returns:
            Preprocessed array of same shape
        """
        # Apply bandpass filter
        data = signal.sosfiltfilt(self.sos_bandpass, data, axis=1)

        # Apply notch filter
        data = signal.filtfilt(self.b_notch, self.a_notch, data, axis=1)

        # Baseline correction
        baseline_start = int((self.baseline_window[0] + 0.5) * self.sample_rate)  # Relative to window start
        baseline_end = int((self.baseline_window[1] + 0.5) * self.sample_rate)
        baseline_mean = np.mean(data[:, baseline_start:baseline_end], axis=1, keepdims=True)
        data = data - baseline_mean

        # Scale to microvolts (CRITICAL: matches training preprocessing)
        data = data * 1e6

        return data


class ClassificationServer:
    """WebSocket server for real-time EEG classification."""

    def __init__(self, model_path: str, config: dict, device: torch.device,
                 confidence_threshold: float = 0.75):
        """
        Initialize classification server.

        Args:
            model_path: Path to trained model checkpoint
            config: Configuration dictionary
            device: Device to run inference on
            confidence_threshold: Minimum confidence for predictions
        """
        self.config = config
        self.device = device
        self.confidence_threshold = confidence_threshold

        # Load model
        self.model = self._load_model(model_path)

        # Initialize preprocessor
        self.preprocessor = OnlinePreprocessor(config)

        # Get parameters
        self.n_channels = config['model']['eegnet']['n_channels']
        self.sample_rate = config['preprocessing']['sfreq']
        self.window_duration = 4.0  # seconds (matches training: -0.5 to 3.5)
        self.window_samples = int(self.window_duration * self.sample_rate)

        # Class mapping
        self.class_mapping = config['preprocessing']['class_mapping']

        print(f"\n[OK] Classification server initialized")
        print(f"  Model: {Path(model_path).name}")
        print(f"  Device: {device}")
        print(f"  Confidence threshold: {confidence_threshold}")
        print(f"  Window: {self.window_duration}s ({self.window_samples} samples)")

    def _load_model(self, model_path: str) -> torch.nn.Module:
        """Load trained model from checkpoint."""
        model = EEGNet(
            n_classes=self.config['model']['eegnet']['n_classes'],
            n_channels=self.config['model']['eegnet']['n_channels'],
            n_timepoints=self.config['model']['eegnet']['n_timepoints'],
            F1=self.config['model']['eegnet']['F1'],
            D=self.config['model']['eegnet']['D'],
            F2=self.config['model']['eegnet']['F2'],
            kernel_length=self.config['model']['eegnet']['kernel_length'],
            dropout=self.config['model']['eegnet']['dropout'],
            pool_size=self.config['model']['eegnet']['pool_size']
        ).to(self.device)

        checkpoint = torch.load(model_path, map_location=self.device)
        model.load_state_dict(checkpoint['model_state_dict'])
        model.eval()

        return model

    def classify(self, data: np.ndarray) -> dict:
        """
        Classify EEG window.

        Args:
            data: Preprocessed EEG data of shape (n_channels, n_timepoints)

        Returns:
            Dictionary with prediction results
        """
        start_time = time.time()

        # Convert to tensor and add batch/channel dimensions
        X = torch.from_numpy(data).float().unsqueeze(0).unsqueeze(0)  # (1, 1, n_channels, n_timepoints)
        X = X.to(self.device)

        # Forward pass
        with torch.no_grad():
            outputs = self.model(X)
            probabilities = F.softmax(outputs, dim=1)
            predicted_idx = torch.argmax(probabilities, dim=1).item()
            confidence = probabilities[0, predicted_idx].item()

        # Get class label
        predicted_label = self.class_mapping[predicted_idx]

        # Convert probabilities to dict
        probs_dict = {
            self.class_mapping[i]: probabilities[0, i].item()
            for i in range(len(self.class_mapping))
        }

        processing_time = (time.time() - start_time) * 1000  # Convert to ms

        return {
            'predicted_index': predicted_idx,
            'predicted_class': predicted_label,
            'confidence': confidence,
            'probabilities': probs_dict,
            'processing_time_ms': processing_time,
            'above_threshold': confidence >= self.confidence_threshold
        }

    async def handle_client(self, websocket, path):
        """
        Handle WebSocket client connection.

        Args:
            websocket: WebSocket connection
            path: Connection path
        """
        client_id = id(websocket)
        print(f"\n[{time.strftime('%H:%M:%S')}] Client connected: {client_id}")

        # Create buffer for this client
        buffer = EEGBuffer(self.n_channels, self.window_samples, self.sample_rate)

        try:
            async for message in websocket:
                try:
                    # Parse incoming message
                    data = json.loads(message)

                    if data.get('type') == 'eeg_data':
                        # Extract EEG samples
                        samples = np.array(data['samples'])  # Shape: (n_channels, n_samples)
                        timestamp = data.get('timestamp', time.time())

                        # Validate shape
                        if samples.shape[0] != self.n_channels:
                            await websocket.send(json.dumps({
                                'type': 'error',
                                'message': f'Invalid channel count: expected {self.n_channels}, got {samples.shape[0]}'
                            }))
                            continue

                        # Add to buffer
                        buffer.add_samples(samples)

                        # Get window if ready
                        window = buffer.get_window()
                        if window is not None:
                            # Preprocess
                            preprocessed = self.preprocessor.preprocess(window)

                            # Classify
                            result = self.classify(preprocessed)

                            # Send response
                            response = {
                                'type': 'prediction',
                                'timestamp': timestamp,
                                'predicted_class': result['predicted_class'],
                                'predicted_index': result['predicted_index'],
                                'confidence': result['confidence'],
                                'probabilities': result['probabilities'],
                                'processing_time_ms': result['processing_time_ms'],
                                'above_threshold': result['above_threshold']
                            }

                            await websocket.send(json.dumps(response))

                    elif data.get('type') == 'reset':
                        # Reset buffer
                        buffer.reset()
                        await websocket.send(json.dumps({
                            'type': 'status',
                            'message': 'Buffer reset'
                        }))

                    else:
                        await websocket.send(json.dumps({
                            'type': 'error',
                            'message': f'Unknown message type: {data.get("type")}'
                        }))

                except json.JSONDecodeError:
                    await websocket.send(json.dumps({
                        'type': 'error',
                        'message': 'Invalid JSON format'
                    }))
                except Exception as e:
                    await websocket.send(json.dumps({
                        'type': 'error',
                        'message': f'Processing error: {str(e)}'
                    }))

        except websockets.exceptions.ConnectionClosed:
            print(f"[{time.strftime('%H:%M:%S')}] Client disconnected: {client_id}")


def load_config(config_path: str = "configs/config.yaml") -> dict:
    """Load configuration from YAML file."""
    config_file = PROJECT_ROOT / config_path
    with open(config_file, 'r') as f:
        config = yaml.safe_load(f)
    return config


async def main():
    """Main server loop."""
    parser = argparse.ArgumentParser(
        description="Real-time EEG classification WebSocket server"
    )
    parser.add_argument(
        '--model', '-m',
        type=str,
        required=True,
        help='Path to trained model checkpoint (.pth file)'
    )
    parser.add_argument(
        '--port', '-p',
        type=int,
        default=8000,
        help='WebSocket server port (default: 8000)'
    )
    parser.add_argument(
        '--host', '-H',
        type=str,
        default='0.0.0.0',
        help='WebSocket server host (default: 0.0.0.0)'
    )
    parser.add_argument(
        '--threshold', '-t',
        type=float,
        default=0.75,
        help='Confidence threshold for predictions (default: 0.75)'
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
    print("BCI EEG Online Classification Server")
    print("=" * 60)

    # Validate model path
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

    # Create server
    server = ClassificationServer(
        args.model,
        config,
        device,
        confidence_threshold=args.threshold
    )

    # Start WebSocket server
    print(f"\n{'='*60}")
    print(f"Starting WebSocket server on {args.host}:{args.port}")
    print(f"{'='*60}")
    print(f"\nServer ready. Waiting for connections...")
    print(f"Press Ctrl+C to stop\n")

    async with websockets.serve(server.handle_client, args.host, args.port):
        await asyncio.Future()  # Run forever


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n\nServer stopped by user")
