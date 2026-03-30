// EEGPredictionBridge.swift
// VisionStudio – Team 5
//
// Connects to the Python EEG classifier's LSL output stream via UDP/TCP
// and translates predictions into arm movement commands for the visionOS app.
//
// Architecture:
//   Python classifier  ──LSL──►  BridgeServer (localhost:12345)
//                                     │
//                              EEGPredictionBridge (SwiftUI @Observable)
//                                     │
//                              ArmMovementController
//                                     │
//                          RealityKit Entity animations
//
// The Python script already streams integer predictions over LSL.
// A thin bridge server (see BridgeServer.py in /scripts) converts those
// LSL samples to newline-delimited JSON over TCP so we can read them here
// without a native LSL SDK.
//
// Prediction codes:
//   0 → idle   (no movement)
//   1 → left   (raise / extend left arm)
//   2 → right  (raise / extend right arm)

import Foundation
import RealityKit
import Combine
import SwiftUI

// MARK: - Prediction Model

/// A single classified EEG prediction received from the Python pipeline.
public struct EEGPrediction: Sendable, Equatable {
    public enum Movement: Int, Sendable, CaseIterable {
        case idle  = 0
        case left  = 1
        case right = 2

        public var label: String {
            switch self {
            case .idle:  return "Idle"
            case .left:  return "Left"
            case .right: return "Right"
            }
        }
    }

    public let movement:   Movement
    public let confidence: Float   // 0–1, optional – set to 1 if not provided
    public let timestamp:  Date

    public init(movement: Movement, confidence: Float = 1.0, timestamp: Date = .now) {
        self.movement   = movement
        self.confidence = confidence
        self.timestamp  = timestamp
    }
}


// MARK: - EEGPredictionBridge

/// Connects to the bridge server and publishes EEG predictions.
/// Designed to run on a background actor; UI updates are published on the main actor.
@MainActor
@Observable
public final class EEGPredictionBridge {

    // ── Public state ──────────────────────────────────────────────────────────
    public private(set) var latestPrediction: EEGPrediction = .init(movement: .idle)
    public private(set) var isConnected: Bool = false
    public private(set) var connectionError: String?

    // ── Configuration ─────────────────────────────────────────────────────────
    public var host: String = "127.0.0.1"
    public var port: UInt16 = 12345

    // ── Internals ─────────────────────────────────────────────────────────────
    private var receiveTask: Task<Void, Never>?
    private var connection: NWConnection?    // NetworkExtension – available on visionOS

    // Fallback demo mode when no server is available
    public var demoMode: Bool = false

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    public init() {}

    deinit { stop() }

    public func start() {
        guard receiveTask == nil else { return }
        if demoMode {
            receiveTask = Task { await self.runDemoLoop() }
        } else {
            receiveTask = Task { await self.runNetworkLoop() }
        }
    }

    public func stop() {
        receiveTask?.cancel()
        receiveTask = nil
        isConnected = false
    }

    // MARK: - Network loop (TCP)

