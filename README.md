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

## Rehabilitation Stage Design

Neurospace structures gameplay into five progressive stages grounded in motor imagery rehabilitation for upper-limb amputees. The core mechanism is **Motor Imagery (MI)**: repeatedly imagining a limb movement preserves cortical representation, improves EEG signal quality, and builds the neural foundation for future BCI-controlled prosthetic use.

### Design Principles

- **Simple → Complex**: single axis → 2D plane → full 3D
- **Unilateral → Bilateral**: one active arm → hemispheric switching
- **Static → Dynamic**: fixed targets → moving, time-limited targets
- **Scaffolded progression**: each stage unlocks only when performance criteria are met

---

### Stage 1 — Signal Discovery

| Parameter | Value |
|---|---|
| Axes | X only (left / right) |
| Bubbles | 3 × large (radius 0.12 m) |
| Arm mode | Single active |
| Duration | 3 min |
| Unlock | ≥ 70% accuracy & all 3 popped |

Large targets and restricted movement minimise frustration during the first BCI interaction. The patient discovers which mental strategy (pushing, rotating, squeezing imagery) produces the strongest and most consistent EEG signal.

**Clinical rationale:** Establishes the patient's individual signal profile. Success on the first contact builds neurological confidence and lays the foundation for cortical map preservation.

---

### Stage 2 — Spatial Mapping

| Parameter | Value |
|---|---|
| Axes | X + Y (left / right + up / down) |
| Bubbles | 6 × medium (radius 0.09 m) |
| Arm mode | Single active |
| Duration | 2 min 30 s |
| Unlock | ≥ 70% accuracy & all 6 popped |

Bubbles are arranged in a grid-like pattern in the frontal plane, providing clear spatial scaffolding. The vertical axis engages a distinct cortical region from the horizontal axis, broadening the motor imagery vocabulary.

**Clinical rationale:** Expanding to 2-D builds a richer set of decodable EEG patterns, directly increasing the degrees of freedom available for future prosthetic control.

---

### Stage 3 — Depth Perception

| Parameter | Value |
|---|---|
| Axes | X + Y + Z (full 3-D) |
| Bubbles | 8 × standard (radius 0.06 m) |
| Arm mode | Single active |
| Duration | 2 min |
| Unlock | ≥ 75% accuracy & ≥ 6 popped |

Bubbles are placed at varying depths, requiring combined intent (e.g. right + forward simultaneously). This mirrors the spatial complexity of real reach-and-grasp scenarios used in ADL (activities of daily living).

**Clinical rationale:** Full 3-D spatial navigation demands predictive motor planning — a higher cognitive-motor integration skill that directly predicts prosthetic usability in daily life.

---

### Stage 4 — Bilateral Coordination

| Parameter | Value |
|---|---|
| Axes | Full 3-D |
| Bubbles | 10 (5 cyan = left arm, 5 orange = right arm) |
| Arm mode | Bilateral (colour-coded assignment) |
| Duration | 2 min |
| Unlock | ≥ 80% accuracy & ≥ 8 popped |

Each bubble is colour-coded to a specific arm. The player must switch the active arm by BCI intent to match the target. Popping with the wrong arm yields no score.

**Clinical rationale:** Most ADL require bimanual coordination. Rapidly alternating between left and right motor imagery trains interhemispheric inhibition circuits — the neural basis of two-handed prosthetic use.

---

### Stage 5 — Dynamic Flow

| Parameter | Value |
|---|---|
| Axes | Full 3-D |
| Bubbles | Continuous respawn batches (radius 0.06 m) |
| Arm mode | Bilateral |
| Duration | 2 min |
| Bubble lifetime | 12 s (expires without scoring) |
| Speed | 0.02 – 0.05 m/s (random drift) |

Bubbles drift slowly and disappear if not popped in time. The session ends only when the timer reaches zero, with continuous respawning. This stage exercises **predictive motor planning** — moving targets cannot be handled by purely reactive control.

**Clinical rationale:** Real-world motor tasks are never static. This stage is the closest simulation of functional prosthetic use: dynamic targets, time pressure, bilateral arm switching, and full 3-D navigation — all simultaneously.

---

### Progression Criteria Summary

| Stage | Unlock condition |
|---|---|
| 1 → 2 | ≥ 70% accuracy · all 3 bubbles popped |
| 2 → 3 | ≥ 70% accuracy · all 6 bubbles popped |
| 3 → 4 | ≥ 75% accuracy · ≥ 6 bubbles popped |
| 4 → 5 | ≥ 80% accuracy · ≥ 8 bubbles popped |
| 5 | Final stage — session ends by timer |

### Additional Clinical Considerations

- **Mental fatigue**: BCI motor imagery causes significant cognitive load; signal quality degrades after 10–15 min. Rest screens between stages are recommended.
- **Phantom limb pain relief**: The combination of motor imagery and real-time visual feedback activates mirror neuron circuits, which may reduce phantom limb pain — a documented side-benefit of AR-based MI training.
- **Therapist monitoring**: Per-stage accuracy, response latency, and session scores should be logged and surfaced in a clinician dashboard for progress tracking.

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
