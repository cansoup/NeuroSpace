#!/usr/bin/env python3
"""
BCI EEG Bridge Server - Enhanced Integration Server

This is an enhanced WebSocket server for production deployment with:
- Multiple concurrent client connections
- Session management and tracking
- Model hot-swapping capability
- Health check endpoint
- Logging and monitoring
- Graceful shutdown

Usage:
    python bridge_server.py --model models/saved_models/fold_0_best.pth --port 8765

Features:
    - Session-based client management
    - Per-client EEG buffers
    - Real-time performance monitoring
    - Automatic error recovery
    - WebSocket and HTTP endpoints
"""

import asyncio
import json
import time
import argparse
import logging
from pathlib import Path
from collections import deque
from dataclasses import dataclass, field
from typing import Dict, Optional
import numpy as np
import yaml
import torch
import torch.nn.functional as F
from scipy import signal
import sys
from datetime import datetime

# WebSocket server
try:
    import websockets
except ImportError:
    print("[ERROR] websockets package not found. Install with: pip install websockets")
    sys.exit(1)

# HTTP server for health checks
try:
    from aiohttp import web
except ImportError:
    print("[ERROR] aiohttp package not found. Install with: pip install aiohttp")
    sys.exit(1)

# Add project root to path
PROJECT_ROOT = Path(__file__).parent.parent
sys.path.append(str(PROJECT_ROOT))

from models.architectures.eegnet import EEGNet


# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


@dataclass
class ClientSession:
    """Session data for a connected client."""
    session_id: str
    websocket: any  # WebSocket connection object
    buffer: 'EEGBuffer'
    connected_at: float = field(default_factory=time.time)
    last_activity: float = field(default_factory=time.time)
    predictions_count: int = 0
    errors_count: int = 0


class EEGBuffer:
    """Sliding window buffer for continuous EEG data."""

    def __init__(self, n_channels: int, window_samples: int, sample_rate: int):
        self.n_channels = n_channels
        self.window_samples = window_samples
        self.sample_rate = sample_rate
        self.buffer = deque(maxlen=window_samples)
        self.is_ready = False

    def add_samples(self, samples: np.ndarray):
        """Add new samples to the buffer."""
        for i in range(samples.shape[1]):
            self.buffer.append(samples[:, i])

        if len(self.buffer) >= self.window_samples:
            self.is_ready = True

    def get_window(self) -> Optional[np.ndarray]:
        """Get current window of data."""
        if not self.is_ready:
            return None

        data = np.array(list(self.buffer))  # (window_samples, n_channels)
        data = data.T  # (n_channels, window_samples)
        return data

    def reset(self):
        """Clear the buffer."""
        self.buffer.clear()
        self.is_ready = False


class OnlinePreprocessor:
    """Real-time preprocessing pipeline for EEG data."""

    def __init__(self, config: dict):
        self.config = config
        self.sample_rate = config['preprocessing']['sfreq']

        # Design filters
        nyquist = self.sample_rate / 2
        low = config['preprocessing']['bandpass']['low'] / nyquist
        high = config['preprocessing']['bandpass']['high'] / nyquist
        self.sos_bandpass = signal.butter(4, [low, high], btype='band', output='sos')

        notch_freq = config['preprocessing']['notch']['freq']
        Q = 30.0
        self.b_notch, self.a_notch = signal.iirnotch(notch_freq, Q, self.sample_rate)

        self.baseline_window = config['preprocessing']['epoch']['baseline']

    def preprocess(self, data: np.ndarray) -> np.ndarray:
        """Apply preprocessing to EEG window."""
        # Bandpass filter
        data = signal.sosfiltfilt(self.sos_bandpass, data, axis=1)

        # Notch filter
        data = signal.filtfilt(self.b_notch, self.a_notch, data, axis=1)

        # Baseline correction
        baseline_start = int((self.baseline_window[0] + 0.5) * self.sample_rate)
        baseline_end = int((self.baseline_window[1] + 0.5) * self.sample_rate)
        baseline_mean = np.mean(data[:, baseline_start:baseline_end], axis=1, keepdims=True)
        data = data - baseline_mean

        # Scale to microvolts
        data = data * 1e6

        return data


