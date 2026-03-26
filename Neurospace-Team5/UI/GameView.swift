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
    @State private var elapsedSeconds: Int = 0
    @State private var showStopConfirm = false

    private var controller: BubbleGameController { appModel.gameController }

    private var timeString: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

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
                .confirmationDialog("Stop Session?", isPresented: $showStopConfirm, titleVisibility: .visible) {
                    Button("Stop", role: .destructive) {
                        Task { @MainActor in
                            controller.resetGame()
                            if appModel.immersiveSpaceState == .open {
                                appModel.immersiveSpaceState = .inTransition
                                await dismissImmersiveSpace()
                            }
                            openWindow(id: appModel.mainWindowID)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().opacity(0.3)

            // Score + Timer
            HStack(spacing: 20) {
                VStack(spacing: 2) {
                    Text(timeString)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
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
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if controller.sessionState == .playing {
                    elapsedSeconds += 1
                }
            }
        }
    }
}
