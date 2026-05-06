//
//  StageConfig.swift
//  NeuroSpace
//
//  Defines the parameters and unlock criteria for each rehabilitation stage.
//

import Foundation

struct StageConfig {

    // MARK: - Axis restriction

    struct AxisSet: OptionSet {
        let rawValue: Int
        static let x    = AxisSet(rawValue: 1 << 0)   // moveLeft / moveRight
        static let y    = AxisSet(rawValue: 1 << 1)   // moveUp   / moveDown
        static let z    = AxisSet(rawValue: 1 << 2)   // moveForward / moveBackward
        static let xy:  AxisSet = [.x, .y]
        static let xyz: AxisSet = [.x, .y, .z]
    }

    // MARK: - Arm mode

    enum ArmMode: Equatable {
        case singleActive   // whichever arm is currently selected by the player
        case bilateral      // each bubble is assigned to a specific arm
    }

    // MARK: - Unlock criteria

    struct UnlockCriteria {
        let minimumAccuracy: Double   // 0.0 – 1.0
        let requiredPops:    Int
    }

    // MARK: - Properties

    let number:          Int
    let title:           String
    let description:     String
    let duration:        Int                   // seconds per session
    let bubbleCount:     Int
    let bubbleRadius:    Float
    let allowedAxes:     AxisSet
    let armMode:         ArmMode
    let bubbleSpeed:     ClosedRange<Float>    // 0...0 for static bubbles
    let bubbleLifetime:  Double?               // nil = lives until explicitly popped
    let respawnsEnabled: Bool                  // continuously respawn after all gone

    let unlockCriteria:  UnlockCriteria

    // MARK: - Helpers

    var isBilateral: Bool { armMode == .bilateral }

    /// Returns whether a BCI intent is permitted in this stage.
    func isIntentAllowed(_ intent: BCIIntent) -> Bool {
        switch intent {
        case .moveLeft,     .moveRight:    return allowedAxes.contains(.x)
        case .moveUp,       .moveDown:     return allowedAxes.contains(.y)
        case .moveForward,  .moveBackward: return allowedAxes.contains(.z)
        case .idle,         .pop:          return true
        }
    }
}

// MARK: - Stage catalogue

extension StageConfig {

    static let allStages: [StageConfig] = [

        // ── Stage 1 · Signal Discovery ──────────────────────────────────────
        // Establish reliable EEG signals on a single lateral axis.
        // Large targets and slow arm speed minimise frustration on first contact.
        StageConfig(
            number: 1,
            title: "Signal Discovery",
            description: "Learn to generate reliable EEG signals using lateral motor imagery on a single axis.",
            duration: 180,
            bubbleCount: 3,
            bubbleRadius: 0.12,
            allowedAxes: .x,
            armMode: .singleActive,
            bubbleSpeed: 0...0,
            bubbleLifetime: nil,
            respawnsEnabled: false,
            unlockCriteria: UnlockCriteria(minimumAccuracy: 0.70, requiredPops: 3)
        ),

        // ── Stage 2 · Spatial Mapping ────────────────────────────────────────
        // Expand the motor imagery vocabulary to vertical + horizontal axes.
        // Grid-like placement provides clear spatial scaffolding.
        StageConfig(
            number: 2,
            title: "Spatial Mapping",
            description: "Expand motor imagery to vertical and horizontal axes in a structured 2D plane.",
            duration: 150,
            bubbleCount: 6,
            bubbleRadius: 0.09,
            allowedAxes: .xy,
            armMode: .singleActive,
            bubbleSpeed: 0...0,
            bubbleLifetime: nil,
            respawnsEnabled: false,
            unlockCriteria: UnlockCriteria(minimumAccuracy: 0.70, requiredPops: 6)
        ),

        // ── Stage 3 · Depth Perception ────────────────────────────────────────
        // Full 3-D spatial navigation requiring combined intent (e.g. right+forward).
        // Mirrors real prosthetic reach-and-grasp scenarios.
        StageConfig(
            number: 3,
            title: "Depth Perception",
            description: "Navigate full 3D space including depth, requiring combined directional intent.",
            duration: 120,
            bubbleCount: 8,
            bubbleRadius: 0.06,
            allowedAxes: .xyz,
            armMode: .singleActive,
            bubbleSpeed: 0...0,
            bubbleLifetime: nil,
            respawnsEnabled: false,
            unlockCriteria: UnlockCriteria(minimumAccuracy: 0.75, requiredPops: 6)
        ),

        // ── Stage 4 · Bilateral Coordination ─────────────────────────────────
        // Each bubble is colour-coded to a specific arm.
        // Trains rapid hemispheric switching — the neural basis of bimanual ADL.
        StageConfig(
            number: 4,
            title: "Bilateral Coordination",
            description: "Switch between left and right arm motor imagery. Each bubble is assigned to a specific arm.",
            duration: 120,
            bubbleCount: 10,
            bubbleRadius: 0.06,
            allowedAxes: .xyz,
            armMode: .bilateral,
            bubbleSpeed: 0...0,
            bubbleLifetime: nil,
            respawnsEnabled: false,
            unlockCriteria: UnlockCriteria(minimumAccuracy: 0.80, requiredPops: 8)
        ),

        // ── Stage 5 · Dynamic Flow ────────────────────────────────────────────
        // Moving targets with a finite lifetime demand predictive motor planning —
        // the closest simulation of real-world prosthetic use.
        StageConfig(
            number: 5,
            title: "Dynamic Flow",
            description: "Pop moving targets before they disappear. Both arms, full 3D, under time pressure.",
            duration: 120,
            bubbleCount: 6,
            bubbleRadius: 0.06,
            allowedAxes: .xyz,
            armMode: .bilateral,
            bubbleSpeed: 0.02...0.05,
            bubbleLifetime: 12.0,
            respawnsEnabled: true,
            unlockCriteria: UnlockCriteria(minimumAccuracy: 0.0, requiredPops: 0)  // final stage
        )
    ]

    /// Returns the config for a given stage number (1-based, clamped to valid range).
    static func config(for stage: Int) -> StageConfig {
        let index = max(0, min(stage - 1, allStages.count - 1))
        return allStages[index]
    }

    static var totalStages: Int { allStages.count }
}
