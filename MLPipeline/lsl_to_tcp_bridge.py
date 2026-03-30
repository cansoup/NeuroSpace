#!/usr/bin/env python3
"""
lsl_to_tcp_bridge.py  –  scripts/
==================================
Forwards EEG predictions from the LSL output stream to the visionOS app
over a plain TCP socket as newline-delimited JSON.

This is the glue between the Python ML pipeline and the Swift app.

  Python classifier  ──LSL──►  this script  ──TCP/JSON──►  Swift EEGPredictionBridge

Usage:
  python lsl_to_tcp_bridge.py [--host 0.0.0.0] [--port 12345]

The Swift EEGPredictionBridge connects to localhost:12345 and reads lines like:
  {"prediction": 1, "confidence": 0.87, "label": "left"}

Requirements:
  pip install pylsl
"""

import argparse
import json
import socket
import threading
import time

try:
    from pylsl import StreamInlet, resolve_stream
    HAS_LSL = True
except ImportError:
    HAS_LSL = False

LABEL_MAP = {0: "idle", 1: "left", 2: "right"}


# ─── Dummy source for testing without LSL ─────────────────────────────────────

class DummyInlet:
    """Cycles through predictions to simulate the classifier output."""
    _SEQ = [0, 0, 1, 1, 1, 0, 2, 2, 2, 0, 1, 0, 2, 0]
    _i   = 0

    def pull_sample(self, timeout: float = 1.0):
        time.sleep(0.25)
        val = self._SEQ[self._i % len(self._SEQ)]
        self._i += 1
        return [val], time.time()


# ─── Client handler ───────────────────────────────────────────────────────────

def handle_client(conn: socket.socket, addr, inbox: "queue.Queue"):
    """Write prediction JSON lines to a connected Swift client."""
    import queue
    print(f"[bridge] Client connected: {addr}")
    try:
        while True:
            try:
                payload = inbox.get(timeout=5.0)
                line = json.dumps(payload) + "\n"
                conn.sendall(line.encode())
            except queue.Empty:
                # Send keep-alive so the iOS TCP stack doesn't time out
                conn.sendall(b'{"prediction":0,"confidence":1.0,"label":"idle"}\n')
    except (BrokenPipeError, ConnectionResetError):
        pass
    finally:
        conn.close()
        print(f"[bridge] Client disconnected: {addr}")


# ─── Main loop ────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host",  default="0.0.0.0")
    parser.add_argument("--port",  type=int, default=12345)
    parser.add_argument("--dummy", action="store_true",
                        help="Use dummy data instead of real LSL stream")
    args = parser.parse_args()

    # Set up LSL inlet
    if args.dummy or not HAS_LSL:
        print("[bridge] Using dummy inlet (no LSL / --dummy flag set)")
        inlet = DummyInlet()
    else:
        print("[bridge] Resolving EEG_Prediction LSL stream…")
        streams = resolve_stream("name", "EEG_Prediction")
        inlet   = StreamInlet(streams[0])
        print("[bridge] LSL stream found.")

    # Per-client queues
    import queue
    clients: list[queue.Queue] = []
    clients_lock = threading.Lock()

    # TCP server
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((args.host, args.port))
    server.listen(5)
    print(f"[bridge] Listening on {args.host}:{args.port}")

    def accept_loop():
        while True:
            conn, addr = server.accept()
            q = queue.Queue(maxsize=20)
            with clients_lock:
                clients.append(q)
            t = threading.Thread(target=handle_client, args=(conn, addr, q), daemon=True)
            t.start()

    threading.Thread(target=accept_loop, daemon=True).start()

    # LSL pull loop → broadcast to all clients
    last_pred = -1
    while True:
        sample, _ts = inlet.pull_sample(timeout=1.0)
        if sample is None:
            continue

        pred = int(sample[0])
        payload = {
            "prediction": pred,
            "confidence": 1.0,          # EEGNet confidence not forwarded here;
            "label":      LABEL_MAP.get(pred, "unknown"),  # extend if needed
        }

        # Only push on change to avoid flooding Swift
        if pred != last_pred:
            last_pred = pred
            print(f"[bridge] → {payload['label']} ({pred})")
            dead = []
            with clients_lock:
                for q in clients:
                    try:
                        q.put_nowait(payload)
                    except Exception:
                        dead.append(q)
                for q in dead:
                    clients.remove(q)


if __name__ == "__main__":
    main()
