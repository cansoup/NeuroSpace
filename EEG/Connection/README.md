# BCI Bridge

The WebSocket bridge between the model backend and any client app (visionOS, web, etc.). This is the real production WebSocket interface — the JSON protocol and message shape are exactly what client apps should integrate against.

In this build, the prediction stream is generated from a deterministic cycle (`left → right → both`) instead of real model inference, so client apps can be integration-tested without the EEG headset or trained model present. When the trained model is wired in, only the function that generates each prediction changes; the WebSocket interface stays identical.

---

## Prerequisites

- Python 3.9 or newer
- One dependency: `websockets`

Verify Python:

```bash
python --version
```

If that prints something `< 3.9`, install a newer Python from [python.org](https://www.python.org/downloads/).

---

## Install

From this folder:

```bash
pip install -r requirements.txt
```

If `pip` warns about non-writable site-packages and falls back to user install, that's fine.

---

## Run

```bash
python bridge_server.py
```

Default behaviour:

- Binds `0.0.0.0:8765` so any device on your LAN can connect.
- Cycles through `left → right → both → left → …` with one prediction every **4 seconds** (matches the real BCI epoch cadence).
- Confidence values are randomised in [0.60, 0.95]; ~20 % of messages dip into [0.30, 0.70] so `above_threshold` flips to `false` occasionally — exercises the client's gating logic.

Useful flags:

```bash
python bridge_server.py --interval 1.0       # 1 prediction per second (faster manual testing)
python bridge_server.py --port 9000          # different port
python bridge_server.py --host 127.0.0.1     # localhost only (no LAN access)
```

The server logs every outbound message so you can correlate with what the client receives:

```
[+] Connected: ('192.168.1.42', 53221) (session_140234567_1745611200)
  -> ('192.168.1.42', 53221) left  p=0.82 (above threshold)
  -> ('192.168.1.42', 53221) right p=0.55 (below threshold)
  -> ('192.168.1.42', 53221) both  p=0.91 (above threshold)
```

Stop with `Ctrl-C`.

---

## Connecting from another device

The client device (visionOS Vision Pro, iPad, another laptop, browser, etc.) needs to be on the **same Wi-Fi network** as the host running this server, then connect to `ws://<HOST_IP>:8765/`.

### Find the host's LAN IP

**Windows:**
```powershell
ipconfig
```
Look for `IPv4 Address . . . : 192.168.x.y` under your active Wi-Fi adapter.

**macOS:**
```bash
ipconfig getifaddr en0     # Wi-Fi
# or
ifconfig | grep "inet "    # all interfaces
```

**Linux:**
```bash
ip addr show               # or `hostname -I` for a quick one-liner
```

Look for the `192.168.x.y` or `10.x.y.z` address (NOT `127.0.0.1` and NOT `169.254.x.y`).

### Allow the firewall (host side, first time only)

**Windows:** A Windows Defender prompt usually appears the first time the server runs — accept "Private networks". If no prompt appeared and clients can't reach you, add a manual rule:
- Windows Defender Firewall → Advanced Settings → Inbound Rules → New Rule
- Type: Port → TCP → 8765 → Allow → Apply to Private profile

**macOS:** System Settings → Network → Firewall → "Allow incoming connections" for `python` (or disable the firewall on the LAN you trust).

**Linux:** Usually permissive by default. If you have `ufw`:
```bash
sudo ufw allow 8765/tcp
```

---

## Test connectivity before launching the real client

Two quick options:

### Option A: bundled Python tester

```bash
python test_client.py                          # localhost
python test_client.py --url ws://192.168.1.42:8765    # from another machine
```

Should print 4 prediction messages cycling through `left, right, both, left`, then exercise ping and reset.

### Option B: any browser dev console

Open a browser, hit F12, go to Console, paste:

```javascript
const ws = new WebSocket("ws://192.168.1.42:8765");
ws.onmessage = e => console.log(JSON.parse(e.data));
```

(Replace the IP with whatever your host machine prints.) Prediction objects should start arriving every 4 seconds.

---

## JSON wire format (what the server sends)

Every prediction looks like this:

```json
{
  "type": "prediction",
  "timestamp": 1745611234.567,
  "session_id": "session_140234567_1745611200",
  "predicted_class": "left",
  "predicted_index": 0,
  "confidence": 0.847,
  "probabilities": {
    "left":  0.847,
    "right": 0.092,
    "both":  0.061
  },
  "processing_time_ms": 12.4,
  "above_threshold": true
}
```

| Field | Type | Meaning |
|---|---|---|
| `type` | string | Always `"prediction"` for prediction messages. Switch on this in the app. |
| `timestamp` | number | Unix epoch seconds. |
| `session_id` | string | Stable per WebSocket connection. |
| `predicted_class` | string | One of `"left"`, `"right"`, `"both"`. |
| `predicted_index` | int | 0=left, 1=right, 2=both. |
| `confidence` | float | Probability of the predicted class, [0, 1]. |
| `probabilities` | object | All class probabilities; sum to ~1.0. |
| `processing_time_ms` | float | Server-side latency. |
| `above_threshold` | bool | `true` iff `confidence ≥ 0.75`. The app should ignore predictions where this is `false`. |

### Other message types the server can produce

The client may send:

```json
{ "type": "ping" }
{ "type": "reset" }
{ "type": "eeg_data", "samples": [[...]], "timestamp": 1745611234.567 }
```

The server will reply with:

```json
{ "type": "pong",   "timestamp": ..., "session_id": "..." }
{ "type": "status", "message": "Buffer reset", "session_id": "..." }
{ "type": "error",  "message": "Invalid JSON format", "session_id": "..." }
```

`eeg_data` messages are ignored in this build (no model is wired up yet); the server just logs them and keeps emitting predictions.

---

## Mapping to the visionOS app

- Eye tracking selects which virtual hand to control.
- `predicted_class == "left"` → that hand goes left.
- `predicted_class == "right"` → right.
- `predicted_class == "both"` → confirm / pop the bubble.
- Gate every action on `above_threshold == true`. Otherwise the hand twitches on low-confidence guesses.

---

## Troubleshooting

**"ConnectionRefusedError" from the test client.**
The server isn't running, or you're connecting to the wrong host/port. Confirm the server prints `Bridge listening on ws://...` and that you used the same port number.

**Server prints `[+] Connected` but no messages reach the client.**
Almost always a firewall / NAT issue between client and host. Test with the bundled `test_client.py` from the same machine first — if that works, the issue is network-side.

**Client connects then immediately disconnects.**
Most likely the client is parsing the wrong message shape. Confirm the client looks at `msg.type === "prediction"` first, then reads `predicted_class`. Errors during parse usually close the WebSocket.

**`above_threshold` is always true (or always false).**
The threshold is hard-coded to 0.75 in the server (`THRESHOLD = 0.75`) — change the constant in `bridge_server.py` if your client uses a different cutoff.

**Multiple devices testing at once.**
Supported. Each connection gets its own `session_id` and its own prediction stream (its own cycle starts at `left`).
