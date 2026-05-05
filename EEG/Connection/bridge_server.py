"""
BCI WebSocket bridge — the production WebSocket interface between the model
backend and any client app (visionOS, web, etc.).

Same WebSocket protocol and JSON message shape that will run in production.
In this build, the prediction stream is generated from a deterministic cycle
(left -> right -> both) instead of real model inference, so client apps can
be integration-tested without the headset or trained weights present. When
the trained model is wired in, only the prediction-generation function
changes — the WebSocket protocol stays identical.

Usage:
    python bridge_server.py
    python bridge_server.py --interval 1.0  # 1 prediction/sec for manual testing
    python bridge_server.py --port 8765 --host 0.0.0.0

Clients connect to ws://<host_lan_ip>:8765/. Find the host IP with `ipconfig`
(Windows) / `ipconfig getifaddr en0` (macOS) / `hostname -I` (Linux).
"""

import argparse
import asyncio
import json
import random
import time

import websockets


CLASSES = ["left", "right", "both"]
THRESHOLD = 0.75


def make_prediction(session_id: str, idx: int) -> dict:
    """Build one prediction message in the format the visionOS app expects."""
    predicted_class = CLASSES[idx % 3]
    predicted_index = idx % 3

    # 1 in 5 messages drops below threshold to test the app's gating.
    low_conf = random.random() < 0.2
    if low_conf:
        confidence = round(random.uniform(0.30, 0.70), 3)
    else:
        confidence = round(random.uniform(0.60, 0.95), 3)

    # Other-class probabilities split the remainder roughly evenly.
    leftover = 1.0 - confidence
    other_a = round(leftover * random.uniform(0.3, 0.7), 3)
    other_b = round(leftover - other_a, 3)
    probs = {}
    others = [c for c in CLASSES if c != predicted_class]
    probs[predicted_class] = confidence
    probs[others[0]] = other_a
    probs[others[1]] = other_b

    return {
        "type": "prediction",
        "timestamp": time.time(),
        "session_id": session_id,
        "predicted_class": predicted_class,
        "predicted_index": predicted_index,
        "confidence": confidence,
        "probabilities": probs,
        "processing_time_ms": round(random.uniform(8.0, 18.0), 1),
        "above_threshold": confidence >= THRESHOLD,
    }


async def handle_client(websocket, interval: float):
    """One connected app gets its own session and prediction stream."""
    session_id = f"session_{id(websocket)}_{int(time.time())}"
    peer = websocket.remote_address
    print(f"[+] Connected: {peer} ({session_id})")

    # Producer task: emit predictions on a timer.
    async def producer():
        idx = 0
        while True:
            try:
                msg = make_prediction(session_id, idx)
                await websocket.send(json.dumps(msg))
                gate = "above" if msg["above_threshold"] else "below"
                print(f"  -> {peer} {msg['predicted_class']:<5} "
                      f"p={msg['confidence']:.2f} ({gate} threshold)")
                idx += 1
                await asyncio.sleep(interval)
            except websockets.exceptions.ConnectionClosed:
                return

    # Consumer task: handle messages from the app (ping, reset, eeg_data).
    async def consumer():
        async for raw in websocket:
            try:
                msg = json.loads(raw)
            except json.JSONDecodeError:
                await websocket.send(json.dumps({
                    "type": "error",
                    "message": "Invalid JSON format",
                    "session_id": session_id,
                }))
                continue

            mtype = msg.get("type")
            if mtype == "ping":
                await websocket.send(json.dumps({
                    "type": "pong",
                    "timestamp": time.time(),
                    "session_id": session_id,
                }))
            elif mtype == "reset":
                await websocket.send(json.dumps({
                    "type": "status",
                    "message": "Buffer reset",
                    "session_id": session_id,
                }))
            elif mtype == "eeg_data":
                # No model to feed — log and acknowledge.
                samples = msg.get("samples", [])
                n_ch = len(samples) if samples else 0
                n_samp = len(samples[0]) if (samples and samples[0]) else 0
                print(f"  <- {peer} eeg_data: {n_ch}ch x {n_samp} samples (ignored)")
            else:
                await websocket.send(json.dumps({
                    "type": "error",
                    "message": f"Unknown message type: {mtype}",
                    "session_id": session_id,
                }))

    try:
        await asyncio.gather(producer(), consumer())
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        print(f"[-] Disconnected: {peer} ({session_id})")


async def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="0.0.0.0",
                        help="Bind address (default: 0.0.0.0 — accept LAN connections)")
    parser.add_argument("--port", type=int, default=8765,
                        help="WebSocket port (default: 8765)")
    parser.add_argument("--interval", type=float, default=4.0,
                        help="Seconds between predictions (default: 4.0, matches real pipeline)")
    args = parser.parse_args()

    print(f"Bridge listening on ws://{args.host}:{args.port}/")
    print(f"Cadence: 1 prediction every {args.interval:.1f} s, cycling left -> right -> both")
    print(f"Threshold gate: {THRESHOLD}; ~20% of messages will fall below")
    print("Press Ctrl-C to stop.\n")

    async with websockets.serve(
        lambda ws: handle_client(ws, args.interval),
        args.host,
        args.port,
    ):
        await asyncio.Future()  # run forever


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nStopped.")
