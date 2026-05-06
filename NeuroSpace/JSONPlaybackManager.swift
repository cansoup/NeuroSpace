//
//  JSONPlaybackManager.swift
//  NeuroSpace
//

import Foundation
import Observation

@MainActor
@Observable
final class JSONPlaybackManager {

    struct PredictionMessage: Codable {
        let type: String
        let timestamp: Double
        let session_id: String
        let predicted_class: String
        let predicted_index: Int
        let confidence: Double
        let probabilities: [String: Double]
        let processing_time_ms: Double
        let above_threshold: Bool
    }

    private let controller: BubbleGameController
    private let minimumConfidence: Double = 0.75

    private var playbackTask: Task<Void, Never>?

    var messages: [PredictionMessage] = []
    var isPlaying = false
    var currentIndex = 0

    var statusText: String = "JSON not loaded"

    var loadedCountText: String {
        "\(messages.count) messages"
    }

    init(controller: BubbleGameController) {
        self.controller = controller
    }

    func loadJSON(named fileName: String) {
        statusText = "Load pressed..."
        print("[JSON] Load button pressed for \(fileName).json")

        if let url = Bundle.main.url(forResource: fileName, withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                messages = try JSONDecoder().decode([PredictionMessage].self, from: data)
                currentIndex = 0

                statusText = "Loaded \(messages.count) messages"
                print("[JSON] \(statusText)")
                return
            } catch {
                messages = []
                statusText = "Decode failed: \(error.localizedDescription)"
                print("[JSON] \(statusText)")
                return
            }
        }

        messages = Self.fallbackMessages()
        currentIndex = 0

        statusText = "Loaded fallback JSON: \(messages.count)"
        print("[JSON] Could not find \(fileName).json in bundle")
        print("[JSON] \(statusText)")
    }

    func startPlayback(interval: Double = 0.35) {
        if messages.isEmpty {
            loadJSON(named: "bci_test_data")
        }

        guard !messages.isEmpty else {
            statusText = "No JSON messages available"
            print("[JSON] \(statusText)")
            return
        }

        stopPlayback(resetMotionOnly: true)

        isPlaying = true
        currentIndex = 0
        statusText = "Playback started"

        print("[JSON] \(statusText)")

        playbackTask = Task { @MainActor in
            while !Task.isCancelled && isPlaying {
                if currentIndex >= messages.count {
                    currentIndex = 0
                }

                let message = messages[currentIndex]
                print("[JSON] Playing index \(currentIndex): \(message.predicted_class)")

                route(prediction: message)

                currentIndex += 1

                let delay = UInt64(interval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    func stopPlayback(resetMotionOnly: Bool = false) {
        playbackTask?.cancel()
        playbackTask = nil

        isPlaying = false
        controller.stopMotion()

        if !resetMotionOnly {
            statusText = "Playback stopped"
            print("[JSON] \(statusText)")
        }
    }

    private func route(prediction: PredictionMessage) {
        guard prediction.type == "prediction" else {
            statusText = "Ignored invalid message"
            print("[JSON] Ignored invalid message type: \(prediction.type)")
            return
        }

        guard controller.sessionState == .playing else {
            statusText = "Waiting: start game first"
            print("[JSON] Ignoring prediction because session is \(controller.sessionState.rawValue)")
            return
        }

        guard prediction.above_threshold else {
            statusText = "Ignored \(prediction.predicted_class): below threshold"
            print("[JSON] \(statusText)")
            controller.stopMotion()
            return
        }

        guard prediction.confidence >= minimumConfidence else {
            statusText = "Ignored \(prediction.predicted_class): low confidence"
            print("[JSON] \(statusText)")
            controller.stopMotion()
            return
        }

        switch prediction.predicted_class.lowercased() {
        case "left":
            statusText = "JSON: LEFT arm"
            print("[JSON] \(statusText)")
            controller.applyPredictionClass(.left)

        case "right":
            statusText = "JSON: RIGHT arm"
            print("[JSON] \(statusText)")
            controller.applyPredictionClass(.right)

        case "both":
            statusText = "JSON: BOTH arms"
            print("[JSON] \(statusText)")
            controller.applyPredictionClass(.both)

        default:
            statusText = "Unknown class: \(prediction.predicted_class)"
            print("[JSON] \(statusText)")
            controller.stopMotion()
        }
    }

    private static func fallbackMessages() -> [PredictionMessage] {
        [
            PredictionMessage(
                type: "prediction",
                timestamp: 1745611234.567,
                session_id: "fallback_session",
                predicted_class: "right",
                predicted_index: 1,
                confidence: 0.95,
                probabilities: [
                    "left": 0.02,
                    "right": 0.95,
                    "both": 0.03
                ],
                processing_time_ms: 12.4,
                above_threshold: true
            ),
            PredictionMessage(
                type: "prediction",
                timestamp: 1745611235.567,
                session_id: "fallback_session",
                predicted_class: "right",
                predicted_index: 1,
                confidence: 0.94,
                probabilities: [
                    "left": 0.03,
                    "right": 0.94,
                    "both": 0.03
                ],
                processing_time_ms: 12.1,
                above_threshold: true
            ),
            PredictionMessage(
                type: "prediction",
                timestamp: 1745611236.567,
                session_id: "fallback_session",
                predicted_class: "left",
                predicted_index: 0,
                confidence: 0.96,
                probabilities: [
                    "left": 0.96,
                    "right": 0.02,
                    "both": 0.02
                ],
                processing_time_ms: 11.8,
                above_threshold: true
            ),
            PredictionMessage(
                type: "prediction",
                timestamp: 1745611237.567,
                session_id: "fallback_session",
                predicted_class: "both",
                predicted_index: 2,
                confidence: 0.91,
                probabilities: [
                    "left": 0.20,
                    "right": 0.19,
                    "both": 0.91
                ],
                processing_time_ms: 13.2,
                above_threshold: true
            )
        ]
    }
}
