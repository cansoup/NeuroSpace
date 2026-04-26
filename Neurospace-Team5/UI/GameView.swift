//
//  GameView.swift
//  Neurospace-Team5
//

import SwiftUI

// MARK: - Congratulations Window

struct CongratsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)

            VStack(spacing: 8) {
                Text("Congratulations!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                let controller = appModel.gameController
                if controller.isOnFinalStage {
                    Text("You completed all stages!")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Stage \(controller.currentStage) cleared! Ready for Stage \(controller.currentStage + 1)?")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Text("Score: \(appModel.gameController.score)")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.purple)

            Button(appModel.gameController.isOnFinalStage ? "Go to Main" : "Next Stage") {
                Task { @MainActor in
                    if appModel.gameController.canAdvanceStage {
                        appModel.gameController.advanceStage()
                        print("[Congrats] advanced to stage \(appModel.gameController.currentStage)")

                        if appModel.immersiveSpaceState == .open {
                            appModel.gameController.startSession()
                            dismissWindow(id: appModel.congratsWindowID)
                            dismissWindow(id: appModel.missionFailedWindowID)
                        } else {
                            appModel.immersiveSpaceState = .inTransition
                            switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                            case .opened:
                                appModel.immersiveSpaceState = .open
                                appModel.gameController.startSession()
                                dismissWindow(id: appModel.congratsWindowID)
                                dismissWindow(id: appModel.missionFailedWindowID)

                            case .userCancelled, .error:
                                fallthrough

                            @unknown default:
                                appModel.immersiveSpaceState = .closed
                            }
                        }
                    } else {
                        appModel.gameController.resetGame()

                        if appModel.immersiveSpaceState == .open {
                            appModel.immersiveSpaceState = .inTransition
                            await dismissImmersiveSpace()
                            appModel.immersiveSpaceState = .closed
                        }

                        openWindow(id: appModel.mainWindowID)
                        dismissWindow(id: appModel.congratsWindowID)
                        dismissWindow(id: appModel.missionFailedWindowID)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(DS.teal)
            .controlSize(.large)
        }
        .padding(40)

        // IMPORTANT: close this window if the session is being force-ended
        .onChange(of: appModel.shouldEndSession) { _, shouldEnd in
            guard shouldEnd else { return }
            dismissWindow(id: appModel.congratsWindowID)
        }
    }
}

// MARK: - Mission Failed Window

struct MissionFailedView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            VStack(spacing: 8) {
                Text("Mission Failed")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Time's up! Better luck next time.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }

            Text("Score: \(appModel.gameController.score)")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.red)

            HStack(spacing: 16) {
                Button("Go to Main") {
                    Task { @MainActor in
                        dismissWindow(id: appModel.missionFailedWindowID)
                        dismissWindow(id: appModel.congratsWindowID)

                        appModel.gameController.resetGame()

                        if appModel.immersiveSpaceState == .open {
                            appModel.immersiveSpaceState = .inTransition
                            await dismissImmersiveSpace()
                            appModel.immersiveSpaceState = .closed
                        }

                        openWindow(id: appModel.mainWindowID)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button("Try Again") {
                    Task { @MainActor in
                        dismissWindow(id: appModel.missionFailedWindowID)
                        dismissWindow(id: appModel.congratsWindowID)

                        appModel.gameController.resetGame(keepStage: true)

                        if appModel.immersiveSpaceState != .open {
                            appModel.immersiveSpaceState = .inTransition
                            switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                            case .opened:
                                appModel.immersiveSpaceState = .open
                                appModel.gameController.startSession()

                            case .userCancelled, .error:
                                fallthrough

                            @unknown default:
                                appModel.immersiveSpaceState = .closed
                            }
                        } else {
                            appModel.gameController.startSession()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.teal)
                .controlSize(.large)
            }
        }
        .padding(40)

        // IMPORTANT: close this window if the session is being force-ended
        .onChange(of: appModel.shouldEndSession) { _, shouldEnd in
            guard shouldEnd else { return }
            dismissWindow(id: appModel.missionFailedWindowID)
        }

        // Also make sure this window disappears if the game is no longer in finished state
        .onChange(of: appModel.gameController.sessionState) { _, newState in
            if newState != .finished {
                dismissWindow(id: appModel.missionFailedWindowID)
            }
        }
    }
}

// MARK: - Compact Control Panel (RealityKit attachment)

struct GameControlPanel: View {
    @Environment(AppModel.self) private var appModel
    @State private var confirmingStop = false

    private var controller: BubbleGameController { appModel.gameController }

    private var timeString: String {
        let t = controller.remainingSeconds
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    private var isLowTime: Bool { controller.remainingSeconds <= 30 }

    private var eegColor: Color {
        switch controller.connectionState {
        case .connected:    return DS.success
        case .connecting:   return DS.warning
        case .disconnected: return DS.gold
        case .failed:       return DS.error
        }
    }

    // Stage progression
    private var stageProgress: Double {
        if controller.stageConfig.respawnsEnabled {
            let total = Double(controller.stageConfig.duration)
            guard total > 0 else { return 0 }
            return min(1.0 - Double(controller.remainingSeconds) / total, 1.0)
        } else {
            let total = controller.bubbles.count
            guard total > 0 else { return 0 }
            return Double(controller.bubbles.filter { $0.isPopped }.count) / Double(total)
        }
    }

    private var progressLabel: String {
        if controller.stageConfig.respawnsEnabled {
            return "\(controller.score) pts"
        }
        let popped = controller.bubbles.filter { $0.isPopped }.count
        let total = controller.bubbles.count
        return "\(popped) / \(total) bubbles"
    }

    private func stageIndicatorColor(for stage: Int) -> Color {
        if stage < controller.currentStage { return .purple }
        if stage == controller.currentStage { return .white }
        return .white.opacity(0.2)
    }

    var body: some View {
        VStack(spacing: 0) {
            if confirmingStop {
                VStack(spacing: 16) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.red)

                    Text("End Session?")
                        .font(.system(size: 18, weight: .bold))

                    Text("Your current progress will be lost.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 12) {
                        Button("Cancel") {
                            confirmingStop = false
                        }
                        .controlSize(.large)

                        Button("End Session") {
                            confirmingStop = false
                            appModel.shouldEndSession = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.large)
                    }
                }
                .padding(16)

            } else {
                HStack(spacing: 10) {
                    Circle()
                        .fill(eegColor)
                        .frame(width: 8, height: 8)

                    Text(controller.connectionState.displayText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        confirmingStop = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(.red, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .hoverEffect()
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider().opacity(0.3)

                HStack(spacing: 14) {
                    VStack(spacing: 2) {
                        Text("\(controller.currentStage)/\(StageConfig.totalStages)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("STAGE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                    }

                    VStack(spacing: 2) {
                        Text("\(controller.score)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("SCORE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                    }

                    VStack(spacing: 2) {
                        Text(timeString)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(isLowTime ? .red : .primary)
                        Text("TIME")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

                Divider().opacity(0.3)

                // Progression bar
                VStack(spacing: 6) {
                    HStack {
                        HStack(spacing: 5) {
                            ForEach(1...StageConfig.totalStages, id: \.self) { stage in
                                Capsule()
                                    .fill(stageIndicatorColor(for: stage))
                                    .frame(height: 4)
                                    .animation(.easeInOut(duration: 0.4), value: controller.currentStage)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    HStack {
                        Text(controller.stageConfig.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(progressLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.12))
                                .frame(height: 6)
                            Capsule()
                                .fill(stageProgress >= 1.0 ? Color.green : Color.purple)
                                .frame(width: geo.size.width * CGFloat(stageProgress), height: 6)
                                .animation(.easeOut(duration: 0.3), value: stageProgress)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 14)
            }
        }
        .frame(width: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - Bubble Progress Bar (head-anchored, bottom of view)

struct BubbleProgressBar: View {
    @Environment(AppModel.self) private var appModel

    private var controller: BubbleGameController { appModel.gameController }
    private var isPlaying: Bool { controller.sessionState == .playing }

    var body: some View {
        if isPlaying {
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    ForEach(0..<controller.totalBubbleCount, id: \.self) { i in
                        Capsule()
                            .fill(i < controller.poppedCount ? DS.teal : Color.white.opacity(0.25))
                            .frame(height: 8)
                            .animation(.easeInOut(duration: 0.25), value: controller.poppedCount)
                        if i < controller.totalBubbleCount - 1 {
                            Spacer().frame(width: 3)
                        }
                    }
                }

                Text("\(controller.poppedCount) / \(controller.totalBubbleCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(width: 260)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .transition(.opacity)
        }
    }
}
