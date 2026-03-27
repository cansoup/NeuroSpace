//
//  BubbleGameController.swift
//  Neurospace-Team5
//
//  Created by Shaiyan Haseen Khan on 26/3/2026.
//

//
//  BubbleGameController.swift
//  Neurospace-Team5
//

//
//  BubbleGameController.swift
//  Neurospace-Team5
//

import Foundation
import Observation
import simd

@MainActor
@Observable
final class BubbleGameController {

    var currentIntent: BCIIntent = .idle
    var connectionState: ConnectionState = .disconnected
    var sessionState: SessionState = .idle

    var activeArm: ActiveArm = .right
    var leftArmState: ArmState = ArmState()
    var rightArmState: ArmState = ArmState()

    var bubbles: [Bubble] = []
    var score: Int = 0

    var currentStage: Int = 1
    var targetBubbleColor: String = "Pink"
    var accuracy: Double = 0.0
    private var hitCount: Int = 0
    private var attemptCount: Int = 0

    static let stageDuration: Int = 120
    var remainingSeconds: Int = stageDuration
    private var timerTask: Task<Void, Never>? = nil

    private var targetDirection: SIMD3<Float> = .zero

    // Tuned to feel less floaty
    private let maxSpeed: Float = 0.48
    private let acceleration: Float = 6.5
    private let deceleration: Float = 8.0

    private let xLimit: ClosedRange<Float> = -0.38 ... 0.38
    private let yLimit: ClosedRange<Float> = -0.10 ... 0.24
    private let zLimit: ClosedRange<Float> = -0.22 ... 0.22

    init() {
        resetGame()
    }

    func startSession() {
        sessionState = .playing
        remainingSeconds = BubbleGameController.stageDuration
        timerTask?.cancel()

        let start = Date()
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, self.sessionState == .playing else { break }

                let elapsed = Int(Date().timeIntervalSince(start))
                self.remainingSeconds = max(0, BubbleGameController.stageDuration - elapsed)

                if self.remainingSeconds == 0 {
                    self.sessionState = .finished
                    break
                }
            }
        }
    }

    func resetGame() {
        timerTask?.cancel()
        timerTask = nil

        currentIntent = .idle
        sessionState = .ready
        activeArm = .right
        score = 0
        remainingSeconds = BubbleGameController.stageDuration

        hitCount = 0
        attemptCount = 0
        accuracy = 0.0

        targetDirection = .zero

        leftArmState = ArmState(
            basePosition: [-0.22, -0.14, 0.08],
            tipPosition: [-0.16, 0.02, 0.00],
            velocity: .zero,
            isPopTriggered: false
        )

        rightArmState = ArmState(
            basePosition: [0.22, -0.14, 0.08],
            tipPosition: [0.16, 0.02, 0.00],
            velocity: .zero,
            isPopTriggered: false
        )

        bubbles = Self.generateRandomBubbles(count: 4)
    }

    func setConnectionState(_ state: ConnectionState) {
        connectionState = state
    }

    func setActiveArm(_ arm: ActiveArm) {
        activeArm = arm
        targetDirection = .zero
        currentIntent = .idle

        // stop previous active arm cleanly
        leftArmState.velocity = .zero
        rightArmState.velocity = .zero
    }

    func applyIntent(_ intent: BCIIntent) {
        currentIntent = intent
        currentArmState.isPopTriggered = false

        switch intent {
        case .moveLeft:
            targetDirection = [-1.0, 0.0, 0.0]
        case .moveRight:
            targetDirection = [1.0, 0.0, 0.0]
        case .moveUp:
            targetDirection = [0.0, 1.0, 0.0]
        case .moveDown:
            targetDirection = [0.0, -1.0, 0.0]
        case .moveForward:
            targetDirection = [0.0, 0.0, -1.0]
        case .moveBackward:
            targetDirection = [0.0, 0.0, 1.0]
        case .idle:
            targetDirection = .zero
        case .pop:
            currentArmState.isPopTriggered = true
            attemptCount += 1
        }
    }

    func applyControlVector(x: Float, y: Float, z: Float) {
        let clamped = SIMD3<Float>(
            max(-1.0, min(1.0, x)),
            max(-1.0, min(1.0, y)),
            max(-1.0, min(1.0, z))
        )

        currentIntent = .idle
        targetDirection = clamped
    }

    func stopMotion() {
        currentIntent = .idle
        targetDirection = .zero
    }

    func update(deltaTime: Float) {
        guard sessionState == .playing || sessionState == .ready else { return }

        let moving = simd_length(targetDirection) > 0.0001
        let speedFactor: Float = moving ? acceleration : deceleration
        let targetVelocity = targetDirection * maxSpeed

        currentArmState.velocity +=
            (targetVelocity - currentArmState.velocity) * min(speedFactor * deltaTime, 1.0)

        // snap very small values to zero so stopping feels clean
        if simd_length(currentArmState.velocity) < 0.001 {
            currentArmState.velocity = .zero
        }

        var newTip = currentArmState.tipPosition + currentArmState.velocity * deltaTime

        newTip.x = min(max(newTip.x, xLimit.lowerBound), xLimit.upperBound)
        newTip.y = min(max(newTip.y, yLimit.lowerBound), yLimit.upperBound)
        newTip.z = min(max(newTip.z, zLimit.lowerBound), zLimit.upperBound)

        currentArmState.tipPosition = newTip

        if sessionState == .playing {
            autoPopIfTouching()
            updateSessionIfFinished()
        }
    }

    var leftTipText: String {
        formatted(leftArmState.tipPosition)
    }

    var rightTipText: String {
        formatted(rightArmState.tipPosition)
    }

    var motionVectorText: String {
        formatted(targetDirection)
    }

    private func formatted(_ v: SIMD3<Float>) -> String {
        String(format: "(%.2f, %.2f, %.2f)", v.x, v.y, v.z)
    }

    private var currentArmState: ArmState {
        get { activeArm == .left ? leftArmState : rightArmState }
        set {
            if activeArm == .left {
                leftArmState = newValue
            } else {
                rightArmState = newValue
            }
        }
    }

    private static func generateRandomBubbles(count: Int) -> [Bubble] {
        let xRange: ClosedRange<Float> = -0.32 ... 0.32
        let yRange: ClosedRange<Float> = -0.02 ... 0.18
        let zRange: ClosedRange<Float> = -0.14 ... 0.12
        let minDistance: Float = 0.18

        var positions: [SIMD3<Float>] = []
        var tries = 0

        while positions.count < count && tries < 300 {
            tries += 1

            let candidate = SIMD3<Float>(
                Float.random(in: xRange),
                Float.random(in: yRange),
                Float.random(in: zRange)
            )

            let overlaps = positions.contains { simd_distance($0, candidate) < minDistance }
            if !overlaps {
                positions.append(candidate)
            }
        }

        return positions.map { Bubble(position: $0) }
    }

    private func autoPopIfTouching() {
        for i in bubbles.indices {
            if bubbles[i].isPopped { continue }

            let distance = simd_distance(bubbles[i].position, currentArmState.tipPosition)
            if distance < 0.085 {
                bubbles[i].isPopped = true
                score += 100
                hitCount += 1
            }
        }

        if attemptCount > 0 {
            accuracy = Double(hitCount) / Double(attemptCount)
        }
    }

    private func updateSessionIfFinished() {
        if bubbles.allSatisfy(\.isPopped) {
            sessionState = .finished
        }
    }
}
