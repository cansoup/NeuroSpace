"""
BCI live inference — standalone deploy script.

Reads EEG from an LSL stream (published by OpenBCI GUI), runs the trained
EEG Conformer model continuously, and serves predictions over WebSocket so
the visionOS app can receive them.

Usage (Windows machine with headset):
    python bci_inference.py --continuous --bridge

The visionOS app on the Mac connects to:
    ws://WINDOWS_IP:8765/

Find the Windows IP by running FIND_MY_IP.bat.

Modes:
  --continuous   No cues needed. Imagine left/right/both for ~4 seconds and
                 the command fires automatically when the model is confident.
  --bridge       Serve predictions over WebSocket on port 8765.
  --model sota   EEG Conformer (default, uses visionpro_sota_finetuned.pth)
  --model baseline  EEGNet fallback (uses visionpro_best.pth if present)
"""

import argparse
import asyncio
import json
import queue
import sys
import threading
import time
from collections import deque
from pathlib import Path

import numpy as np
import torch
import mne
from pylsl import StreamInlet, resolve_byprop
import websockets

mne.set_log_level("ERROR")

# ---------------------------------------------------------------------------
# Paths — everything lives next to this script
# ---------------------------------------------------------------------------
SCRIPT_DIR      = Path(__file__).resolve().parent
sys.path.append(str(SCRIPT_DIR / "models"))
from eegnet import EEGNet

MODEL_PATH      = SCRIPT_DIR / "visionpro_best.pth"
SOTA_MODEL_PATH = SCRIPT_DIR / "visionpro_sota_finetuned.pth"
SOTA_CONFIG     = {"f1": 40, "depth": 6, "n_heads": 10}

# ---------------------------------------------------------------------------
# Signal processing constants — must match training exactly
# ---------------------------------------------------------------------------
CHANNELS_TO_USE = list(range(8))   # all 8 OpenBCI channels
SFREQ           = 250
EPOCH_SECONDS   = 4.0
N_TIMEPOINTS    = 1001             # tmin=0, tmax=4 inclusive at 250 Hz
BANDPASS_LOW    = 8.0
BANDPASS_HIGH   = 30.0
NOTCH_HZ        = 50.0
PAD_SECONDS     = 2.0              # IIR edge-transient guard each side
N_PAD_SAMPLES   = int(PAD_SECONDS * SFREQ)           # 500
N_WINDOW        = 2 * N_PAD_SAMPLES + N_TIMEPOINTS   # 2001 samples = 8 s

MI_MARKERS  = {769: ("left", 0), 770: ("right", 1), 773: ("both", 2)}
CLASS_NAMES = ["left", "right", "both"]

RESOLVE_TIMEOUT = 15.0
BUFFER_SECONDS  = 15.0
POLL_SLEEP      = 0.01
# Per-class confidence thresholds, tuned from live testing:
# RIGHT fires very cleanly (p~0.95+), LEFT is weaker (p~0.75), BOTH rarely clears 0.75.
THRESHOLDS = [0.60, 0.75, 0.45]  # [left, right, both]

# Continuous-mode tuning
INFER_INTERVAL = 0.5    # seconds between sliding-window inferences
DEBOUNCE_COUNT = 2      # consecutive same-class above-threshold wins needed
COOLDOWN       = 3.0    # seconds before next command is allowed

BRIDGE_PORT = 8765
DEVICE      = "cuda" if torch.cuda.is_available() else "cpu"


# ---------------------------------------------------------------------------
# Model loading
# ---------------------------------------------------------------------------

