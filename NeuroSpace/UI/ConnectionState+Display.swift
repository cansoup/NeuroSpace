import SwiftUI

extension BCIWebSocketClient.ConnectionState {

    var displayText: String {
        switch self {
        case .connected:     return "Connected"
        case .connecting:    return "Connecting…"
        case .disconnected:  return "Disconnected"
        case .failed(let m): return "Failed: \(m)"
        }
    }

    var tint: Color {
        switch self {
        case .connected:    return DS.teal
        case .connecting:   return DS.warning
        case .disconnected: return DS.textTertiary
        case .failed:       return DS.error
        }
    }
}
