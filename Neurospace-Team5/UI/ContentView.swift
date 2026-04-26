import SwiftUI

private let accentTeal = DS.teal

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        LobbyView()
            .frame(width: 1100, height: 560)
    }
}

struct LobbyView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var skyboxOpen = false
    @State private var showDebug = false

    private var controller: BubbleGameController { appModel.gameController }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            brandPanel
                .frame(width: 280)

            menuPanel
                .frame(width: 300)

            VStack(spacing: 16) {
                todaysGoalPanel
                weeklyStreakPanel
            }
            .frame(width: 240)

            if showDebug {
                debugPanel
                    .frame(width: 300)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            guard !skyboxOpen else { return }
            skyboxOpen = true
            await openImmersiveSpace(id: appModel.lobbySkyboxID)
        }
    }

    // MARK: - Left Column: Brand + EEG Status

    private var brandPanel: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)

            NeuroLogoMark(size: 64)

            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    Text("NEURO")
                        .foregroundStyle(DS.textPrimary)
                    Text("SPACE")
                        .foregroundStyle(DS.teal)
                }
                .font(DS.fontH2)
                .tracking(DS.heroTracking)

                Text("NEURAL  REHAB  XR")
                    .font(DS.fontMeta)
                    .foregroundStyle(DS.textTertiary)
                    .tracking(DS.labelTracking)
            }

            EEGWaveformView()
                .frame(height: 36)
                .padding(.horizontal, 20)

            HStack(spacing: 6) {
                Circle()
                    .fill(accentTeal)
                    .frame(width: 8, height: 8)
                Text("EEG LINKED")
                    .font(DS.fontMeta)
                    .foregroundStyle(DS.teal)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(accentTeal.opacity(0.12), in: Capsule())

            HStack {
                Text("SIGNAL")
                    .font(DS.fontMeta)
                    .tracking(DS.metaTracking)
                    .foregroundStyle(DS.textSecondary)

                Spacer()

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.1))
                        Capsule()
                            .fill(DS.teal)
                            .frame(width: geo.size.width * 0.87)
                    }
                }
                .frame(height: 6)

                Text("87%")
                    .font(DS.fontMeta)
                    .foregroundStyle(DS.teal)
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 8)
        }
        .padding(20)
        .tealGlassCard()
    }

    // MARK: - Center Column: Menu

    private var menuPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Menu", color: DS.textSecondary)
                .padding(.leading, 4)

            menuButton(icon: "play.fill", label: "Start Session", isPrimary: true) {
                Task { @MainActor in
                    if skyboxOpen {
                        await dismissImmersiveSpace()
                        skyboxOpen = false
                    }

                    if controller.sessionState == .finished || controller.sessionState == .idle {
                        controller.resetGame()
                    }

                    if appModel.immersiveSpaceState == .closed {
                        appModel.immersiveSpaceState = .inTransition

                        switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                        case .opened:
                            appModel.immersiveSpaceState = .open
                            controller.startSession()
                            dismissWindow(id: appModel.mainWindowID)

                        case .userCancelled, .error:
                            fallthrough

                        @unknown default:
                            appModel.immersiveSpaceState = .closed
                        }
                    } else if appModel.immersiveSpaceState == .open {
                        controller.startSession()
                        dismissWindow(id: appModel.mainWindowID)
                    }
                }
            }
            .disabled(controller.sessionState == .playing || appModel.immersiveSpaceState == .inTransition)

            menuButton(icon: "books.vertical", label: "Training Library") {}
            menuButton(icon: "chart.line.uptrend.xyaxis", label: "My Progress") {}
            menuButton(icon: "gearshape", label: "Settings") {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showDebug.toggle()
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Last Session")
                    .font(DS.fontBody)
                    .foregroundStyle(DS.textSecondary)

                Text("Stage 3/5  ·  240 pts  ·  4:12")
                    .font(DS.fontData)
                    .foregroundStyle(DS.teal)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: DS.radiusMd, border: DS.teal.opacity(0.15))
        }
        .padding(20)
        .tealGlassCard()
    }

    private func menuButton(
        icon: String,
        label: String,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isPrimary ? DS.teal : DS.textSecondary)
                    .frame(width: 20)

                Text(label)
                    .font(DS.fontButtonSm)
                    .foregroundStyle(isPrimary ? DS.teal : DS.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                isPrimary
                    ? accentTeal.opacity(0.12)
                    : Color.white.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isPrimary ? accentTeal.opacity(0.4) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right Column: Stats

    private var todaysGoalPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Today's Goal", color: DS.teal)

            goalRow(label: "Reach", value: "3", unit: "sessions")
            goalRow(label: "Duration", value: "15", unit: "min")
            goalRow(label: "Score", value: "500", unit: "pts")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tealGlassCard()
    }

    private func goalRow(label: String, value: String, unit: String) -> some View {
        HStack {
            Text(label)
                .font(DS.fontBody)
                .foregroundStyle(DS.textSecondary)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(DS.fontH3)
                    .foregroundStyle(DS.teal)
                Text(unit)
                    .font(DS.fontSmall)
                    .foregroundStyle(DS.textTertiary)
            }
        }
    }

    private var weeklyStreakPanel: some View {
        let days = ["M", "T", "W", "T", "F", "S", "S"]
        let filled = [true, true, true, true, false, false, false]

        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Weekly Streak", color: DS.teal)

            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(filled[i] ? accentTeal : Color.white.opacity(0.08))
                            .frame(width: 22, height: 28)

                        Text(days[i])
                            .font(DS.fontLabel)
                            .foregroundStyle(filled[i] ? DS.teal : DS.textTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tealGlassCard()
    }

    // MARK: - Debug Panel

    private var debugPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                debugHeader

                debugSection("Arm Debug") {
                    debugRow("Left Tip", controller.leftTipText)
                    debugRow("Right Tip", controller.rightTipText)
                    debugRow("Motion Vector", controller.motionVectorText)
                    debugRow("Active Bubble", controller.activeBubbleText)
                }

                debugSection("Session") {
                    debugRow("State", controller.sessionState.rawValue.capitalized)
                    debugRow("Intent", controller.currentIntent.rawValue)
                    debugRow("Active Arm", controller.activeArm.rawValue.capitalized)
                    debugRow("Score", "\(controller.score)")
                    debugRow("Stage", "\(controller.currentStage)/\(StageConfig.totalStages)")
                    debugRow("EEG", controller.connectionState.displayText)
                }

                debugSection("Arm Selection") {
                    HStack(spacing: 8) {
                        debugActionButton("Left Arm", isActive: controller.activeArm == .left) {
                            controller.setActiveArm(.left)
                        }
                        debugActionButton("Right Arm", isActive: controller.activeArm == .right) {
                            controller.setActiveArm(.right)
                        }
                    }
                }

                debugSection("Movement") {
                    HStack(spacing: 6) {
                        debugSmallButton("←") { controller.applyIntent(.moveLeft) }
                        debugSmallButton("→") { controller.applyIntent(.moveRight) }
                        debugSmallButton("↑") { controller.applyIntent(.moveUp) }
                        debugSmallButton("↓") { controller.applyIntent(.moveDown) }
                    }
                    HStack(spacing: 6) {
                        debugSmallButton("Fwd") { controller.applyIntent(.moveForward) }
                        debugSmallButton("Bwd") { controller.applyIntent(.moveBackward) }
                        debugSmallButton("Idle") { controller.applyIntent(.idle) }
                    }
                }

                debugSection("JSON Playback") {
                    HStack(spacing: 6) {
                        debugSmallButton("Load") {
                            appModel.jsonPlayback.loadJSON(named: "bci_test_data")
                        }
                        debugActionButton("Play", isActive: appModel.jsonPlayback.isPlaying) {
                            appModel.jsonPlayback.startPlayback(interval: 0.35)
                        }
                        debugSmallButton("Stop") {
                            appModel.jsonPlayback.stopPlayback()
                        }
                    }
                    HStack(spacing: 6) {
                        Button("Reset Game") {
                            controller.resetGame()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red.opacity(0.7))
                        .controlSize(.small)
                    }
                }
            }
            .padding(18)
        }
        .tealGlassCard()
    }

    private var debugHeader: some View {
        HStack {
            SectionLabel(text: "Debug", color: DS.teal)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showDebug = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    private func debugSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title, color: DS.textTertiary)

            content()
        }
    }

    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(DS.fontSmall)
                .foregroundStyle(DS.textSecondary)
            Spacer()
            Text(value)
                .font(DS.fontSmall)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func debugActionButton(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .tint(isActive ? accentTeal : .gray.opacity(0.5))
            .controlSize(.small)
    }

    private func debugSmallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }
}

