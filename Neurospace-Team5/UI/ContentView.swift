import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        LobbyView()
            .frame(width: 1040, height: 520)
    }
}

struct LobbyView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    private var controller: BubbleGameController { appModel.gameController }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection

            HStack(alignment: .top, spacing: 16) {
                statusSection
                    .frame(minWidth: 430, maxWidth: .infinity, alignment: .topLeading)

                BubblePointsPanel()
                    .frame(width: 270, alignment: .topLeading)
            }

            HStack(alignment: .top, spacing: 16) {
                armDebugSection
                    .frame(width: 260, alignment: .topLeading)

                debugControlsSection
                    .frame(minWidth: 450, maxWidth: .infinity, alignment: .topLeading)
            }

            Spacer(minLength: 0)

            startSection
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Neurospace")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text("BCI Bubble Pop")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Session Overview")

            VStack(spacing: 10) {
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

                StatusRow(
                    icon: "star.fill",
                    label: "Current Score",
                    value: "\(controller.score)",
                    valueColor: .yellow
                )

                StatusRow(
                    icon: "flag.fill",
                    label: "Stage",
                    value: "\(controller.currentStage)",
                    valueColor: .blue
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var armDebugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Arm Debug")

            VStack(alignment: .leading, spacing: 10) {
                debugValueRow(title: "Left Tip", value: controller.leftTipText)
                debugValueRow(title: "Right Tip", value: controller.rightTipText)
                debugValueRow(title: "Motion Vector", value: controller.motionVectorText)
                debugValueRow(title: "Active Bubble", value: controller.activeBubbleText)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var debugControlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Debug Controls")

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    miniLabel("Arm Selection")

                    HStack(spacing: 10) {
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
                }

                VStack(alignment: .leading, spacing: 8) {
                    miniLabel("Movement")

                    HStack(spacing: 8) {
                        smallControlButton("← Left") { controller.applyIntent(.moveLeft) }
                        smallControlButton("Right →") { controller.applyIntent(.moveRight) }
                        smallControlButton("↑ Up") { controller.applyIntent(.moveUp) }
                        smallControlButton("↓ Down") { controller.applyIntent(.moveDown) }
                    }

                    HStack(spacing: 8) {
                        smallControlButton("Forward") { controller.applyIntent(.moveForward) }
                        smallControlButton("Backward") { controller.applyIntent(.moveBackward) }
                        smallControlButton("Idle") { controller.applyIntent(.idle) }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    miniLabel("JSON Playback")

                    HStack(spacing: 8) {
                        smallControlButton("Load JSON") {
                            appModel.jsonPlayback.loadJSON(named: "bci_test_data")
                        }

                        Button("Play JSON") {
                            appModel.jsonPlayback.startPlayback(interval: 0.1)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .controlSize(.small)

                        smallControlButton("Stop JSON") {
                            appModel.jsonPlayback.stopPlayback()
                        }

                        Button("Reset Game") {
                            controller.resetGame()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red.opacity(0.85))
                        .controlSize(.small)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startSection: some View {
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
                .padding(.vertical, 9)
        }
        .buttonStyle(.borderedProminent)
        .tint(.purple)
        .disabled(controller.sessionState == .playing || appModel.immersiveSpaceState == .inTransition)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.secondary)
    }

    private func miniLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func debugValueRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func smallControlButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private var connectionColor: Color {
        switch controller.connectionState {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .orange
        case .failed: return .red
        }
    }
}

struct BubblePointsPanel: View {
    private let bubbleTypes: [BubbleType] = [.red, .blue, .green, .gold]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bubble Points")
                .font(.system(size: 15, weight: .bold))

            Text("Pop as many bubbles as possible and aim for the highest score.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(bubbleTypes, id: \.rawValue) { type in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(uiColor: type.uiColor))
                            .frame(width: 11, height: 11)

                        Text(type.displayName)
                            .font(.system(size: 13, weight: .medium))

                        Spacer()

                        Text("\(type.points) pts")
                            .font(.system(size: 13, weight: .bold))
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct StatusRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(width: 14)
                .foregroundStyle(.secondary)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
