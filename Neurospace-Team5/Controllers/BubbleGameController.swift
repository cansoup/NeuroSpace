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

    private var velocityX: Float = 0.0
    private var targetDirection: Float = 0.0

    private let maxSpeed: Float = 0.6
    private let acceleration: Float = 1.5
    private let deceleration: Float = 2.0
    private let xLimit: Float = 0.4

    init() {
        resetGame()
    }

    func resetGame() {
        currentIntent = .idle
        sessionState = .ready
        score = 0

        velocityX = 0.0
        targetDirection = 0.0

        armState = ArmState(
            pointerPosition: [0.0, 0.0, 0.0],
            armBasePosition: [0.0, -0.08, 0.0],
            isPopTriggered: false
        )

        bubbles = [
            Bubble(position: [-0.25, 0.0, 0.0]),
            Bubble(position: [ 0.25, 0.0, 0.0]),
            Bubble(position: [-0.10, 0.0, 0.0]),
            Bubble(position: [ 0.10, 0.0, 0.0])
        ]
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
        guard sessionState == .playing || sessionState == .ready else { return }

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
