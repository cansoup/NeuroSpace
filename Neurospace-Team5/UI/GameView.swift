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

    private var controller: BubbleGameController { appModel.gameController }

    private var canProceed: Bool {
        controller.isOnFinalStage || controller.meetsUnlockCriteria
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: canProceed ? "party.popper.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(canProceed ? .yellow : .orange)

            VStack(spacing: 8) {
                Text(canProceed ? "Congratulations!" : "Stage Not Cleared")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                if controller.isOnFinalStage {
                    Text("You completed all stages!")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                } else if canProceed {
                    Text("Stage \(controller.currentStage) cleared! Ready for Stage \(controller.currentStage + 1)?")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Unlock criteria not met. Try Stage \(controller.currentStage) again to proceed.")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Text("Score: \(controller.score)")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.purple)

            if !controller.isOnFinalStage {
                Text(controller.unlockProgressText)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(canProceed ? DS.success : DS.warning)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        (canProceed ? DS.success : DS.warning).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
            }

            HStack(spacing: 12) {
                if !canProceed {
                    Button("Try Again") {
                        retryStage()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Button(primaryButtonLabel) {
                    primaryAction()
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.teal)
                .controlSize(.large)
            }
        }
        .padding(40)
        .onChange(of: appModel.shouldEndSession) { _, shouldEnd in
            guard shouldEnd else { return }
            dismissWindow(id: appModel.congratsWindowID)
        }
    }

    private var primaryButtonLabel: String {
        if controller.isOnFinalStage { return "Go to Main" }
        return canProceed ? "Next Stage" : "Go to Main"
    }

    private func primaryAction() {
        Task { @MainActor in
            if !controller.isOnFinalStage && canProceed && controller.canAdvanceStage {
                controller.advanceStage()
                print("[Congrats] advanced to stage \(controller.currentStage)")

                if appModel.immersiveSpaceState == .open {
                    controller.startSession()
                    dismissWindow(id: appModel.congratsWindowID)
                    dismissWindow(id: appModel.missionFailedWindowID)
                } else {
                    appModel.immersiveSpaceState = .inTransition
                    switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                    case .opened:
                        appModel.immersiveSpaceState = .open
                        controller.startSession()
                        dismissWindow(id: appModel.congratsWindowID)
                        dismissWindow(id: appModel.missionFailedWindowID)

                    case .userCancelled, .error:
                        fallthrough

                    @unknown default:
                        appModel.immersiveSpaceState = .closed
                    }
                }
            } else {
                dismissWindow(id: appModel.congratsWindowID)
                dismissWindow(id: appModel.missionFailedWindowID)

                appModel.saveSessionRecord()
                controller.resetGame()

                if appModel.immersiveSpaceState == .open {
                    appModel.immersiveSpaceState = .inTransition
                    await dismissImmersiveSpace()
                    appModel.immersiveSpaceState = .closed
                }

                openWindow(id: appModel.mainWindowID)
            }
        }
    }

    private func retryStage() {
        Task { @MainActor in
            dismissWindow(id: appModel.congratsWindowID)
            dismissWindow(id: appModel.missionFailedWindowID)

            controller.resetGame(keepStage: true)

            if appModel.immersiveSpaceState == .open {
                controller.startSession()
            } else {
                appModel.immersiveSpaceState = .inTransition
                switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                case .opened:
                    appModel.immersiveSpaceState = .open
                    controller.startSession()

                case .userCancelled, .error:
                    fallthrough

                @unknown default:
                    appModel.immersiveSpaceState = .closed
                }
            }
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

                        appModel.saveSessionRecord()
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
        .onChange(of: appModel.shouldEndSession) { _, shouldEnd in
            guard shouldEnd else { return }
            dismissWindow(id: appModel.missionFailedWindowID)
        }
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

    private var isLowTime: Bool {
        controller.remainingSeconds <= 30
    }

    private var eegColor: Color {
        switch controller.connectionState {
        case .connected:    return DS.success
        case .connecting:   return DS.warning
        case .disconnected: return DS.gold
        case .failed:       return DS.error
        }
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
                            appModel.jsonPlayback.stopPlayback(resetMotionOnly: true)
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
                .padding(16)

                if appModel.debugMode {
                    Divider().opacity(0.3)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("JSON ARM TEST")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(1)

                        Text(appModel.jsonPlayback.statusText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.teal)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)

                        HStack(spacing: 8) {
                            Button("Load") {
                                appModel.jsonPlayback.loadJSON(named: "bci_test_data")
                            }
                            .controlSize(.small)

                            Button(appModel.jsonPlayback.isPlaying ? "Playing" : "Play") {
                                appModel.jsonPlayback.startPlayback(interval: 0.35)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(appModel.jsonPlayback.isPlaying ? .green : DS.teal)
                            .controlSize(.small)

                            Button("Stop") {
                                appModel.jsonPlayback.stopPlayback()
                            }
                            .controlSize(.small)
                        }

                        HStack(spacing: 8) {
                            Text("Loaded: \(appModel.jsonPlayback.loadedCountText)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text("Arm: \(controller.activeArm.rawValue.capitalized)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Text("Vector: \(controller.motionVectorText)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
        }
        .frame(width: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - Bubble Progress Bar (head-anchored, bottom of view)

struct BubbleProgressBar: View {
    @Environment(AppModel.self) private var appModel

    private var controller: BubbleGameController {
        appModel.gameController
    }

    private var isPlaying: Bool {
        controller.sessionState == .playing
    }

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
