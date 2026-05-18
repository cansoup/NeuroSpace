import SwiftUI

struct EEGStatusPill: View {
    @Environment(AppModel.self) private var appModel

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
