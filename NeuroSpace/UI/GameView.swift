//
//  GameView.swift
//  NeuroSpace
//

import SwiftUI

// MARK: - Congratulations Window

struct CongratsView: View {
    @Environment(AppModel.self) private var appModel

    private var controller: BubbleGameController { appModel.gameController }

    private var passed: Bool {
        controller.meetsUnlockCriteria
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

            if passed {
                breakdownCard
                    .padding(.bottom, 14)
            } else {
                criteriaCard
                    .padding(.bottom, 14)
            }

            stageScoreRow
                .padding(.bottom, 20)

            bubblePrompt
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 26)
        .frame(width: 360)
        .background(
            Color(hex: 0x080E1C, alpha: 0.75),
            in: RoundedRectangle(cornerRadius: DS.radiusXl)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXl)
                .strokeBorder(
                    passed ? DS.teal.opacity(0.25) : DS.warning.opacity(0.30),
                    lineWidth: 1
                )
        )
        .onChange(of: appModel.shouldEndSession) { _, shouldEnd in
            guard shouldEnd else { return }
            appModel.stageEndResult = .none
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 12) {
            if passed {
                NeuroLogoMark(size: 56)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(DS.warning)
            }

            VStack(spacing: 6) {
                Text(passed
                     ? "STAGE \(controller.currentStage) COMPLETE"
                     : "STAGE \(controller.currentStage) INCOMPLETE")
                    .font(DS.fontLabel)
                    .tracking(DS.labelTracking)
                    .foregroundStyle(DS.textTertiary)

                Text(passed ? "Stage Cleared!" : "Stage Not Cleared")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: passed ? [.white, DS.teal] : [.white, DS.warning],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            EEGStatusPill()
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
        .background(Color(hex: 0x080E1C, alpha: 0.75), in: RoundedRectangle(cornerRadius: DS.radiusXl))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXl)
                .strokeBorder(DS.teal.opacity(0.2), lineWidth: 1)
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

    // MARK: Criteria card (incomplete stage)

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

    // MARK: Bubble prompt

    private var bubblePrompt: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye")
                .font(.system(size: 12))
                .foregroundStyle(DS.teal)
            Text("Look at a bubble to make your choice")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(DS.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(DS.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(DS.teal.opacity(0.20), lineWidth: 1)
        )
    }
}

// MARK: - Mission Failed Window

struct MissionFailedView: View {
    @Environment(AppModel.self) private var appModel

    private var controller: BubbleGameController { appModel.gameController }

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

            breakdownCard
                .padding(.bottom, 14)

            stageScoreRow
                .padding(.bottom, 20)

            bubblePrompt
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 26)
        .frame(width: 360)
        .background(
            Color(hex: 0x080E1C, alpha: 0.75),
            in: RoundedRectangle(cornerRadius: DS.radiusXl)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXl)
                .strokeBorder(DS.error.opacity(0.30), lineWidth: 1)
        )
        .onChange(of: appModel.shouldEndSession) { _, shouldEnd in
            guard shouldEnd else { return }
            appModel.stageEndResult = .none
        }
        .onChange(of: appModel.gameController.sessionState) { _, newState in
            if newState != .finished {
                appModel.stageEndResult = .none
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(DS.error)
                .shadow(color: DS.error.opacity(0.4), radius: 12)

            VStack(spacing: 6) {
                Text("STAGE \(controller.currentStage)  ·  TIME UP")
                    .font(DS.fontLabel)
                    .tracking(DS.labelTracking)
                    .foregroundStyle(DS.textTertiary)

                Text("Mission Failed")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, DS.error],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Better luck next time.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(DS.textTertiary)
                    .padding(.top, 2)
            }

            EEGStatusPill()
        }
    }

    // MARK: Score breakdown

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
        .background(Color(hex: 0x080E1C, alpha: 0.75), in: RoundedRectangle(cornerRadius: DS.radiusXl))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXl)
                .strokeBorder(DS.teal.opacity(0.2), lineWidth: 1)
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
                    .foregroundStyle(DS.error)
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

    // MARK: Bubble prompt

    private var bubblePrompt: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye")
                .font(.system(size: 12))
                .foregroundStyle(DS.warning)
            Text("Look at a bubble to make your choice")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(DS.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(DS.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(DS.warning.opacity(0.20), lineWidth: 1)
        )
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

    private var eegColor: Color { appModel.bciClient.state.tint }
    private var eegLabel: String { appModel.bciClient.state.displayText }

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

                    Text(eegLabel)
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
        .background(Color(hex: 0x080E1C, alpha: 0.75), in: RoundedRectangle(cornerRadius: DS.radiusXl))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXl)
                .strokeBorder(DS.teal.opacity(0.2), lineWidth: 1)
        )
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
            .background(Color(hex: 0x080E1C, alpha: 0.75), in: RoundedRectangle(cornerRadius: DS.radiusXl))
            .overlay(
                RoundedRectangle(cornerRadius: DS.radiusXl)
                    .strokeBorder(DS.teal.opacity(0.2), lineWidth: 1)
            )
            .transition(.opacity)
        }
    }
}