class BridgeServer:
    """Enhanced WebSocket server with session management."""

    def __init__(self, model_path: str, config: dict, device: torch.device,
                 confidence_threshold: float = 0.75):
        self.config = config
        self.device = device
        self.confidence_threshold = confidence_threshold
        self.model_path = model_path

        # Load model
        self.model = self._load_model(model_path)
        self.preprocessor = OnlinePreprocessor(config)

        # Server state
        self.sessions: Dict[str, ClientSession] = {}
        self.start_time = time.time()
        self.total_predictions = 0
        self.total_errors = 0

        # Parameters
        self.n_channels = config['model']['eegnet']['n_channels']
        self.sample_rate = config['preprocessing']['sfreq']
        self.window_duration = 4.0
        self.window_samples = int(self.window_duration * self.sample_rate)
        self.class_mapping = config['preprocessing']['class_mapping']

        logger.info("Bridge server initialized")
        logger.info(f"  Model: {Path(model_path).name}")
        logger.info(f"  Device: {device}")
        logger.info(f"  Confidence threshold: {confidence_threshold}")

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

        logger.info(f"Model loaded from checkpoint (epoch {checkpoint['epoch']}, val_acc {checkpoint['val_acc']:.4f})")
        return model

    def reload_model(self, model_path: str):
        """Hot-swap model with new checkpoint."""
        try:
            logger.info(f"Reloading model from {model_path}")
            self.model = self._load_model(model_path)
            self.model_path = model_path
            logger.info("Model reloaded successfully")
            return True
        except Exception as e:
            logger.error(f"Failed to reload model: {e}")
            return False

    def classify(self, data: np.ndarray) -> dict:
        """Classify EEG window."""
        start_time = time.time()

        X = torch.from_numpy(data).float().unsqueeze(0).unsqueeze(0)
        X = X.to(self.device)

        with torch.no_grad():
            outputs = self.model(X)
            probabilities = F.softmax(outputs, dim=1)
            predicted_idx = torch.argmax(probabilities, dim=1).item()
            confidence = probabilities[0, predicted_idx].item()

        predicted_label = self.class_mapping[predicted_idx]
        probs_dict = {
            self.class_mapping[i]: probabilities[0, i].item()
            for i in range(len(self.class_mapping))
        }

        processing_time = (time.time() - start_time) * 1000

        return {
            'predicted_index': predicted_idx,
            'predicted_class': predicted_label,
            'confidence': confidence,
            'probabilities': probs_dict,
            'processing_time_ms': processing_time,
            'above_threshold': confidence >= self.confidence_threshold
        }

    async def handle_websocket(self, websocket, path: str):
        """Handle WebSocket client connection."""
        session_id = f"session_{id(websocket)}_{int(time.time())}"
        buffer = EEGBuffer(self.n_channels, self.window_samples, self.sample_rate)

        session = ClientSession(
            session_id=session_id,
            websocket=websocket,
            buffer=buffer
        )
        self.sessions[session_id] = session

        logger.info(f"Client connected: {session_id} (total: {len(self.sessions)})")

        try:
            async for message in websocket:
                session.last_activity = time.time()

                try:
                    data = json.loads(message)
                    message_type = data.get('type')

                    if message_type == 'eeg_data':
                        await self._handle_eeg_data(session, data)

                    elif message_type == 'reset':
                        buffer.reset()
                        await websocket.send(json.dumps({
                            'type': 'status',
                            'message': 'Buffer reset',
                            'session_id': session_id
                        }))

                    elif message_type == 'ping':
                        await websocket.send(json.dumps({
                            'type': 'pong',
                            'timestamp': time.time(),
                            'session_id': session_id
                        }))

                    elif message_type == 'stats':
                        stats = self._get_session_stats(session)
                        await websocket.send(json.dumps(stats))

                    else:
                        await websocket.send(json.dumps({
                            'type': 'error',
                            'message': f'Unknown message type: {message_type}',
                            'session_id': session_id
                        }))

                except json.JSONDecodeError:
                    session.errors_count += 1
                    self.total_errors += 1
                    await websocket.send(json.dumps({
                        'type': 'error',
                        'message': 'Invalid JSON format',
                        'session_id': session_id
                    }))
                except Exception as e:
                    session.errors_count += 1
                    self.total_errors += 1
                    logger.error(f"Error processing message: {e}")
                    await websocket.send(json.dumps({
                        'type': 'error',
                        'message': f'Processing error: {str(e)}',
                        'session_id': session_id
                    }))

        except websockets.exceptions.ConnectionClosed:
            logger.info(f"Client disconnected: {session_id}")
        finally:
            if session_id in self.sessions:
                del self.sessions[session_id]
            logger.info(f"Session cleaned up: {session_id} (remaining: {len(self.sessions)})")

    async def _handle_eeg_data(self, session: ClientSession, data: dict):
        """Handle incoming EEG data."""
        samples = np.array(data['samples'])
        timestamp = data.get('timestamp', time.time())

        # Validate shape
        if samples.shape[0] != self.n_channels:
            raise ValueError(f'Invalid channel count: expected {self.n_channels}, got {samples.shape[0]}')

        # Add to buffer
        session.buffer.add_samples(samples)

        # Process if window ready
        window = session.buffer.get_window()
        if window is not None:
            # Preprocess
            preprocessed = self.preprocessor.preprocess(window)

            # Classify
            result = self.classify(preprocessed)

            # Update stats
            session.predictions_count += 1
            self.total_predictions += 1

            # Send response
            response = {
                'type': 'prediction',
                'timestamp': timestamp,
                'session_id': session.session_id,
                'predicted_class': result['predicted_class'],
                'predicted_index': result['predicted_index'],
                'confidence': result['confidence'],
                'probabilities': result['probabilities'],
                'processing_time_ms': result['processing_time_ms'],
                'above_threshold': result['above_threshold']
            }

            await session.websocket.send(json.dumps(response))

    def _get_session_stats(self, session: ClientSession) -> dict:
        """Get statistics for a session."""
        uptime = time.time() - session.connected_at
        return {
            'type': 'stats',
            'session_id': session.session_id,
            'uptime_seconds': uptime,
            'predictions_count': session.predictions_count,
            'errors_count': session.errors_count,
            'buffer_ready': session.buffer.is_ready,
            'last_activity': session.last_activity
        }

    def _get_server_stats(self) -> dict:
        """Get server-wide statistics."""
        uptime = time.time() - self.start_time
        return {
            'status': 'running',
            'uptime_seconds': uptime,
            'uptime_formatted': str(datetime.timedelta(seconds=int(uptime))),
            'active_sessions': len(self.sessions),
            'total_predictions': self.total_predictions,
            'total_errors': self.total_errors,
            'model_path': str(self.model_path),
            'device': str(self.device),
            'confidence_threshold': self.confidence_threshold
        }

    # HTTP health check endpoint
    async def health_check(self, request):
        """HTTP health check endpoint."""
        stats = self._get_server_stats()
        return web.json_response(stats)


