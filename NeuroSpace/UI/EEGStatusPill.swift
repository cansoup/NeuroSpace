import SwiftUI

/// Reusable capsule that reflects the BCI WebSocket client state.
/// Label and tint come from `BCIWebSocketClient.ConnectionState`'s display
/// helpers so every site that shows the connection (lobby, in-game HUD,
/// stage-end screens, My Progress header, Settings header) stays in sync.
struct EEGStatusPill: View {
    @Environment(AppModel.self) private var appModel

    /// Uppercased variant of `displayText` — pills look louder than the
    /// regular label used elsewhere.
    private var label: String {
        switch appModel.bciClient.state {
        case .connected:    return "CONNECTED"
        case .connecting:   return "CONNECTING…"
        case .disconnected: return "DISCONNECTED"
        case .failed:       return "CONNECTION FAILED"
        }
    }

    var body: some View {
        let color = appModel.bciClient.state.tint
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(DS.fontMeta)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.30), lineWidth: 1))
    }
}