def load_model(model_type: str):
    path = SOTA_MODEL_PATH if model_type == "sota" else MODEL_PATH
    if not path.exists():
        raise SystemExit(
            f"Model file not found: {path.name}\n"
            f"Run PREPARE_PACKAGE.bat in this folder to copy it from the project."
        )
    checkpoint = torch.load(path, map_location=DEVICE, weights_only=False)
    arch = checkpoint.get("arch", "eegnet")

    if arch == "eeg_conformer_8ch":
        from eeg_conformer import EEGConformer
        model = EEGConformer(
            n_channels=len(CHANNELS_TO_USE),
            n_classes=len(MI_MARKERS),
            n_times=N_TIMEPOINTS,
            f1=SOTA_CONFIG["f1"],
            depth=SOTA_CONFIG["depth"],
            n_heads=SOTA_CONFIG["n_heads"],
        )
    else:
        model = EEGNet(
            n_channels=len(CHANNELS_TO_USE),
            n_classes=len(MI_MARKERS),
            n_timepoints=N_TIMEPOINTS,
            F1=8, D=2, F2=16, kernel_length=64, dropout=0.5,
        )

    model.load_state_dict(checkpoint["model_state_dict"])
    model.to(DEVICE).eval()
    val_acc = checkpoint.get("val_acc", float("nan"))
    print(f"Model : {arch}")
    print(f"File  : {path.name}  (val_acc={val_acc:.3f}, device={DEVICE})")
    return model


# ---------------------------------------------------------------------------
# WebSocket bridge
# ---------------------------------------------------------------------------

def _make_bridge_msg(pred_name, pred_idx, probs, session_id):
    conf = float(probs[pred_idx])
    return {
        "type": "prediction",
        "timestamp": time.time(),
        "session_id": session_id,
        "predicted_class": pred_name,
        "predicted_index": pred_idx,
        "confidence": round(conf, 3),
        "probabilities": {n: round(float(p), 3) for n, p in zip(CLASS_NAMES, probs)},
        "processing_time_ms": 0.0,
        "above_threshold": conf >= THRESHOLDS[pred_idx],
    }


async def _ws_handler(ws, clients):
    clients.add(ws)
    try:
        async for raw in ws:
            try:
                msg = json.loads(raw)
                if msg.get("type") == "ping":
                    await ws.send(json.dumps({"type": "pong", "timestamp": time.time()}))
                elif msg.get("type") == "reset":
                    await ws.send(json.dumps({"type": "status", "message": "Buffer reset"}))
            except Exception:
                pass
    except Exception:
        pass
    finally:
        clients.discard(ws)


async def _broadcaster(q, clients):
    while True:
        try:
            pred = q.get_nowait()
            msg  = json.dumps(pred)
            dead = set()
            for ws in list(clients):
                try:
                    await ws.send(msg)
                except Exception:
                    dead.add(ws)
            clients -= dead
        except queue.Empty:
            pass
        await asyncio.sleep(0.01)


def _run_bridge(port, q):
    clients = set()

    async def _main():
        async with websockets.serve(lambda ws: _ws_handler(ws, clients), "0.0.0.0", port):
            print(f"Bridge : ws://0.0.0.0:{port}/")
            print(f"         visionOS connects to ws://<this machine's IP>:{port}/\n")
            await _broadcaster(q, clients)

    asyncio.run(_main())


# ---------------------------------------------------------------------------
# LSL helpers
# ---------------------------------------------------------------------------

def resolve_stream(stream_type, expect_rate=None, min_channels=None):
    print(f"Looking for LSL '{stream_type}' stream (up to {RESOLVE_TIMEOUT}s)...")
    streams = resolve_byprop("type", stream_type, timeout=RESOLVE_TIMEOUT)
    if not streams:
        raise SystemExit(
            f"\nNo LSL stream of type '{stream_type}' found.\n"
            f"Make sure OpenBCI GUI is running and LSL output is enabled:\n"
            f"  OpenBCI GUI -> Networking -> LSL -> Start"
        )
    info  = streams[0]
    srate = info.nominal_srate()
    nch   = info.channel_count()
    print(f"  Found: '{info.name()}'  {srate} Hz  {nch} channels")

    if expect_rate is not None and abs(srate - expect_rate) > 0.5:
        raise SystemExit(f"Expected ~{expect_rate} Hz for {stream_type}, got {srate}.")
    if min_channels is not None and nch < min_channels:
        raise SystemExit(f"Expected at least {min_channels} channels for {stream_type}, got {nch}.")

    return StreamInlet(info, max_chunklen=0)


