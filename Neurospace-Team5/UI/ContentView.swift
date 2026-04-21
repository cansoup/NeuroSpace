import SwiftUI

private let accentTeal = Color(red: 0.18, green: 0.83, blue: 0.66)

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

            Image(systemName: "brain.head.profile")
                .font(.system(size: 52))
                .foregroundStyle(accentTeal.opacity(0.8))
                .shadow(color: accentTeal.opacity(0.4), radius: 12)

            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    Text("NEURO")
                        .foregroundStyle(.white)
                    Text("SPACE")
                        .foregroundStyle(accentTeal)
                }
                .font(.system(size: 26, weight: .black, design: .rounded))

                Text("NEURAL  REHAB  XR")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(3)
            }

            EEGWaveformView()
                .frame(height: 36)
                .padding(.horizontal, 20)

            HStack(spacing: 6) {
                Circle()
                    .fill(accentTeal)
                    .frame(width: 8, height: 8)
                Text("EEG LINKED")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(accentTeal)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(accentTeal.opacity(0.12), in: Capsule())

            HStack {
                Text("SIGNAL")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))

                Spacer()

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.1))
                        Capsule()
                            .fill(accentTeal)
                            .frame(width: geo.size.width * 0.87)
                    }
                }
                .frame(height: 6)

                Text("87%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(accentTeal)
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 8)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(accentTeal.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Center Column: Menu

    private var menuPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MENU")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(2)
                .padding(.leading, 4)

            menuButton(icon: "play.fill", label: "Start Session", isPrimary: true) {
                Task { @MainActor in
                    if appModel.immersiveSpaceState == .closed {
                        appModel.immersiveSpaceState = .inTransition
                        switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                        case .opened:
                            dismissWindow(id: appModel.mainWindowID)
                        case .userCancelled, .error:
                            fallthrough
                        @unknown default:
                            appModel.immersiveSpaceState = .closed
                        }
                    }
                }
            }
            .disabled(controller.sessionState == .playing || appModel.immersiveSpaceState == .inTransition)

            menuButton(icon: "books.vertical", label: "Training Library") {}
            menuButton(icon: "chart.line.uptrend.xyaxis", label: "My Progress") {}
            menuButton(icon: "gearshape", label: "Settings") {}

            Spacer(minLength: 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Last Session")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))

                Text("Stage 3/5  ·  240 pts  ·  4:12")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(accentTeal)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(accentTeal.opacity(0.15), lineWidth: 1)
            )
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(accentTeal.opacity(0.2), lineWidth: 1)
        )
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
                    .foregroundStyle(isPrimary ? accentTeal : .white.opacity(0.7))
                    .frame(width: 20)

                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isPrimary ? accentTeal : .white)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
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
            Text("TODAY'S GOAL")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(accentTeal)
                .tracking(2)

            goalRow(label: "Reach", value: "3", unit: "sessions")
            goalRow(label: "Duration", value: "15", unit: "min")
            goalRow(label: "Score", value: "500", unit: "pts")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(accentTeal.opacity(0.2), lineWidth: 1)
        )
    }

    private func goalRow(label: String, value: String, unit: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(accentTeal)
                Text(unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private var weeklyStreakPanel: some View {
        let days = ["M", "T", "W", "T", "F", "S", "S"]
        let filled = [true, true, true, true, false, false, false]

        return VStack(alignment: .leading, spacing: 12) {
            Text("WEEKLY STREAK")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(accentTeal)
                .tracking(2)

            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(filled[i] ? accentTeal : Color.white.opacity(0.08))
                            .frame(width: 22, height: 28)

                        Text(days[i])
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(filled[i] ? accentTeal : .white.opacity(0.3))
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(accentTeal.opacity(0.2), lineWidth: 1)
        )
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