// MARK: - Neuro Logo Mark

struct NeuroLogoMark: View {
    let size: CGFloat
    @State private var rotation: Double = 0
    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(accentTeal.opacity(0.5), lineWidth: 1.5)
                .frame(width: size, height: size)

            Circle()
                .strokeBorder(accentTeal.opacity(0.3), lineWidth: 1)
                .frame(width: size * 0.65, height: size * 0.65)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [accentTeal, accentTeal.opacity(0.4)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.18
                    )
                )
                .frame(width: size * 0.28, height: size * 0.28)
                .shadow(color: accentTeal, radius: pulse ? 14 : 8)
                .scaleEffect(pulse ? 1.08 : 1.0)

            Circle()
                .trim(from: 0, to: 0.2)
                .stroke(accentTeal.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: size * 0.85, height: size * 0.85)
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 3).repeatForever()) {
                pulse = true
            }
        }
    }
}

// MARK: - EEG Waveform

struct EEGWaveformView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { context, size in
                let midY = size.height / 2
                var path = Path()
                path.move(to: CGPoint(x: 0, y: midY))
                for x in stride(from: 0, to: size.width, by: 1) {
                    let norm = x / size.width
                    let y = midY + sin(norm * .pi * 4 + phase) * midY * 0.6
                        * (1 - abs(norm - 0.5) * 1.2)
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                context.stroke(path, with: .color(accentTeal.opacity(0.7)), lineWidth: 1.5)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
