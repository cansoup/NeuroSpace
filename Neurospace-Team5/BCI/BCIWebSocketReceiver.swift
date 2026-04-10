import Foundation
import Observation

@Observable
final class BCIWebSocketClient {
    struct IntentMessage: Decodable {
        let type: String
        let intent: String
        let confidence: Double
        let timestamp_ms: Int
        let seq: Int
        let source: String?
    }

    struct StatusMessage: Decodable {
        let type: String
        let state: String
        let message: String
        let timestamp_ms: Int
    }

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    var state: ConnectionState = .disconnected
    var lastIntent: String = "-"
    var lastConfidence: Double = 0
    var logLines: [String] = []

    /// Assign this before starting a session so intent messages drive the arm.
    /// Set from AppModel or BubbleGameController when the session begins.
    var armMapper: BCIArmMapper?

    private var socketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private let decoder = JSONDecoder()

    // Aligned with the Python bridge CONFIDENCE_THRESHOLD (0.65).
    // BCIArmMapper applies its own secondary check at 0.55.
    private let minimumConfidence = 0.65

    // Movement magnitude applied per intent (matches bci_test_data.json scale)
    private let moveMagnitude: Float = 0.9

    func connect(host: String, port: Int = 8765) {
        disconnect()

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            state = .failed("Host is empty")
            return
        }
        guard (1...65535).contains(port) else {
            state = .failed("Port must be 1-65535")
            return
        }
        guard let url = URL(string: "ws://\(trimmedHost):\(port)") else {
            state = .failed("Bad WebSocket URL")
            return
        }

        state = .connecting
        socketTask = session.webSocketTask(with: url)
        socketTask?.resume()

        listen()
    }

    func disconnect() {
        socketTask?.cancel(with: .normalClosure, reason: nil)
        socketTask = nil
        state = .disconnected
    }

    func sendPing() {
        guard socketTask != nil else {
            appendLog("Ping skipped: not connected")
            return
        }
        socketTask?.sendPing { [weak self] error in
            if let error {
                self?.appendLog("Ping failed: \(error.localizedDescription)")
            } else {
                self?.appendLog("Ping ok")
            }
        }
    }

    func clearLog() {
        logLines.removeAll(keepingCapacity: false)
    }

    private func listen() {
        Task { [weak self] in
            guard let self else { return }

            do {
                while let socketTask = self.socketTask {
                    let message = try await socketTask.receive()
                    if self.state == .connecting {
                        self.state = .connected
                        self.appendLog("Connected to \(socketTask.currentRequest?.url?.absoluteString ?? "unknown URL")")
                    }
                    switch message {
                    case .string(let text):
                        self.handle(text: text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handle(text: text)
                        } else {
                            self.appendLog("Received non-UTF8 data frame")
                        }
                    @unknown default:
                        self.appendLog("Received unknown frame")
                    }
                }
            } catch {
                self.state = .failed(error.localizedDescription)
                self.appendLog("Receive failed: \(error.localizedDescription)")
            }
        }
    }

    private func handle(text: String) {
        appendLog("RX: \(text)")
        guard let data = text.data(using: .utf8) else { return }

        do {
            if let generic = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let type = generic["type"] as? String {
                switch type {
                case "intent":
                    let message = try decoder.decode(IntentMessage.self, from: data)
                    route(intent: message.intent, confidence: message.confidence)
                case "status":
                    let message = try decoder.decode(StatusMessage.self, from: data)
                    appendLog("Status: \(message.state) - \(message.message)")
                default:
                    appendLog("Unhandled type: \(type)")
                }
            } else {
                appendLog("Malformed JSON message")
            }
        } catch {
            appendLog("Decode failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Intent routing

    private func route(intent: String, confidence: Double) {
        lastIntent = intent
        lastConfidence = confidence

        guard confidence >= minimumConfidence else {
            appendLog("Ignored \(intent) — confidence \(String(format: "%.2f", confidence)) < \(minimumConfidence)")
            sendControlMessage(.idle, confidence: confidence)
            return
        }

        switch intent {

        // ── EEGNet outputs (from Python bridge_server.py) ─────────────────
        case "moveLeft":
            appendLog("Action: move LEFT arm (\(String(format: "%.2f", confidence)))")
            sendControlMessage(.moveLeft, confidence: confidence)

        case "moveRight":
            appendLog("Action: move RIGHT arm (\(String(format: "%.2f", confidence)))")
            sendControlMessage(.moveRight, confidence: confidence)

        case "moveUp":
            appendLog("Action: move UP (\(String(format: "%.2f", confidence)))")
            sendControlMessage(.moveUp, confidence: confidence)

        case "moveDown":
            appendLog("Action: move DOWN (\(String(format: "%.2f", confidence)))")
            sendControlMessage(.moveDown, confidence: confidence)

        case "moveForward":
            appendLog("Action: move FORWARD (\(String(format: "%.2f", confidence)))")
            sendControlMessage(.moveForward, confidence: confidence)

        case "moveBackward":
            appendLog("Action: move BACKWARD (\(String(format: "%.2f", confidence)))")
            sendControlMessage(.moveBackward, confidence: confidence)

        case "idle":
            appendLog("Action: idle — stopping motion")
            sendControlMessage(.idle, confidence: confidence)

        // ── Legacy mock intents (kept for debug/fallback) ─────────────────
        case "focus_left":
            appendLog("Action: focus_left (legacy) → moveLeft")
            sendControlMessage(.moveLeft, confidence: confidence)

        case "focus_right":
            appendLog("Action: focus_right (legacy) → moveRight")
            sendControlMessage(.moveRight, confidence: confidence)

        case "confirm":
            appendLog("Action: confirm (legacy) → idle")
            sendControlMessage(.idle, confidence: confidence)

        default:
            appendLog("Unknown intent: \(intent)")
        }
    }

    // MARK: - BCIArmMapper bridge

    /// Translates a semantic intent into a BCIControlMessage and forwards it
    /// to BCIArmMapper, which drives BubbleGameController.
    private func sendControlMessage(_ intent: BCIIntent, confidence: Double) {
        let (activeArm, x, y, z): (ActiveArm, Float, Float, Float) = {
            switch intent {
            case .moveLeft:     return (.left,  -moveMagnitude,  0, 0)
            case .moveRight:    return (.right,  moveMagnitude,  0, 0)
            case .moveUp:       return (.right,  0,  moveMagnitude, 0)
            case .moveDown:     return (.right,  0, -moveMagnitude, 0)
            case .moveForward:  return (.right,  0,  0, -moveMagnitude)
            case .moveBackward: return (.right,  0,  0,  moveMagnitude)
            case .idle, .pop:   return (.right,  0,  0,  0)
            }
        }()

        let message = BCIControlMessage(
            timestamp: Date().timeIntervalSince1970,
            activeArm: activeArm,
            moveX: x,
            moveY: y,
            moveZ: z,
            confidence: Float(confidence)
        )

        // BCIArmMapper is @MainActor — dispatch to main thread
        Task { @MainActor in
            self.armMapper?.handleControlMessage(message)
        }
    }

    private func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > 50 {
            logLines.removeFirst(logLines.count - 50)
        }
        print(line)
    }
}