    private func runNetworkLoop() async {
        while !Task.isCancelled {
            do {
                try await connectAndReceive()
            } catch {
                connectionError = error.localizedDescription
                isConnected     = false
                // Back-off before retry
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func connectAndReceive() async throws {
        let url = URL(string: "http://\(host):\(port)")!
        connectionError = nil

        // Use URLSession stream for simplicity on visionOS
        // The Python bridge server writes newline-delimited JSON:
        //   {"prediction": 1, "confidence": 0.87}\n
        let (bytes, _) = try await URLSession.shared.bytes(from: url)
        isConnected = true

        var lineBuffer = ""
        for try await byte in bytes {
            let char = Character(UnicodeScalar(byte))
            if char == "\n" {
                handleLine(lineBuffer)
                lineBuffer = ""
            } else {
                lineBuffer.append(char)
            }
        }
    }

    private func handleLine(_ line: String) {
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let json = try? JSONDecoder().decode(PredictionPayload.self, from: data)
        else { return }

        let movement = EEGPrediction.Movement(rawValue: json.prediction) ?? .idle
        latestPrediction = EEGPrediction(
            movement:   movement,
            confidence: json.confidence ?? 1.0
        )
    }

    // MARK: - Demo loop

    /// Cycles through predictions for UI testing without a real EEG device.
    private func runDemoLoop() async {
        let sequence: [(EEGPrediction.Movement, Float, Double)] = [
            (.idle,  1.0, 1.5),
            (.left,  0.9, 2.0),
            (.idle,  1.0, 0.5),
            (.right, 0.85, 2.0),
            (.idle,  1.0, 0.5),
            (.left,  0.92, 1.5),
            (.right, 0.78, 1.5),
        ]

        var i = 0
        while !Task.isCancelled {
            let (movement, conf, delay) = sequence[i % sequence.count]
            latestPrediction = EEGPrediction(movement: movement, confidence: conf)
            try? await Task.sleep(for: .seconds(delay))
            i += 1
        }
    }

    // MARK: - Codable helpers

    private struct PredictionPayload: Decodable {
        let prediction:  Int
        let confidence:  Float?
    }
}


// MARK: - ArmMovementController

/// Drives RealityKit arm entities based on incoming EEG predictions.
/// Attach to your RealityView update closure.
@MainActor
public final class ArmMovementController: ObservableObject {

    // ── Entities set by the caller ─────────────────────────────────────────
    public var leftArmEntity:  Entity?
    public var rightArmEntity: Entity?

    // ── Animation parameters ───────────────────────────────────────────────
    public var raiseDuration:   TimeInterval = 0.4   // seconds to raise arm
    public var lowerDuration:   TimeInterval = 0.6   // seconds to lower arm
    public var holdDuration:    TimeInterval = 1.2   // seconds to hold raised position

    /// Rotation (in degrees) applied to the arm when "raised".
    public var raiseAngleDeg:   Float = -80.0        // negative = forward/up

    private var cancellables = Set<AnyCancellable>()
    private var currentMovement: EEGPrediction.Movement = .idle
    private var holdTask: Task<Void, Never>?

    public init() {}

    // ── Connect to bridge ──────────────────────────────────────────────────

    /// Observe the bridge and react to each new prediction.
    public func observe(_ bridge: EEGPredictionBridge) {
        // visionOS / SwiftUI @Observable doesn't expose a Combine publisher directly;
        // use a polling task instead, which is idiomatic for @Observable.
        Task { @MainActor [weak self] in
            var last: EEGPrediction.Movement = .idle
            while true {
                let current = bridge.latestPrediction.movement
                if current != last {
                    self?.apply(prediction: bridge.latestPrediction)
                    last = current
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    // MARK: - Apply prediction

    public func apply(prediction: EEGPrediction) {
        guard prediction.movement != currentMovement else { return }
        currentMovement = prediction.movement

        holdTask?.cancel()

        switch prediction.movement {
        case .idle:
            lowerBothArms()
        case .left:
            raiseArm(entity: leftArmEntity)
            lowerArm(entity: rightArmEntity)
            scheduleAutoLower()
        case .right:
            raiseArm(entity: rightArmEntity)
            lowerArm(entity: leftArmEntity)
            scheduleAutoLower()
        }
    }

    // MARK: - RealityKit animations

    private func raiseArm(entity: Entity?) {
        guard let entity else { return }
        var transform = entity.transform
        transform.rotation = simd_quatf(
            angle: raiseAngleDeg * (.pi / 180),
            axis: SIMD3<Float>(1, 0, 0)   // rotate around X axis (forward tilt)
        )
        entity.move(
            to: transform,
            relativeTo: entity.parent,
            duration: raiseDuration,
            timingFunction: .easeOut
        )
    }

    private func lowerArm(entity: Entity?) {
        guard let entity else { return }
        var transform = entity.transform
        transform.rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(1, 0, 0))
        entity.move(
            to: transform,
            relativeTo: entity.parent,
            duration: lowerDuration,
            timingFunction: .easeIn
        )
    }

    private func lowerBothArms() {
        lowerArm(entity: leftArmEntity)
        lowerArm(entity: rightArmEntity)
    }

    private func scheduleAutoLower() {
        holdTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(holdDuration))
            if !Task.isCancelled {
                lowerBothArms()
                currentMovement = .idle
            }
        }
    }
}


// MARK: - SwiftUI Preview helper

#if DEBUG
/// Drop this into a RealityView for quick visual testing.
public struct EEGDebugOverlay: View {
    @State private var bridge = EEGPredictionBridge()

    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            Text("EEG Prediction")
                .font(.headline)
            Text(bridge.latestPrediction.movement.label)
                .font(.largeTitle.bold())
                .foregroundStyle(color(for: bridge.latestPrediction.movement))
            Text(String(format: "conf: %.0f%%", bridge.latestPrediction.confidence * 100))
                .font(.caption)
            HStack {
                Circle()
                    .fill(bridge.isConnected ? .green : .red)
                    .frame(width: 10, height: 10)
                Text(bridge.isConnected ? "connected" : "disconnected")
                    .font(.caption2)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            bridge.demoMode = true
            bridge.start()
        }
    }

    private func color(for movement: EEGPrediction.Movement) -> Color {
        switch movement {
        case .idle:  return .secondary
        case .left:  return .blue
        case .right: return .orange
        }
    }
}
#endif
