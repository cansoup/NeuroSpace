#!/usr/bin/env python3
"""Minimal WebSocket bridge server for a BCI -> visionOS demo.

Run on the machine that owns the EEG / ML pipeline.
It broadcasts small JSON command messages to any connected client.

Install:
    pip install websockets

Run:
    python bridge_server.py --host 0.0.0.0 --port 8765
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
from dataclasses import asdict, dataclass
from time import time_ns
from typing import Final

from websockets.asyncio.server import ServerConnection, serve

LOG: Final = logging.getLogger("bci-bridge")
CLIENTS: set[ServerConnection] = set()


@dataclass(slots=True)
class IntentMessage:
    type: str
    intent: str
    confidence: float
    timestamp_ms: int
    seq: int
    source: str = "mock"


@dataclass(slots=True)
class StatusMessage:
    type: str
    state: str
    message: str
    timestamp_ms: int


def now_ms() -> int:
    return time_ns() // 1_000_000


async def handler(websocket: ServerConnection) -> None:
    CLIENTS.add(websocket)
    peer = getattr(websocket, "remote_address", None)
    LOG.info("Client connected: %s", peer)

    await websocket.send(
        json.dumps(
            asdict(
                StatusMessage(
                    type="status",
                    state="connected",
                    message="BCI bridge connected",
                    timestamp_ms=now_ms(),
                )
            )
        )
    )

    try:
        async for message in websocket:
            LOG.info("Received from client: %s", message)
    except Exception as exc:  # pragma: no cover
        LOG.warning("Client loop ended: %s", exc)
    finally:
        CLIENTS.discard(websocket)
        LOG.info("Client disconnected: %s", peer)


async def broadcast(payload: dict) -> None:
    if not CLIENTS:
        LOG.info("No clients connected. Dropping payload: %s", payload)
        return

    message = json.dumps(payload)
    stale_clients: list[ServerConnection] = []
    for client in list(CLIENTS):
        try:
            await client.send(message)
        except Exception as exc:  # pragma: no cover
            LOG.warning("Failed to send to client: %s", exc)
            stale_clients.append(client)

    for client in stale_clients:
        CLIENTS.discard(client)


async def demo_loop(interval: float) -> None:
    sequence = 0
    demo_messages = [
        ("focus_left", 0.86),
        ("focus_right", 0.88),
        ("confirm", 0.93),
        ("idle", 0.99),
    ]

    while True:
        for intent, confidence in demo_messages:
            sequence += 1
            payload = asdict(
                IntentMessage(
                    type="intent",
                    intent=intent,
                    confidence=confidence,
                    timestamp_ms=now_ms(),
                    seq=sequence,
                )
            )
            LOG.info("Broadcasting: %s", payload)
            await broadcast(payload)
            await asyncio.sleep(interval)


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", default=8765, type=int)
    parser.add_argument("--interval", default=2.0, type=float)
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")

    async with serve(handler, args.host, args.port):
        LOG.info("BCI bridge listening on ws://%s:%d", args.host, args.port)
        await demo_loop(args.interval)


if __name__ == "__main__":
    asyncio.run(main())
