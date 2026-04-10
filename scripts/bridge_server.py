"""
bridge_server.py — BCI ML inference + WebSocket bridge.

Replaces the mock demo_loop in the original scripts/bridge_server.py with
a real EEGNet inference pipeline.

Two operating modes
-------------------
  --mode offline  Read epochs from the .xdf file in sequence and stream
                  them through the model at a configurable FPS (default 10).
                  Great for demos without a headset.

  --mode live     Pull EEG from a live Lab Streaming Layer (LSL) stream,
                  epoch in a sliding window, run inference, and broadcast
                  the result over WebSocket in near-real-time.

WebSocket message format (matches BCIWebSocketReceiver.swift exactly)
----------------------------------------------------------------------
Intent message:
  {
    "type"         : "intent",
    "intent"       : "moveLeft" | "moveRight" | "idle",
    "confidence"   : 0.91,          // float 0–1
    "timestamp_ms" : 1712701234567, // UNIX ms
    "seq"          : 42,
    "source"       : "eegnet"       // or "offline" / "mock"
  }

Status message:
  {
    "type"         : "status",
    "state"        : "connected" | "streaming" | "error",
    "message"      : "...",
    "timestamp_ms" : ...
  }

BCIIntent mapping (matches BCIIntent.swift):
  class 0 (left  MI) → "moveLeft"
  class 1 (right MI) → "moveRight"
  confidence < threshold → "idle"

Install:
    pip install pyxdf torch scipy pylsl websockets

Run (offline demo):
    python bridge_server.py --mode offline --xdf bci-mi-n-100.xdf --model model.pt

Run (live EEG):
    python bridge_server.py --mode live --model model.pt --lsl-stream obci_eeg1
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from time import time_ns
from typing import Final, Optional

import numpy as np
import torch
import torch.nn.functional as F
from websockets.asyncio.server import ServerConnection, serve

from eegnet import EEGNet
from preprocessing import HIGHCUT, LOWCUT, SFREQ, _bandpass, preprocess

LOG: Final = logging.getLogger("bci-bridge")
CLIENTS: set[ServerConnection] = set()

# ── Swift intent labels (must match BCIIntent.swift enum raw values) ─────────
INTENT_MAP = {
    0: "moveLeft",
    1: "moveRight",
}
IDLE_INTENT = "idle"
CONFIDENCE_THRESHOLD = 0.65   # below this → broadcast idle


# ── Message dataclasses ──────────────────────────────────────────────────────
@dataclass(slots=True)
class IntentMessage:
    type: str
    intent: str
    confidence: float
    timestamp_ms: int
    seq: int
    source: str = "eegnet"


@dataclass(slots=True)
class StatusMessage:
    type: str
    state: str
    message: str
    timestamp_ms: int


def now_ms() -> int:
    return time_ns() // 1_000_000


# ── WebSocket handlers ───────────────────────────────────────────────────────
async def handler(websocket: ServerConnection) -> None:
    CLIENTS.add(websocket)
    peer = getattr(websocket, "remote_address", None)
    LOG.info("Client connected: %s", peer)

    await websocket.send(
        json.dumps(asdict(StatusMessage(
            type="status", state="connected",
            message="BCI bridge connected (EEGNet)",
            timestamp_ms=now_ms(),
        )))
    )

    try:
        async for _ in websocket:
            pass  # accept pings/keep-alives silently
    except Exception as exc:
        LOG.warning("Client loop ended: %s", exc)
    finally:
        CLIENTS.discard(websocket)
        LOG.info("Client disconnected: %s", peer)


async def broadcast(payload: dict) -> None:
    if not CLIENTS:
        LOG.debug("No clients. Dropping: %s", payload)
        return
    message = json.dumps(payload)
    stale: list[ServerConnection] = []
    for client in list(CLIENTS):
        try:
            await client.send(message)
        except Exception:
            stale.append(client)
    for c in stale:
        CLIENTS.discard(c)


# ── Model loading ────────────────────────────────────────────────────────────
def load_model(model_path: str, device: torch.device) -> tuple[EEGNet, dict]:
    checkpoint = torch.load(model_path, map_location=device, weights_only=False)
    cfg = checkpoint["config"]
    model = EEGNet(**cfg).to(device)
    model.load_state_dict(checkpoint["model_state"])
    model.eval()
    LOG.info(
        "Loaded EEGNet: classes=%d, channels=%d, samples=%d  [val_acc=%.3f]",
        cfg["num_classes"], cfg["channels"], cfg["samples"],
        checkpoint.get("best_val_acc", float("nan")),
    )
    return model, cfg


def predict(model: EEGNet, epoch: np.ndarray, device: torch.device) -> tuple[str, float]:
    """
    Run EEGNet on a single epoch.

    Parameters
    ----------
    epoch : np.ndarray, shape (C, T)

    Returns
    -------
    intent : str  (e.g. "moveLeft")
    confidence : float
    """
    x = torch.from_numpy(epoch.astype(np.float32)).unsqueeze(0).unsqueeze(0)  # (1,1,C,T)
    x = x.to(device)
    with torch.no_grad():
        logits = model(x)
        probs = F.softmax(logits, dim=1).cpu().numpy()[0]

    class_id = int(probs.argmax())
    confidence = float(probs[class_id])

    if confidence < CONFIDENCE_THRESHOLD:
        return IDLE_INTENT, confidence
    return INTENT_MAP.get(class_id, IDLE_INTENT), confidence


# ── Offline mode ─────────────────────────────────────────────────────────────
async def offline_loop(model: EEGNet, device: torch.device, xdf_path: str, fps: float) -> None:
    """Stream pre-loaded epochs from the .xdf file through EEGNet, looping."""
    LOG.info("Offline mode: loading epochs from %s …", xdf_path)
    X, y = preprocess(xdf_path)   # (N,1,C,T)
    epochs = X.squeeze(1).numpy()  # (N,C,T)
    labels = y.numpy()
    LOG.info("Loaded %d epochs. Streaming at %.1f FPS …", len(epochs), fps)

    interval = 1.0 / fps
    seq = 0

    await broadcast(asdict(StatusMessage(
        type="status", state="streaming",
        message=f"Offline replay: {len(epochs)} trials",
        timestamp_ms=now_ms(),
    )))

    while True:
        for i, epoch in enumerate(epochs):
            seq += 1
            intent, confidence = predict(model, epoch, device)
            payload = asdict(IntentMessage(
                type="intent",
                intent=intent,
                confidence=round(confidence, 4),
                timestamp_ms=now_ms(),
                seq=seq,
                source="offline",
            ))
            LOG.info("Seq %d | true=%d | pred=%s | conf=%.3f", seq, labels[i], intent, confidence)
            await broadcast(payload)
            await asyncio.sleep(interval)


# ── Live LSL mode ─────────────────────────────────────────────────────────────
async def live_loop(
    model: EEGNet,
    device: torch.device,
    cfg: dict,
    lsl_stream_name: Optional[str],
    window_sec: float = 2.0,
    step_sec: float = 0.1,
) -> None:
    """Pull from a live LSL stream and run sliding-window inference."""
    try:
        import pylsl
    except ImportError:
        LOG.error("pylsl not installed. Run: pip install pylsl")
        sys.exit(1)

    LOG.info("Searching for LSL stream '%s' …", lsl_stream_name or "(any EEG)")
    streams = pylsl.resolve_byprop("type", "EEG", timeout=10)
    if lsl_stream_name:
        streams = [s for s in streams if s.name() == lsl_stream_name]

    if not streams:
        LOG.error("No LSL stream found. Is the EEG device streaming?")
        sys.exit(1)

    inlet = pylsl.StreamInlet(streams[0])
    sfreq = inlet.info().nominal_srate() or SFREQ
    n_channels = cfg["channels"]
    n_samples = cfg["samples"]
    window_samples = int(window_sec * sfreq)
    step_samples = max(1, int(step_sec * sfreq))

    LOG.info("LSL connected: %s @ %.1f Hz | window=%.1fs step=%.2fs",
             streams[0].name(), sfreq, window_sec, step_sec)

    await broadcast(asdict(StatusMessage(
        type="status", state="streaming",
        message=f"Live LSL: {streams[0].name()} @ {sfreq:.0f} Hz",
        timestamp_ms=now_ms(),
    )))

    buffer: list[np.ndarray] = []   # list of (C,) samples
    seq = 0

    while True:
        # Pull available samples
        chunk, _ = inlet.pull_chunk(max_samples=step_samples)
        if chunk:
            buffer.extend(np.array(chunk)[:, :n_channels])

        if len(buffer) >= window_samples:
            # Grab window
            window = np.array(buffer[-window_samples:]).T   # (C, T)
            # Bandpass
            window_f = _bandpass(window.T, LOWCUT, HIGHCUT, sfreq).T  # (C, T)
            # Normalise
            window_f = (window_f - window_f.mean(axis=1, keepdims=True)) / (
                window_f.std(axis=1, keepdims=True) + 1e-8
            )
            # Resize to model input if needed
            if window_f.shape[1] != n_samples:
                from scipy.signal import resample
                window_f = resample(window_f, n_samples, axis=1)

            seq += 1
            intent, confidence = predict(model, window_f, device)
            payload = asdict(IntentMessage(
                type="intent",
                intent=intent,
                confidence=round(confidence, 4),
                timestamp_ms=now_ms(),
                seq=seq,
                source="live",
            ))
            LOG.info("Seq %d | pred=%s | conf=%.3f", seq, intent, confidence)
            await broadcast(payload)

            # Slide buffer
            buffer = buffer[step_samples:]

        await asyncio.sleep(step_sec * 0.1)   # yield to event loop


# ── Main ─────────────────────────────────────────────────────────────────────
async def main() -> None:
    parser = argparse.ArgumentParser(description="BCI EEGNet WebSocket Bridge")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--model", required=True, help="Path to trained model (.pt)")
    parser.add_argument(
        "--mode", choices=["offline", "live", "mock"], default="offline",
        help="offline=replay .xdf | live=LSL stream | mock=hardcoded demo",
    )
    parser.add_argument("--xdf", default="bci-mi-n-100.xdf", help="Path to .xdf (offline mode)")
    parser.add_argument("--fps", type=float, default=5.0, help="Prediction rate in offline mode")
    parser.add_argument("--lsl-stream", default=None, help="LSL stream name (live mode)")
    parser.add_argument("--window", type=float, default=2.0, help="Epoch window size in seconds (live mode)")
    parser.add_argument("--step", type=float, default=0.2, help="Sliding step in seconds (live mode)")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    if args.mode == "mock":
        # Fallback: hardcoded demo without a trained model
        from VisionStudio_team5_main_scripts_bridge_server import demo_loop  # type: ignore
        LOG.warning("Mock mode: broadcasting canned intent sequence (no model loaded).")
        async with serve(handler, args.host, args.port):
            LOG.info("BCI bridge (mock) on ws://%s:%d", args.host, args.port)
            await demo_loop(2.0)
        return

    model, cfg = load_model(args.model, device)

    async with serve(handler, args.host, args.port):
        LOG.info("BCI bridge on ws://%s:%d  [mode=%s]", args.host, args.port, args.mode)

        if args.mode == "offline":
            await offline_loop(model, device, args.xdf, args.fps)
        elif args.mode == "live":
            await live_loop(
                model, device, cfg,
                lsl_stream_name=args.lsl_stream,
                window_sec=args.window,
                step_sec=args.step,
            )


if __name__ == "__main__":
    asyncio.run(main())
