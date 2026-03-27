//
//  GameView.swift
//  Neurospace-Team5
//

import SwiftUI

// MARK: - Compact Control Panel (rendered as RealityKit attachment in ImmersiveView)

struct GameControlPanel: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @State private var showStopConfirm = false

    private var controller: BubbleGameController { appModel.gameController }

    private var timeString: String {
        let t = controller.remainingSeconds
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    private var isLowTime: Bool { controller.remainingSeconds <= 30 }

    private var eegColor: Color {
        switch controller.connectionState {
        case .connected:    return .green
        case .connecting:   return .yellow
        case .disconnected: return .orange
        case .failed:       return .red
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            // EEG status + Stop
            HStack(spacing: 10) {
                Circle()
                    .fill(eegColor)
                    .frame(width: 8, height: 8)
                Text(controller.connectionState.displayText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showStopConfirm = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(.red, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Inline stop confirmation
            if showStopConfirm {
                Divider().opacity(0.3)
                VStack(spacing: 8) {
                    Text("Stop session?")
                        .font(.system(size: 12, weight: .semibold))
                    HStack(spacing: 8) {
                        Button("Cancel") {
                            showStopConfirm = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Stop") {
                            showStopConfirm = false
                            Task { @MainActor in
                                controller.resetGame()
                                if appModel.immersiveSpaceState == .open {
                                    appModel.immersiveSpaceState = .inTransition
                                    await dismissImmersiveSpace()
                                }
                                openWindow(id: appModel.mainWindowID)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            Divider().opacity(0.3)

            // Score + Timer
            HStack(spacing: 20) {
                VStack(spacing: 2) {
                    Text(timeString)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(isLowTime ? .red : .primary)
                        .animation(.easeInOut(duration: 0.3), value: isLowTime)
                    Text("TIME")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                }

                Divider()
                    .frame(height: 30)
                    .opacity(0.3)

                VStack(spacing: 2) {
                    Text("\(controller.score)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.3), value: controller.score)
                    Text("SCORE")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 200)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
