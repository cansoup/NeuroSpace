//
//  ContentView.swift
//  Neurospace-Team5
//

//
//  ContentView.swift
//  Neurospace-Team5
//

//
//  ContentView.swift
//  Neurospace-Team5
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        LobbyView()
            .frame(minWidth: 420, minHeight: 620)
    }
}

struct LobbyView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    private var controller: BubbleGameController { appModel.gameController }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Neurospace")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("BCI Bubble Pop")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Divider()

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
                StatusRow(
                    icon: "hand.raised",
                    label: "Active Arm",
                    value: controller.activeArm.rawValue.capitalized,
                    valueColor: .purple
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Arm Debug")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                Text("Left Tip: \(controller.leftTipText)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))

                Text("Right Tip: \(controller.rightTipText)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))

                Text("Motion Vector: \(controller.motionVectorText)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Debug Controls")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                HStack(spacing: 8) {
                    Button("Left Arm") {
                        controller.setActiveArm(.left)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(controller.activeArm == .left ? .purple : .gray)

                    Button("Right Arm") {
                        controller.setActiveArm(.right)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(controller.activeArm == .right ? .purple : .gray)
                }

                HStack(spacing: 8) {
                    Button("← Left") { controller.applyIntent(.moveLeft) }
                        .buttonStyle(.bordered)

                    Button("Right →") { controller.applyIntent(.moveRight) }
                        .buttonStyle(.bordered)

                    Button("↑ Up") { controller.applyIntent(.moveUp) }
                        .buttonStyle(.bordered)

                    Button("↓ Down") { controller.applyIntent(.moveDown) }
                        .buttonStyle(.bordered)
                }

                HStack(spacing: 8) {
                    Button("Forward") { controller.applyIntent(.moveForward) }
                        .buttonStyle(.bordered)

                    Button("Backward") { controller.applyIntent(.moveBackward) }
                        .buttonStyle(.bordered)

                    Button("Idle") { controller.applyIntent(.idle) }
                        .buttonStyle(.bordered)
                }

                Button("Reset Game") {
                    controller.resetGame()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red.opacity(0.8))
            }

            Divider()

            Button {
                Task { @MainActor in
                    controller.startSession()

                    if appModel.immersiveSpaceState == .closed {
                        appModel.immersiveSpaceState = .inTransition

                        switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                        case .opened:
                            dismissWindow(id: appModel.mainWindowID)

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
