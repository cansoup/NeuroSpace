"""
Connectivity tester for bridge_server.py.

Connects to a running server, prints the first few prediction messages,
exercises the ping and reset commands, then exits. Use this to verify the
LAN path before bringing the visionOS app into the loop.

Usage:
    python test_client.py                          # connects to ws://localhost:8765
    python test_client.py --url ws://192.168.1.42:8765
"""

import argparse
import asyncio
import json

import websockets


async def run(url: str, n_messages: int):
    print(f"Connecting to {url}...")
    async with websockets.connect(url) as ws:
        print("Connected.\n")

        # Receive a few prediction messages.
        for i in range(n_messages):
            raw = await asyncio.wait_for(ws.recv(), timeout=10.0)
            msg = json.loads(raw)
            if msg["type"] == "prediction":
                gate = "above" if msg["above_threshold"] else "below"
                print(f"  msg {i+1}: {msg['predicted_class']:<5} "
                      f"conf={msg['confidence']:.2f} ({gate} threshold) "
                      f"probs={msg['probabilities']}")
            else:
                print(f"  msg {i+1}: {msg}")

        # Test the ping/pong roundtrip.
        print("\nSending ping...")
        await ws.send(json.dumps({"type": "ping"}))
        for _ in range(8):
            m = json.loads(await asyncio.wait_for(ws.recv(), timeout=5.0))
            if m["type"] == "pong":
                print(f"  pong received OK")
                break

        # Test the reset/status roundtrip.
        print("\nSending reset...")
        await ws.send(json.dumps({"type": "reset"}))
        for _ in range(8):
            m = json.loads(await asyncio.wait_for(ws.recv(), timeout=5.0))
            if m["type"] == "status":
                print(f"  status received: {m['message']}")
                break

        print("\nAll checks passed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="ws://localhost:8765",
                        help="WebSocket URL (default: ws://localhost:8765)")
    parser.add_argument("--messages", type=int, default=4,
                        help="Number of prediction messages to receive (default: 4)")
    args = parser.parse_args()

    try:
        asyncio.run(run(args.url, args.messages))
    except (ConnectionRefusedError, OSError) as e:
        raise SystemExit(f"Could not reach {args.url}: {e}")


if __name__ == "__main__":
    main()
