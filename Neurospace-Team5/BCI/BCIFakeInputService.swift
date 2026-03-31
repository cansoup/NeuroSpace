//
//  BCIFakeInputService.swift
//  Neurospace-Team5
//
//  Created by Shaiyan Haseen Khan on 31/3/2026.
//

import Foundation

@MainActor
final class FakeBCIInputService {

    private let mapper: BCIArmMapper
    private var timer: Timer?
    private var step: Int = 0

    init(mapper: BCIArmMapper) {
        self.mapper = mapper
    }

    func start() {
        stop()

        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.sendNextFakeMessage()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sendNextFakeMessage() {
        let messages: [BCIControlMessage] = [
            BCIControlMessage(activeArm: .left,  moveX: -0.8, moveY:  0.0, moveZ:  0.0, confidence: 0.90, timestamp: Date().timeIntervalSince1970),
            BCIControlMessage(activeArm: .left,  moveX:  0.0, moveY:  0.7, moveZ:  0.0, confidence: 0.88, timestamp: Date().timeIntervalSince1970),
            BCIControlMessage(activeArm: .left,  moveX:  0.0, moveY:  0.0, moveZ: -0.7, confidence: 0.92, timestamp: Date().timeIntervalSince1970),

            BCIControlMessage(activeArm: .right, moveX:  0.8, moveY:  0.0, moveZ:  0.0, confidence: 0.91, timestamp: Date().timeIntervalSince1970),
            BCIControlMessage(activeArm: .right, moveX:  0.0, moveY: -0.6, moveZ:  0.0, confidence: 0.87, timestamp: Date().timeIntervalSince1970),
            BCIControlMessage(activeArm: .right, moveX:  0.0, moveY:  0.0, moveZ:  0.6, confidence: 0.89, timestamp: Date().timeIntervalSince1970),

            BCIControlMessage(activeArm: .right, moveX:  0.0, moveY:  0.0, moveZ:  0.0, confidence: 0.95, timestamp: Date().timeIntervalSince1970)
        ]

        let message = messages[step % messages.count]
        mapper.handleControlMessage(message)
        step += 1
    }
}