# ---------------------------------------------------------------------------
# Preprocessing
# ---------------------------------------------------------------------------

def preprocess_epoch(samples: np.ndarray) -> torch.Tensor:
    """samples: (n_ch, N_WINDOW) — returns (1,1,n_ch,N_TIMEPOINTS) tensor."""
    n_ch = samples.shape[0]
    ch_names = [f"Ch{i+1}" for i in CHANNELS_TO_USE]
    info = mne.create_info(ch_names=ch_names, sfreq=SFREQ, ch_types=["eeg"] * n_ch)
    raw  = mne.io.RawArray(samples, info, verbose=False)
    raw.filter(l_freq=BANDPASS_LOW, h_freq=BANDPASS_HIGH, method="iir", verbose=False)
    raw.notch_filter(freqs=NOTCH_HZ, method="iir", verbose=False)
    filtered = raw.get_data()

    if filtered.shape[1] >= N_PAD_SAMPLES + N_TIMEPOINTS:
        epoch = filtered[:, N_PAD_SAMPLES : N_PAD_SAMPLES + N_TIMEPOINTS]
    else:
        start = max(0, (filtered.shape[1] - N_TIMEPOINTS) // 2)
        epoch = filtered[:, start : start + N_TIMEPOINTS]
        if epoch.shape[1] < N_TIMEPOINTS:
            pad   = np.zeros((n_ch, N_TIMEPOINTS - epoch.shape[1]), dtype=epoch.dtype)
            epoch = np.concatenate([epoch, pad], axis=1)

    normalized = np.zeros_like(epoch)
    for c in range(n_ch):
        ch  = epoch[c]
        std = ch.std() + 1e-8
        normalized[c] = (ch - ch.mean()) / std

    return torch.from_numpy(normalized).float().unsqueeze(0).unsqueeze(0).to(DEVICE)


MIN_SIGNAL_UV = 1.0   # µV — median channel std below this = headset not on head

def _classify_latest(eeg_buffer, model):
    if len(eeg_buffer) < N_WINDOW:
        return None
    recent  = list(eeg_buffer)[-N_WINDOW:]
    samples = np.stack([s for _, s in recent], axis=1)
    if np.median(samples.std(axis=1)) < MIN_SIGNAL_UV:
        return "flat", -1, None   # sentinel: signal too weak
    x       = preprocess_epoch(samples)
    with torch.no_grad():
        probs = torch.softmax(model(x), dim=1)[0].cpu().numpy()
    pred_idx = int(np.argmax(probs))
    return CLASS_NAMES[pred_idx], pred_idx, probs


# ---------------------------------------------------------------------------
# Continuous (async) loop — the main live mode
# ---------------------------------------------------------------------------

def _continuous_loop(model, eeg_inlet, bridge_q, session_id):
    """
    Sliding-window inference every 500 ms. No markers or cues required.

    Hold the imagined movement for ~4 seconds. The model fires when the same
    class wins DEBOUNCE_COUNT times in a row above THRESHOLD confidence, then
    waits COOLDOWN seconds before the next command.
    """
    max_buf    = int(BUFFER_SECONDS * SFREQ)
    eeg_buffer = deque(maxlen=max_buf)
    recent_preds: deque = deque(maxlen=DEBOUNCE_COUNT)
    last_fire_time  = 0.0
    last_infer_time = 0.0
    fired = 0

    print(f"Continuous mode  |  thresholds left={THRESHOLDS[0]} right={THRESHOLDS[1]} both={THRESHOLDS[2]}  debounce={DEBOUNCE_COUNT}x  cooldown={COOLDOWN}s")
    print(f"Buffering {N_WINDOW/SFREQ:.0f} seconds of EEG before first inference...\n")

    try:
        while True:
            chunk, ts = eeg_inlet.pull_chunk(timeout=0.0, max_samples=256)
            if chunk:
                arr = np.asarray(chunk)[:, CHANNELS_TO_USE]
                for t, row in zip(ts, arr):
                    eeg_buffer.append((t, row.astype(np.float32)))

            now = time.time()
            if now - last_infer_time < INFER_INTERVAL:
                time.sleep(POLL_SLEEP)
                continue

            if len(eeg_buffer) < N_WINDOW:
                pct = 100 * len(eeg_buffer) / N_WINDOW
                print(f"  buffering {pct:.0f}%...", end="\r", flush=True)
                time.sleep(POLL_SLEEP)
                continue

            last_infer_time = now
            result = _classify_latest(eeg_buffer, model)
            if result is None:
                continue
            pred_name, pred_idx, probs = result
            if pred_idx == -1:
                print("  [flat signal — headset not on head?]", end="\r", flush=True)
                recent_preds.clear()
                continue
            conf = float(probs[pred_idx])
            gate = "ABOVE" if conf >= THRESHOLDS[pred_idx] else "below"

            bar = "  ".join(f"{n}={probs[i]:.2f}" for i, n in enumerate(CLASS_NAMES))
            print(f"  [{pred_name:<5} p={conf:.2f} {gate}]  {bar}", end="\r", flush=True)

            in_cooldown = (now - last_fire_time) < COOLDOWN
            if in_cooldown:
                remaining = COOLDOWN - (now - last_fire_time)
                print(f"  [cooldown {remaining:.1f}s]", end="\r", flush=True)
                recent_preds.clear()
            else:
                recent_preds.append((pred_idx, conf))
                if (len(recent_preds) == DEBOUNCE_COUNT):
                    idxs  = [p[0] for p in recent_preds]
                    confs = [p[1] for p in recent_preds]
                    if len(set(idxs)) == 1 and min(confs) >= THRESHOLDS[idxs[0]]:
                        last_fire_time = now
                        fired += 1
                        recent_preds.clear()
                        print(f"\n[FIRE #{fired}] {pred_name.upper()}  p={conf:.2f}  -> sent to visionOS\n")
                        if bridge_q is not None:
                            try:
                                bridge_q.put_nowait(
                                    _make_bridge_msg(pred_name, pred_idx, probs, session_id)
                                )
                            except queue.Full:
                                pass

            time.sleep(POLL_SLEEP)

    except KeyboardInterrupt:
        print(f"\nStopped. Commands fired: {fired}")


# ---------------------------------------------------------------------------
# Epoch-locked loop — useful for accuracy testing with XDF replay
# ---------------------------------------------------------------------------

def _extract_padded_window(buffer, marker_ts):
    start_ts = marker_ts - PAD_SECONDS
    end_ts   = marker_ts + EPOCH_SECONDS + PAD_SECONDS
    pairs    = [(ts, s) for ts, s in buffer if start_ts <= ts <= end_ts]
    if not pairs:
        return None
    timestamps = np.array([ts for ts, _ in pairs])
    samples    = np.stack([s for _, s in pairs], axis=1)
    marker_idx   = int(np.argmin(np.abs(timestamps - marker_ts)))
    target_total = N_PAD_SAMPLES + N_TIMEPOINTS + N_PAD_SAMPLES
    if marker_idx < N_PAD_SAMPLES:
        pad     = np.repeat(samples[:, :1], N_PAD_SAMPLES - marker_idx, axis=1)
        samples = np.concatenate([pad, samples], axis=1)
    elif marker_idx > N_PAD_SAMPLES:
        samples = samples[:, marker_idx - N_PAD_SAMPLES:]
    if samples.shape[1] < target_total:
        pad     = np.repeat(samples[:, -1:], target_total - samples.shape[1], axis=1)
        samples = np.concatenate([samples, pad], axis=1)
    elif samples.shape[1] > target_total:
        samples = samples[:, :target_total]
    return samples


def _epoch_locked_loop(model, eeg_inlet, marker_inlet, bridge_q, session_id):
    max_buf    = int(BUFFER_SECONDS * SFREQ)
    eeg_buffer = deque(maxlen=max_buf)
    pending    = []
    total = correct = 0
    per_class = {n: [0, 0] for n in CLASS_NAMES}

    print("Epoch-locked mode — waiting for markers 769/770/773. Press Ctrl-C to stop.\n")
    try:
        while True:
            chunk, ts = eeg_inlet.pull_chunk(timeout=0.0, max_samples=256)
            if chunk:
                arr = np.asarray(chunk)[:, CHANNELS_TO_USE]
                for t, row in zip(ts, arr):
                    eeg_buffer.append((t, row.astype(np.float32)))

            mk_chunk, mk_ts = marker_inlet.pull_chunk(timeout=0.0, max_samples=32)
            if mk_chunk:
                for marker_row, t in zip(mk_chunk, mk_ts):
                    try:
                        code = int(marker_row[0])
                    except (TypeError, ValueError):
                        continue
                    if code in MI_MARKERS:
                        name, idx = MI_MARKERS[code]
                        pending.append((t, idx, name))

            if pending and eeg_buffer:
                latest_ts     = eeg_buffer[-1][0]
                still_pending = []
                for marker_ts, true_idx, true_name in pending:
                    if latest_ts < marker_ts + EPOCH_SECONDS + PAD_SECONDS:
                        still_pending.append((marker_ts, true_idx, true_name))
                        continue
                    window = _extract_padded_window(eeg_buffer, marker_ts)
                    if window is None or window.shape[1] < SFREQ:
                        continue
                    x = preprocess_epoch(window)
                    with torch.no_grad():
                        probs = torch.softmax(model(x), dim=1)[0].cpu().numpy()
                    pred_idx  = int(np.argmax(probs))
                    pred_name = CLASS_NAMES[pred_idx]
                    conf      = float(probs[pred_idx])
                    total += 1
                    per_class[CLASS_NAMES[true_idx]][1] += 1
                    hit = pred_idx == true_idx
                    if hit:
                        correct += 1
                        per_class[CLASS_NAMES[true_idx]][0] += 1
                    tick = "+" if hit else "x"
                    print(f"[{total:>3}] true={true_name:<5} pred={pred_name:<5} "
                          f"p={conf:.2f} [{tick}]  acc={correct/total:.3f} ({correct}/{total})")
                    if bridge_q is not None:
                        try:
                            bridge_q.put_nowait(_make_bridge_msg(pred_name, pred_idx, probs, session_id))
                        except queue.Full:
                            pass
                pending = still_pending

            time.sleep(POLL_SLEEP)

    except KeyboardInterrupt:
        print("\nStopped.")
        if total:
            print(f"Overall: {correct/total:.3f} ({correct}/{total})")
            for n, (c, t) in per_class.items():
                if t:
                    print(f"  {n:<5}  {c/t:.3f} ({c}/{t})")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def _parse_args():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--model", choices=["sota", "baseline"], default="sota")
    p.add_argument("--continuous", action="store_true",
                   help="Async sliding-window mode — no cues needed")
    p.add_argument("--bridge", action="store_true",
                   help="Serve predictions over WebSocket on port 8765")
    return p.parse_args()


def main():
    args       = _parse_args()
    model      = load_model(args.model)
    session_id = f"session_{int(time.time())}"

    bridge_q = None
    if args.bridge:
        bridge_q = queue.Queue(maxsize=100)
        t = threading.Thread(target=_run_bridge, args=(BRIDGE_PORT, bridge_q), daemon=True)
        t.start()

    eeg_inlet = resolve_stream("EEG",
                               expect_rate=SFREQ,
                               min_channels=max(CHANNELS_TO_USE) + 1)

    if args.continuous:
        _continuous_loop(model, eeg_inlet, bridge_q, session_id)
    else:
        marker_inlet = resolve_stream("Markers")
        _epoch_locked_loop(model, eeg_inlet, marker_inlet, bridge_q, session_id)


if __name__ == "__main__":
    main()
