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

    private var socketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private let decoder = JSONDecoder()
    private let minimumConfidence = 0.75

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

    private func route(intent: String, confidence: Double) {
        lastIntent = intent
        lastConfidence = confidence

        guard confidence >= minimumConfidence else {
            appendLog("Ignored \(intent) because confidence \(confidence) < \(minimumConfidence)")
            return
        }

        switch intent {
        case "focus_left":
            appendLog("Action: highlight left target")
        case "focus_right":
            appendLog("Action: highlight right target")
        case "confirm":
            appendLog("Action: confirm selected target")
        case "idle":
            appendLog("Action: no-op / idle")
        default:
            appendLog("Unknown intent: \(intent)")
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
