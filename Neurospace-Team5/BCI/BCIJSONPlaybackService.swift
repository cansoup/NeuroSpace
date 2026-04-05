//
//  BCIJSONPlaybackService.swift
//  Neurospace-Team5
//
//  Created by Shaiyan Haseen Khan on 5/4/2026.
//
import Foundation

@MainActor
final class BCIJSONPlaybackService {

    private let controller: BubbleGameController
    private var timer: Timer?
    private var messages: [BCIControlMessage] = []
    private var currentIndex: Int = 0
    private let confidenceThreshold: Float = 0.6

    init(controller: BubbleGameController) {
        self.controller = controller
    }

    func loadJSON(named resourceName: String) {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json") else {
            print("Could not find \(resourceName).json in app bundle")
            messages = []
            return
        }

        do {
            let data = try Data(contentsOf: url)
            messages = try JSONDecoder().decode([BCIControlMessage].self, from: data)
            currentIndex = 0
            print("Loaded \(messages.count) BCI messages")
        } catch {
            print("Failed to decode JSON: \(error)")
            messages = []
        }
    }

    func startPlayback(interval: TimeInterval = 0.1) {
        stopPlayback()

        if messages.isEmpty {
            loadJSON(named: "bci_test_data")
        }

        guard !messages.isEmpty else { return }

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.playNext()
        }
    }

    func stopPlayback() {
        timer?.invalidate()
        timer = nil
        controller.stopMotion()
    }

    private func playNext() {
        guard !messages.isEmpty else { return }

        if currentIndex >= messages.count {
            currentIndex = 0
        }

        let message = messages[currentIndex]
        currentIndex += 1

        if message.confidence < confidenceThreshold {
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
