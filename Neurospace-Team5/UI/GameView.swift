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
            .tint(.purple)
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
                .tint(.purple)
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
        case .connected:    return .green
        case .connecting:   return .yellow
        case .disconnected: return .orange
        case .failed:       return .red
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
            }
        }
        .frame(width: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}
