//
//  ContentView.swift
//  Neurospace-Team5
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    private var controller: BubbleGameController { appModel.gameController }

    var body: some View {
        Group {
            switch controller.sessionState {
            case .playing, .paused:
                GameView()
                    .frame(minWidth: 240, minHeight: 120)
            default:
                LobbyView()
                    .frame(minWidth: 520, minHeight: 380)
            }
        }
    }
}

// MARK: - Lobby / Setup View

struct LobbyView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    private var controller: BubbleGameController { appModel.gameController }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text("Neurospace")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("BCI Bubble Pop")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Status
            VStack(alignment: .leading, spacing: 10) {
                StatusRow(
                    icon: "antenna.radiowaves.left.and.right",
                    label: "EEG Connection",
                    value: controller.connectionState.displayText,
                    valueColor: connectionColor
                )
                StatusRow(
                    icon: "gamecontroller",
                    label: "Session",
                    value: controller.sessionState.rawValue.capitalized,
                    valueColor: .primary
                )
                StatusRow(
                    icon: "brain.head.profile",
                    label: "Last Intent",
                    value: controller.currentIntent.rawValue,
                    valueColor: .secondary
                )
            }

            Divider()

            // Debug controls
            VStack(alignment: .leading, spacing: 12) {
                Text("Debug Controls")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                HStack(spacing: 8) {
                    Button("← Left") { controller.applyIntent(.moveLeft) }
                        .buttonStyle(.bordered)
                    Button("Right →") { controller.applyIntent(.moveRight) }
                        .buttonStyle(.bordered)
                    Button("Idle") { controller.applyIntent(.idle) }
                        .buttonStyle(.bordered)
                }

                Button("Reset Game") { controller.resetGame() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red.opacity(0.8))
            }

            Divider()

            // Start game
            Button {
                Task { @MainActor in
                    controller.sessionState = .playing
                    if appModel.immersiveSpaceState == .closed {
                        appModel.immersiveSpaceState = .inTransition
                        switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                        case .opened:
                            break
                        case .userCancelled, .error:
                            fallthrough
                        @unknown default:
                            appModel.immersiveSpaceState = .closed
                        }
                    }
                }
            } label: {
                Label("Start Session", systemImage: "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(controller.sessionState == .playing || appModel.immersiveSpaceState == .inTransition)
        }
        .padding(28)
    }

    private var connectionColor: Color {
        switch controller.connectionState {
        case .connected:    return .green
        case .connecting:   return .yellow
        case .disconnected: return .orange
        case .failed:       return .red
        }
    }
}

// MARK: - Status Row

struct StatusRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(valueColor)
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
