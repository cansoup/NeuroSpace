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

    private var poppedByType: [(BubbleType, Int)] {
        let popped = controller.bubbles.filter { $0.isPopped }
        return BubbleType.allCases.compactMap { type in
            let count = popped.filter { $0.type == type }.count
            return count > 0 ? (type, count) : nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 22)

            if canProceed {
                breakdownCard
                    .padding(.bottom, 14)

                stageScoreRow
                    .padding(.bottom, 18)
            } else {
                criteriaCard
                    .padding(.bottom, 18)

                stageScoreRow
                    .padding(.bottom, 18)
            }

            buttons
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 26)
        .frame(width: 400)
        .background(
            Color(red: 0.031, green: 0.055, blue: 0.110).opacity(0.85),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(
                    canProceed ? DS.teal.opacity(0.25) : DS.warning.opacity(0.30),
                    lineWidth: 1
                )
        )
        .onChange(of: appModel.shouldEndSession) { _, shouldEnd in
            guard shouldEnd else { return }
            dismissWindow(id: appModel.congratsWindowID)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 12) {
            if canProceed {
                NeuroLogoMark(size: 56)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(DS.warning)
            }

            VStack(spacing: 6) {
                Text(canProceed
                     ? "STAGE \(controller.currentStage) COMPLETE"
                     : "STAGE \(controller.currentStage) INCOMPLETE")
                    .font(DS.fontLabel)
                    .tracking(DS.labelTracking)
                    .foregroundStyle(DS.textTertiary)

                Text(canProceed ? "Stage Cleared!" : "Stage Not Cleared")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: canProceed ? [.white, DS.teal] : [.white, DS.warning],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
    }

    // MARK: Score breakdown card

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SCORE BREAKDOWN")
                .font(DS.fontLabel)
                .tracking(DS.labelTracking)
                .foregroundStyle(DS.textTertiary)

            VStack(spacing: 8) {
                ForEach(Array(poppedByType.enumerated()), id: \.offset) { _, item in
                    breakdownRow(type: item.0, count: item.1)
                }

                if poppedByType.isEmpty {
                    Text("No bubbles popped")
                        .font(DS.fontSmall)
                        .foregroundStyle(DS.textTertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.innerBg, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(DS.innerBorder, lineWidth: 1)
        )
    }

    private func breakdownRow(type: BubbleType, count: Int) -> some View {
        let color = bubbleColor(for: type)
        return HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.7), radius: 3)

            Text(type.displayName)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(DS.textSecondary)

            Text("×\(count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DS.textTertiary)

            Spacer()

            Text("+\(count * type.points)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private func bubbleColor(for type: BubbleType) -> Color {
        switch type {
        case .red:  return DS.bubbleRed
        case .blue: return DS.bubbleBlue
        }
    }

    // MARK: Criteria pill (failure case)

    private var criteriaCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("UNLOCK CRITERIA")
                .font(DS.fontLabel)
                .tracking(DS.labelTracking)
                .foregroundStyle(DS.textTertiary)

            Text(controller.unlockProgressText)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(DS.warning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(DS.warning.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: Stage Score row

    private var stageScoreRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("STAGE SCORE")
                .font(.system(size: 10, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(DS.textTertiary)

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(controller.score)")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(DS.teal)
                Text("pts")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .padding(.vertical, 10)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: Buttons

    @ViewBuilder
    private var buttons: some View {
        if canProceed {
            // Single full-width primary button
            primaryButton(
                label: controller.isOnFinalStage ? "Session Complete ✦" : "Next Stage →",
                gradient: controller.isOnFinalStage
                    ? [Color(hex: 0x9B7FEA).opacity(0.85), Color(hex: 0x785AC8).opacity(0.85)]
                    : [DS.teal.opacity(0.85), Color(hex: 0x00A078).opacity(0.85)],
                textColor: controller.isOnFinalStage ? .white : Color(hex: 0x001a12),
                glow: controller.isOnFinalStage ? DS.purple : DS.teal,
                action: primaryAction
            )
        } else {
            // Try Again (primary) + Go to Main (secondary)
            VStack(spacing: 10) {
                primaryButton(
                    label: "Try Again",
                    gradient: [DS.teal.opacity(0.85), Color(hex: 0x00A078).opacity(0.85)],
                    textColor: Color(hex: 0x001a12),
                    glow: DS.teal,
                    action: retryStage
                )

                Button(action: primaryAction) {
                    Text("Go to Main")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(DS.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func primaryButton(
        label: String,
        gradient: [Color],
        textColor: Color,
        glow: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .shadow(color: glow.opacity(0.25), radius: 12)
        }
        .buttonStyle(.plain)
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
