# Neurospace — BCI Bubble Pop

A visionOS game designed for upper-limb amputees, enabling gameplay through Brain-Computer Interface (BCI) signals decoded from EEG data. Players control a virtual arm pointer using their motor imagery to navigate and pop 3D bubbles in mixed-reality space.

---

## Overview

Neurospace translates EEG-based BCI signals into spatial movement, allowing users without full limb function to interact with a 3D AR environment on Apple Vision Pro. The game provides an engaging rehabilitation and training context where players move a pointer through thought-driven intent to pop bubbles rendered in their physical space.

---

## Features

- **BCI-driven control** — Arm pointer movement is driven by decoded EEG intent signals (left, right, up, down, forward, backward) received via WebSocket from a backend BCI pipeline
- **Mixed-reality immersive space** — Bubbles and arm entities are rendered as 3D RealityKit objects overlaid on the real world (passthrough AR)
- **Dual arm support** — Left and right arm models are both rendered; the active arm (used for gameplay) can be toggled
- **Auto-pop collision** — When the active arm tip comes within range of a bubble, the bubble pops and score increases
- **Randomized bubble placement** — Each session spawns bubbles at random non-overlapping positions to keep gameplay varied
- **2-minute countdown timer** — Each session runs for 120 seconds; the timer counts down in real time and turns red in the final 30 seconds
- **Session end conditions** — Session ends when all bubbles are popped or the timer reaches zero
- **Compact in-session HUD** — A minimal floating control panel shows EEG connection status, remaining time, and current score; includes a stop button with an end-session confirmation prompt
- **Lobby with debug controls** — Pre-session screen shows connection and session status, active arm selector, manual intent debug buttons, and the Start Session button

---

## Architecture

```
Neurospace-Team5/
├── App/
│   ├── Neurospace_Team5App.swift   # App entry point, WindowGroup + ImmersiveSpace setup
│   └── AppModel.swift              # Shared observable state (immersive space state, game controller)
├── BCI/
│   ├── BCIService.swift            # BCI signal processing service
│   ├── IntentManager.swift         # Maps decoded signals to BCIIntent
│   └── WebSocketManager.swift      # WebSocket connection to EEG backend
├── BubbleGame/
│   ├── BubbleManager.swift         # Bubble lifecycle management
│   ├── CollisionManager.swift      # Collision detection logic
│   └── ScoreManager.swift          # Score tracking
├── Controllers/
│   └── BubbleGameController.swift  # Central game controller (state, timer, movement, collision)
├── Immersive/
│   └── ImmersiveView.swift         # RealityKit scene: arm entities, bubbles, head anchor
├── Models/
│   ├── ArmState.swift              # Arm position, velocity, and pop state
│   ├── BCIIntent.swift             # Enum of possible BCI intents
│   ├── Bubble.swift                # Bubble model (position, popped state)
│   ├── ConnectionState.swift       # EEG connection state enum
│   ├── EEGCommandMessage.swift     # WebSocket message model
│   └── SessionState.swift          # Game session state enum
└── UI/
    ├── ContentView.swift           # Root view, lobby screen with debug controls
    └── GameView.swift              # In-session compact HUD (timer, score, stop button)
```

---

## How It Works

1. **Lobby** — The user sees connection status, session info, and debug controls. They can manually trigger intents for testing or select the active arm.
2. **Start Session** — Tapping "Start Session" opens the mixed-reality immersive space and begins the 2-minute countdown. The lobby window is dismissed.
3. **Gameplay** — 3D bubbles appear in front of the user anchored relative to head position. BCI signals move the arm pointer. When the pointer tip touches a bubble, it pops and adds 100 points.
4. **In-session HUD** — A compact panel floats in the upper-right of the immersive view, showing EEG status, countdown timer, and score.
5. **Session End** — When all bubbles are popped or time runs out, the session ends. The user can also stop early via the X button → confirmation prompt.

---

## BCI Intent Mapping

| Intent | Movement |
|---|---|
| `moveLeft` | Pointer moves left |
| `moveRight` | Pointer moves right |
| `moveUp` | Pointer moves up |
| `moveDown` | Pointer moves down |
| `moveForward` | Pointer moves forward (toward scene) |
| `moveBackward` | Pointer moves backward |
| `pop` | Triggers pop action |
| `idle` | No movement |

---

## Requirements

- Apple Vision Pro or visionOS Simulator
- Xcode 16+
- visionOS 2.0+
- EEG BCI backend (WebSocket server) for live signal input — debug mode available without hardware

---

## Running in Simulator

1. Open `Neurospace-Team5.xcodeproj` in Xcode
2. Select the **visionOS Simulator** target
3. Build and run (`Cmd+R`)
4. Use the debug intent buttons in the lobby to simulate BCI signals
5. Press **Start Session** to enter the immersive space and begin gameplay

> **Note:** In the simulator, spatial input (gaze + pinch) replaces physical interaction. Use the simulator's input controls to interact with UI elements.

---

## Team

**Team 5 — VisionStudio**
