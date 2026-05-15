import SwiftUI

private let accentTeal = DS.teal

enum LobbyScreen {
    case lobby
    case progress
    case settings
}

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @State private var screen: LobbyScreen = .lobby

    var body: some View {
        Group {
            if !appModel.hasCompletedOnboarding {
                OnboardingView(onContinue: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        appModel.hasCompletedOnboarding = true
                    }
                })
            } else {
                switch screen {
                case .lobby:
                    LobbyView(screen: $screen)
                case .progress:
                    MyProgressView(onBack: backToLobby)
                case .settings:
                    SettingsView(onBack: backToLobby)
                }
            }
        }
        .frame(width: 1100, height: 560)
    }

    private func backToLobby() {
        withAnimation(.easeInOut(duration: 0.25)) {
            screen = .lobby
        }
    }
}

struct LobbyView: View {
    @Binding var screen: LobbyScreen

    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

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
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    if controller.sessionState == .finished || controller.sessionState == .idle {
                        controller.resetGame()
                    }

                    if appModel.immersiveSpaceState == .closed {
                        appModel.immersiveSpaceState = .inTransition

                        switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                        case .opened:
                            appModel.immersiveSpaceState = .open
                            controller.beginCalibration()
                            dismissWindow(id: appModel.mainWindowID)

                        case .userCancelled, .error:
                            fallthrough

                        @unknown default:
                            appModel.immersiveSpaceState = .closed
                        }
                    } else if appModel.immersiveSpaceState == .open {
                        controller.beginCalibration()
                        dismissWindow(id: appModel.mainWindowID)
                    }
                }
            }
            .disabled(
                controller.sessionState == .playing ||
                controller.sessionState == .calibrating ||
                appModel.immersiveSpaceState == .inTransition
            )

            menuButton(icon: "chart.line.uptrend.xyaxis", label: "My Progress") {
                withAnimation(.easeInOut(duration: 0.25)) {
                    screen = .progress
                }
            }
            menuButton(icon: "gearshape", label: "Settings") {
                withAnimation(.easeInOut(duration: 0.25)) {
                    screen = .settings
                }
            }

            Spacer(minLength: 4)

            if let last = appModel.sessionStore.lastSession {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last Session")
                        .font(DS.fontBody)
                        .foregroundStyle(DS.textSecondary)

                    Text("Stage \(last.stageReached)/\(last.totalStages)  ·  \(last.score) pts  ·  \(last.formattedDuration)")
                        .font(DS.fontData)
                        .foregroundStyle(DS.teal)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(radius: DS.radiusMd, border: DS.teal.opacity(0.15))
            }
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
        .hoverEffect(.highlight)
        .dwellable(
            appModel.dwellModeEnabled,
            duration: appModel.dwellDuration,
            cornerRadius: 14,
            action: action
        )
    }

    // MARK: - Right Column: Stats

    private var todaysGoalPanel: some View {
        let store = appModel.sessionStore
        return VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Today's Progress", color: DS.teal)

            goalRow(label: "Sessions", value: "\(store.todayCount)", unit: "done")
            goalRow(label: "Duration", value: "\(store.todayTotalSeconds / 60)", unit: "min")
            goalRow(label: "Score", value: "\(store.todayTotalScore)", unit: "pts")
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
        let filled = appModel.sessionStore.weeklyDays

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
