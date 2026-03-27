//
//  BubbleGameController.swift
//  Neurospace-Team5
//
//  Created by Shaiyan Haseen Khan on 26/3/2026.
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
    var armState: ArmState = ArmState()
    var bubbles: [Bubble] = []
    var score: Int = 0

    // UI state
    var currentStage: Int = 1
    var targetBubbleColor: String = "Pink"
    var accuracy: Double = 0.0
    private var hitCount: Int = 0
    private var attemptCount: Int = 0

    // Timer — driven by an independent async Task, not the render loop
    static let stageDuration: Int = 120
    var remainingSeconds: Int = stageDuration
    private var timerTask: Task<Void, Never>? = nil

    private var velocityX: Float = 0.0
    private var targetDirection: Float = 0.0

    private let maxSpeed: Float = 0.6
    private let acceleration: Float = 1.5
    private let deceleration: Float = 2.0
    private let xLimit: Float = 0.4

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
        score = 0
        remainingSeconds = BubbleGameController.stageDuration
        hitCount = 0
        attemptCount = 0
        accuracy = 0.0

        velocityX = 0.0
        targetDirection = 0.0

        armState = ArmState(
            pointerPosition: [0.0, 0.0, 0.0],
            armBasePosition: [0.0, -0.08, 0.0],
            isPopTriggered: false
        )

        bubbles = Self.generateRandomBubbles(count: 4)
    }

    func setConnectionState(_ state: ConnectionState) {
        connectionState = state
    }

    func applyIntent(_ intent: BCIIntent) {
        currentIntent = intent

        switch intent {
        case .moveLeft:
            targetDirection = -1.0
        case .moveRight:
            targetDirection = 1.0
        case .idle:
            targetDirection = 0.0
        case .moveForward, .moveBackward, .pop:
            break
        }
    }

    func update(deltaTime: Float) {
        guard sessionState == .playing else { return }

        let targetVelocity = targetDirection * maxSpeed

        if targetDirection != 0 {
            velocityX += (targetVelocity - velocityX) * min(acceleration * deltaTime, 1.0)
        } else {
            velocityX += (0.0 - velocityX) * min(deceleration * deltaTime, 1.0)
        }

        var newX = armState.pointerPosition.x + velocityX * deltaTime
        newX = max(-xLimit, min(xLimit, newX))

        armState.pointerPosition.x = newX
        armState.armBasePosition = [
            newX * 0.5,
            -0.08,
            0.0
        ]

        autoPopIfTouching()
        updateSessionIfFinished()
    }

    private static func generateRandomBubbles(count: Int) -> [Bubble] {
        let xRange: ClosedRange<Float> = -0.35...0.35
        let yRange: ClosedRange<Float> = -0.25...0.25
        let minDistance: Float = 0.18
        // Keep bubbles away from the pointer's initial position (x=0)
        // to prevent instant pops at session start
        let safeDistanceFromOrigin: Float = 0.12

        var positions: [SIMD3<Float>] = []
        var attempts = 0

        while positions.count < count && attempts < 200 {
            attempts += 1
            let candidate = SIMD3<Float>(
                Float.random(in: xRange),
                Float.random(in: yRange),
                0.0
            )
            let tooCloseToOrigin = abs(candidate.x) < safeDistanceFromOrigin
            let tooCloseToOther = positions.contains {
                distance($0, candidate) < minDistance
            }
            if !tooCloseToOrigin && !tooCloseToOther {
                positions.append(candidate)
            }
        }

        return positions.map { Bubble(position: $0) }
    }

    private func autoPopIfTouching() {
        for i in bubbles.indices {
            if bubbles[i].isPopped { continue }

            let distance = abs(bubbles[i].position.x - armState.pointerPosition.x)
            attemptCount += 1
            if distance < 0.08 {
                bubbles[i].isPopped = true
                score += 100
                hitCount += 1
            }
            if attemptCount > 0 {
                accuracy = Double(hitCount) / Double(attemptCount)
            }
        }
    }

    private func updateSessionIfFinished() {
        let allPopped = bubbles.allSatisfy(\.isPopped)
        if allPopped {
            sessionState = .finished
        }
    }
}
