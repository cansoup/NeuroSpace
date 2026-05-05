//
//  BCIArmMapper.swift
//  Neurospace-Team5
//
//  Created by Shaiyan Haseen Khan on 31/3/2026.
//
import Foundation
import simd

@MainActor
final class BCIArmMapper {

    private let controller: BubbleGameController
    private let confidenceThreshold: Float = 0.55

    init(controller: BubbleGameController) {
        self.controller = controller
    }

    func handleControlMessage(_ message: BCIControlMessage) {
        guard message.confidence >= confidenceThreshold else {
            controller.stopMotion()
            return
        }

        controller.setActiveArm(message.activeArm)
        controller.applyControlVector(
            x: message.moveX,
            y: message.moveY,
            z: message.moveZ
        )
    }
}
