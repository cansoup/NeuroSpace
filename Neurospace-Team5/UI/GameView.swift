//
//  GameView.swift
//  Neurospace-Team5
//

import SwiftUI

// MARK: - Main Game HUD

struct GameView: View {
    @Environment(AppModel.self) private var appModel
    @State private var elapsedSeconds: Int = 0

    private var controller: BubbleGameController { appModel.gameController }

    private var poppedCount: Int { controller.bubbles.filter(\.isPopped).count }
    private var progress: Double {
        controller.bubbles.isEmpty ? 0 : Double(poppedCount) / Double(controller.bubbles.count)
    }

    var body: some View {
        ZStack {
            // Top-center: Stage + Target (overlaid independently)
            VStack {
                VStack(spacing: 10) {
                    Text("STAGE \(controller.currentStage)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .padding(.horizontal, 40)
                        .padding(.vertical, 13)
                        .background(.regularMaterial, in: Capsule())

                    Text("Target: Pop \(controller.targetBubbleColor) Bubble")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                }
                .padding(.top, 24)
                Spacer()
            }

            // Left + Right + Bottom panels
            VStack {
                HStack(alignment: .top) {
                    SessionSummaryPanel(
                        poppedCount: poppedCount,
                        totalCount: controller.bubbles.count,
                        elapsedSeconds: elapsedSeconds,
                        accuracy: controller.accuracy
                    )
                    Spacer()
                    EEGControlPanel(
                        connectionState: controller.connectionState,
                        onStopGame: { controller.resetGame() }
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                Spacer()

                HStack(alignment: .center, spacing: 12) {
                    BubbleProgressPanel(
                        progress: progress,
                        poppedCount: poppedCount,
                        totalCount: controller.bubbles.count
                    )
                    ScorePanel(score: controller.score)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
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

// MARK: - Session Summary Panel (top-left)

struct SessionSummaryPanel: View {
    let poppedCount: Int
    let totalCount: Int
    let elapsedSeconds: Int
    let accuracy: Double

    private var timeString: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var accuracyColor: Color {
        accuracy >= 0.8 ? .green : accuracy >= 0.6 ? .orange : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.purple)
                Text("Session Summary")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.3)

            // Target Count
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target Count")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Pop/Remaining: \(poppedCount)/\(totalCount)")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().opacity(0.2).padding(.horizontal, 10)

            // Timer
            HStack(spacing: 10) {
                Image(systemName: "timer")
                    .font(.system(size: 18))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text(timeString)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                    Text("Timer")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().opacity(0.2).padding(.horizontal, 10)

            // Accuracy
            HStack {
                Text("Accuracy")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(accuracy * 100))%")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accuracyColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 210)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.purple.opacity(0.35), lineWidth: 1.5)
        }
    }
}

// MARK: - EEG Control Panel (top-right)

struct EEGControlPanel: View {
    let connectionState: ConnectionState
    let onStopGame: () -> Void
    @State private var showStopConfirm = false
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(AppModel.self) private var appModel

    private var signalColor: Color {
        switch connectionState {
        case .connected:        return .green
        case .connecting:       return .yellow
        case .disconnected:     return .red
        case .failed:           return .red
        }
    }

    private var signalIcon: String {
        switch connectionState {
        case .connected:    return "waveform.path.ecg"
        case .connecting:   return "waveform"
        default:            return "waveform.path.ecg.rectangle"
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Labels
            HStack(spacing: 28) {
                Text("EEG Headset Signal")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Stop game")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Buttons
            HStack(spacing: 8) {
                HUDIconButton(icon: "camera.fill")
                HUDIconButton(icon: "mic.fill")

                // EEG signal button
                Button {
                    // future: show signal detail
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: signalIcon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Circle()
                            .fill(signalColor)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                            .offset(x: 3, y: -3)
                    }
                }
                .buttonStyle(.plain)

                // Stop game
                Button {
                    showStopConfirm = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.red, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .confirmationDialog("Stop Game?", isPresented: $showStopConfirm, titleVisibility: .visible) {
                    Button("Stop Game", role: .destructive) {
                        Task { @MainActor in
                            onStopGame()
                            if appModel.immersiveSpaceState == .open {
                                appModel.immersiveSpaceState = .inTransition
                                await dismissImmersiveSpace()
                            }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Current progress will be saved.")
                }
            }
        }
    }
}

// MARK: - HUD Icon Button

struct HUDIconButton: View {
    let icon: String
    var action: (() -> Void)? = nil

    var body: some View {
        Button { action?() } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bubble Progress Panel (bottom)

struct BubbleProgressPanel: View {
    let progress: Double
    let poppedCount: Int
    let totalCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bubble Pop Progress: \(Int(progress * 100))%")
                .font(.system(size: 13, weight: .semibold))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 8)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.purple, .indigo],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * progress, 0), height: 8)
                        .animation(.easeInOut(duration: 0.4), value: progress)
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: Capsule())
    }
}

// MARK: - Score Panel (bottom-right)

struct ScorePanel: View {
    let score: Int

    var body: some View {
        VStack(spacing: 3) {
            Text("SCORE")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(1.5)
            Text("\(score)pt")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.3), value: score)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .background(.regularMaterial, in: Capsule())
    }
}

#Preview(windowStyle: .automatic) {
    GameView()
        .environment(AppModel())
        .frame(width: 1100, height: 650)
}
