"""
Replay an XDF file as live LSL streams (EEG + Markers) at real-time speed.

Stand-in for XDFStreamer.exe when its GUI only lets you broadcast one stream
at a time. Produces the same two LSL outlets the consumer expects:
  - type='EEG', float32, 250 Hz, 8 channels (name: obci_eeg1)
  - type='Markers', int32, irregular rate, 1 channel

Usage:
    python scripts/xdf_replay.py              # defaults to data/visionpro-ml.xdf
    python scripts/xdf_replay.py path.xdf
"""

import sys
import time
from pathlib import Path

import numpy as np
import pyxdf
from pylsl import StreamInfo, StreamOutlet, cf_float32, cf_int32

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
DEFAULT_XDF = PROJECT_ROOT / "data" / "visionpro-ml.xdf"

EEG_CHUNK_SAMPLES = 25   # push EEG in 100 ms batches (25 / 250 Hz)


def find_streams(streams):
    eeg = next((s for s in streams if s["info"]["type"][0] == "EEG"), None)
    markers = next((s for s in streams if s["info"]["type"][0] == "Markers"), None)
    if eeg is None or markers is None:
        raise SystemExit("XDF must contain both an EEG stream and a Markers stream.")
    return eeg, markers


def make_outlets(eeg_stream):
    eeg_name = eeg_stream["info"]["name"][0]
    eeg_rate = float(eeg_stream["info"]["nominal_srate"][0])
    eeg_nch = int(eeg_stream["info"]["channel_count"][0])

    eeg_info = StreamInfo(
        name=eeg_name, type="EEG",
        channel_count=eeg_nch, nominal_srate=eeg_rate,
        channel_format=cf_float32, source_id=f"{eeg_name}_replay",
    )
    marker_info = StreamInfo(
        name="Markers", type="Markers",
        channel_count=1, nominal_srate=0,
        channel_format=cf_int32, source_id="markers_replay",
    )
    return StreamOutlet(eeg_info, chunk_size=EEG_CHUNK_SAMPLES), StreamOutlet(marker_info)


def build_event_schedule(eeg_stream, marker_stream):
    eeg_data = np.asarray(eeg_stream["time_series"], dtype=np.float32)  # (n_samples, n_ch)
    eeg_ts = np.asarray(eeg_stream["time_stamps"], dtype=np.float64)
    marker_data = marker_stream["time_series"]
    marker_ts = np.asarray(marker_stream["time_stamps"], dtype=np.float64)

    first_ts = min(eeg_ts[0], marker_ts[0])

    events = []
    # EEG batched into chunks so the Python loop doesn't fire 250 times/sec.
    for i in range(0, len(eeg_ts), EEG_CHUNK_SAMPLES):
        j = min(i + EEG_CHUNK_SAMPLES, len(eeg_ts))
        rel_t = eeg_ts[i] - first_ts
        events.append(("eeg", rel_t, eeg_data[i:j], eeg_ts[i:j]))

    for mrow, mt in zip(marker_data, marker_ts):
        try:
            code = int(mrow[0])
        except (TypeError, ValueError):
            continue
        events.append(("marker", mt - first_ts, code))

    events.sort(key=lambda e: e[1])
    duration = max(eeg_ts[-1], marker_ts[-1]) - first_ts
    return events, duration


def replay(xdf_path):
    print(f"Loading {xdf_path}...")
    streams, _ = pyxdf.load_xdf(str(xdf_path))
    eeg_stream, marker_stream = find_streams(streams)
    print(f"  EEG:     name='{eeg_stream['info']['name'][0]}' "
          f"rate={eeg_stream['info']['nominal_srate'][0]} Hz "
          f"channels={eeg_stream['info']['channel_count'][0]} "
          f"samples={len(eeg_stream['time_stamps'])}")
    print(f"  Markers: events={len(marker_stream['time_stamps'])}")

    eeg_outlet, marker_outlet = make_outlets(eeg_stream)
    print("LSL outlets created (type=EEG, type=Markers). Giving consumers a moment to connect...")
    time.sleep(1.0)

    events, duration = build_event_schedule(eeg_stream, marker_stream)
    print(f"Replaying {duration:.1f}s of data ({len(events)} events). Ctrl-C to stop.\n")

    start_wall = time.monotonic()
    eeg_pushed = 0
    markers_pushed = 0
    last_log = start_wall

    try:
        for ev in events:
            kind, rel_t = ev[0], ev[1]
            target = start_wall + rel_t
            delay = target - time.monotonic()
            if delay > 0:
                time.sleep(delay)

            if kind == "eeg":
                _, _, chunk, _ = ev
                # Let LSL timestamp with local_clock() at push time so EEG
                # and markers share the same clock (original XDF timestamps
                # are from a different recording session and would desync).
                eeg_outlet.push_chunk(chunk.tolist())
                eeg_pushed += len(chunk)
            else:
                _, _, code = ev
                marker_outlet.push_sample([code])
                markers_pushed += 1
                print(f"  [t={rel_t:6.1f}s] marker={code}")

            now = time.monotonic()
            if now - last_log >= 10.0:
                print(f"  progress: {rel_t:.1f}/{duration:.1f}s, "
                      f"EEG samples pushed={eeg_pushed}, markers={markers_pushed}")
                last_log = now

        print(f"\nReplay complete. EEG samples pushed={eeg_pushed}, markers={markers_pushed}.")
    except KeyboardInterrupt:
        print(f"\nStopped. EEG samples pushed={eeg_pushed}, markers={markers_pushed}.")


def main():
    xdf_path = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else DEFAULT_XDF
    if not xdf_path.exists():
        raise SystemExit(f"XDF file not found: {xdf_path}")
    replay(xdf_path)


if __name__ == "__main__":
    main()