def load_config(config_path: str = "configs/config.yaml") -> dict:
    """Load configuration from YAML file."""
    config_file = PROJECT_ROOT / config_path
    with open(config_file, 'r') as f:
        config = yaml.safe_load(f)
    return config


async def main():
    """Main server loop."""
    parser = argparse.ArgumentParser(
        description="BCI EEG Bridge Server - Enhanced WebSocket server with session management"
    )
    parser.add_argument(
        '--model', '-m',
        type=str,
        required=True,
        help='Path to trained model checkpoint (.pth file)'
    )
    parser.add_argument(
        '--ws-port', '-p',
        type=int,
        default=8765,
        help='WebSocket server port (default: 8765)'
    )
    parser.add_argument(
        '--http-port', '-P',
        type=int,
        default=8080,
        help='HTTP health check port (default: 8080)'
    )
    parser.add_argument(
        '--host', '-H',
        type=str,
        default='0.0.0.0',
        help='Server host (default: 0.0.0.0)'
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

    logger.info("=" * 60)
    logger.info("BCI EEG Bridge Server - Starting")
    logger.info("=" * 60)

    # Validate model path
    if not Path(args.model).exists():
        logger.error(f"Model checkpoint not found: {args.model}")
        return

    # Load configuration
    config = load_config()

    # Set device
    if args.device == 'auto':
        device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    else:
        device = torch.device(args.device)

    # Create server
    server = BridgeServer(
        args.model,
        config,
        device,
        confidence_threshold=args.threshold
    )

    # Start HTTP health check server
    app = web.Application()
    app.router.add_get('/health', server.health_check)
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, args.host, args.http_port)
    await site.start()

    logger.info(f"HTTP health check server started on http://{args.host}:{args.http_port}/health")
    logger.info(f"WebSocket server starting on ws://{args.host}:{args.ws_port}")
    logger.info("=" * 60)
    logger.info("Server ready. Waiting for connections...")
    logger.info("Press Ctrl+C to stop")
    logger.info("=" * 60)

    # Start WebSocket server
    async with websockets.serve(server.handle_websocket, args.host, args.ws_port):
        await asyncio.Future()  # Run forever


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("\nServer stopped by user")
