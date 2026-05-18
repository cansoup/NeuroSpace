import SwiftUI

/// Display helpers for the BCI connection state. Centralised so the lobby
/// pill, the in-game HUD dot, the Settings debug line, and any other place
/// that surfaces the connection all use the same label and tint.
extension BCIWebSocketClient.ConnectionState {

    /// Short human-readable label, e.g. "Connected" / "Connecting…" / "Failed: …".
    var displayText: String {
        switch self {
        case .connected:     return "Connected"
        case .connecting:    return "Connecting…"
        case .disconnected:  return "Disconnected"
        case .failed(let m): return "Failed: \(m)"
        }
    }

    /// Canonical tint colour for the state. Picks brand teal for connected,
    /// warning amber while transient, tertiary text grey for disconnected,
    /// and error red for failed.
    var tint: Color {
        switch self {
        case .connected:    return DS.teal
        case .connecting:   return DS.warning
        case .disconnected: return DS.textTertiary
        case .failed:       return DS.error
        }
    }
}
