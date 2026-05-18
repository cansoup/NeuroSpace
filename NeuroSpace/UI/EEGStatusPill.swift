import SwiftUI

/// Reusable capsule that reflects the BCI WebSocket client state.
/// Shows Connected / Connecting… / Disconnected / Failed with matching
/// dot and tint colour. Read by the lobby, in-game HUD, stage-end
/// screens, My Progress header, and the Settings header.
struct EEGStatusPill: View {
    @Environment(AppModel.self) private var appModel

    private var label: String {
        switch appModel.bciClient.state {
        case .connected:     return "CONNECTED"
        case .connecting:    return "CONNECTING…"
        case .disconnected:  return "DISCONNECTED"
        case .failed:        return "CONNECTION FAILED"
        }
    }

    private var color: Color {
        switch appModel.bciClient.state {
        case .connected:    return DS.teal
        case .connecting:   return DS.warning
        case .disconnected: return DS.textTertiary
        case .failed:       return DS.error
        }
    }

    var body: some View {
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
