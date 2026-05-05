# 🧠 NeuroSpace — BCI Bubble Pop

NeuroSpace is a **visionOS** app for Apple Vision Pro that enables upper-limb amputees to play a mixed-reality bubble-popping game using **Brain-Computer Interface (BCI)** signals decoded from EEG data. This project is an **MVP** built to demonstrate core gameplay and rehabilitation stage design for a potential clinical product.

---

## 🚀 Features

- Control a virtual arm pointer using **motor imagery** (no physical movement required)
- Pop 3D bubbles rendered in your real-world space via **passthrough AR**
- **Dual arm support** with toggleable active arm
- **5 progressive rehabilitation stages** from single-axis to full 3D bilateral control
- Live EEG connection status, countdown timer, and score in a compact **in-session HUD**
- **Debug mode** for testing without EEG hardware

---

## 🛠️ Technologies Used

- **Swift / SwiftUI**
- **RealityKit** — 3D entity rendering and collision detection
- **visionOS 2.0** — ImmersiveSpace and mixed-reality passthrough
- **WebSocket** — Live EEG signal streaming from BCI backend
- **Python** — EEG backend signal processing scripts

---

## 📲 Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/cansoup/VisionStudio_team5.git
   ```
2. Open `Neurospace-Team5.xcodeproj` in **Xcode 16** or later.
3. Select the **visionOS Simulator** target (or a connected Apple Vision Pro).
4. Build and run (`Cmd+R`).

> **Note:** Live BCI input requires a running EEG WebSocket backend. Use the lobby's debug intent buttons to simulate signals without hardware.

---

## 📖 Usage

1. Launch the app and check EEG connection status in the **Lobby**.
2. Select the active arm and optionally test intents using the debug buttons.
3. Press **Start Session** to enter the immersive space.
4. Use BCI signals (or debug buttons) to move the arm pointer and pop bubbles.
5. Session ends when all bubbles are popped, time runs out, or you stop manually.

---

## 🏥 Rehabilitation Stages

| Stage | Name | Axes | Bubbles | Duration | Unlock |
|---|---|---|---|---|---|
| 1 | Signal Discovery | X | 3 large | 3 min | ≥70% · all 3 popped |
| 2 | Spatial Mapping | X + Y | 6 medium | 2 min 30 s | ≥70% · all 6 popped |
| 3 | Depth Perception | X + Y + Z | 8 standard | 2 min | ≥75% · ≥6 popped |
| 4 | Bilateral Coordination | X + Y + Z | 10 colour-coded | 2 min | ≥80% · ≥8 popped |
| 5 | Dynamic Flow | X + Y + Z | Continuous respawn | 2 min | Timer only |

---

## 🔮 Future Development

- Clinician dashboard for tracking per-stage accuracy, latency, and session history
- Rest screens between stages to manage mental fatigue
- Expanded BCI intent vocabulary for higher degrees of freedom
- Persistent user profiles and session logging
- Support for additional BCI hardware backends

---

## 📄 Requirements

- Apple Vision Pro or visionOS Simulator
- Xcode 16+
- visionOS 2.0+
- EEG BCI backend (WebSocket) — debug mode available without hardware

---

## 🙌 Credits

Built by **vOS Team 5**
