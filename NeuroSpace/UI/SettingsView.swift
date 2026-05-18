import SwiftUI

private let accent = DS.teal

// MARK: - Tabs

private enum SettingsTab: String, CaseIterable, Identifiable {
    case debug, immersive, about

    var id: String { rawValue }

    var label: String {
        switch self {
        case .debug:     return "Debug"
        case .immersive: return "Immersive"
        case .about:     return "About"
        }
    }

    var icon: String {
        switch self {
        case .debug:     return "⬡"
        case .immersive: return "✦"
        case .about:     return "◇"
        }
    }
}

// MARK: - Local UI state (placeholders, not wired to AppModel)

@Observable
private final class SettingsState {
    // Debug (note: debugMode lives on AppModel so it can be observed across views)
    var autoPlayJson: Bool = false
    var loopJson: Bool = false

    // Immersive (note: `environment` lives on AppModel)
    var hudPos: String = "top"
    var hudScale: String = "md"
}

// MARK: - Main view

struct SettingsView: View {
    let onBack: () -> Void

    @Environment(AppModel.self) private var appModel
    @State private var selectedTab: SettingsTab = .debug
    @State private var settings = SettingsState()

    var body: some View {
        VStack(spacing: 14) {
            header

            HStack(alignment: .top, spacing: 14) {
                sidebar.frame(width: 200)
                contentArea
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            NeuroLogoMark(size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text("Settings")
                    .font(DS.fontH2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("NEUROSPACE  ·  CONFIGURATION")
                    .font(DS.fontMeta)
                    .tracking(DS.metaTracking)
                    .foregroundStyle(DS.textTertiary)
            }

            Spacer()

            EEGStatusPill()

            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Back")
                        .font(DS.fontButtonSm)
                }
                .foregroundStyle(DS.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.05), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .dwellable(
                appModel.dwellModeEnabled,
                duration: appModel.dwellDuration,
                cornerRadius: 999,
                action: onBack
            )
        }
    }

    

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Navigation", color: DS.textTertiary)
                .padding(.bottom, 12)

            VStack(spacing: 3) {
                ForEach(SettingsTab.allCases) { tab in
                    NavRow(
                        tab: tab,
                        isActive: tab == selectedTab,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = tab
                            }
                        }
                    )
                }
            }

            Spacer()

            Text("v0.9.2  ·  build 142")
                .font(DS.fontLabel)
                .tracking(0.7)
                .foregroundStyle(DS.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .frame(maxHeight: .infinity)
        .tealGlassCard()
    }

    // MARK: Content

    private var contentArea: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(selectedTab.label)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(DS.textPrimary)

            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    switch selectedTab {
                    case .debug:     DebugPanel(s: settings)
                    case .immersive: ImmersivePanel(s: settings)
                    case .about:     AboutPanel()
                    }
                }
                .padding(.trailing, 4)
                .id(selectedTab)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Sidebar nav row

private struct NavRow: View {
    let tab: SettingsTab
    let isActive: Bool
    let onTap: () -> Void

    @Environment(AppModel.self) private var appModel
    @State private var hover = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text(tab.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isActive ? accent : DS.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(
                        isActive ? accent.opacity(0.18) : Color.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isActive ? accent.opacity(0.35) : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                    )

                Text(tab.label)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(isActive ? accent : DS.textSecondary)

                Spacer()

                if isActive {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isActive ? accent.opacity(0.12) : (hover ? Color.white.opacity(0.05) : .clear),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isActive ? accent.opacity(0.35) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .onHover { hover = $0 }
        .dwellable(
            appModel.dwellModeEnabled,
            duration: appModel.dwellDuration,
            cornerRadius: 12,
            action: onTap
        )
    }
}

// MARK: - Reusable controls

private struct ToggleSwitch: View {
    @Binding var value: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { value.toggle() }
        } label: {
            ZStack(alignment: value ? .trailing : .leading) {
                Capsule()
                    .fill(value ? accent.opacity(0.25) : Color.white.opacity(0.08))
                    .frame(width: 46, height: 26)
                    .overlay(
                        Capsule().strokeBorder(
                            value ? accent.opacity(0.55) : Color.white.opacity(0.15),
                            lineWidth: 1
                        )
                    )

                Circle()
                    .fill(value ? accent : Color.white.opacity(0.35))
                    .frame(width: 18, height: 18)
                    .padding(.horizontal, 4)
                    .shadow(color: value ? accent.opacity(0.5) : .clear, radius: 4)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SettingSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...100
    var step: Double = 1
    var unit: String = "%"

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: $value, in: range, step: step)
                .tint(accent)
                .frame(width: 140)

            Text("\(Int(value))\(unit)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(accent)
                .frame(width: 38, alignment: .trailing)
        }
    }
}

private struct ChipOption: Identifiable, Hashable {
    let value: String
    let label: String
    var id: String { value }
}

private struct ChipGroupView: View {
    @Binding var value: String
    let options: [ChipOption]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options) { opt in
                let selected = opt.value == value
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { value = opt.value }
                } label: {
                    Text(opt.label)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(selected ? accent : DS.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            selected ? accent.opacity(0.16) : Color.white.opacity(0.05),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                selected ? accent.opacity(0.45) : Color.white.opacity(0.10),
                                lineWidth: 1
                            )
                        )
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
            }
        }
    }
}

private struct SettingRowView<Control: View>: View {
    let icon: String
    let label: String
    var desc: String? = nil
    var divider: Bool = true
    @ViewBuilder let control: () -> Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(icon)
                    .font(.system(size: 15))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.textPrimary)
                    if let desc {
                        Text(desc)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 12)

                control()
            }
            .padding(.vertical, 13)

            if divider {
                Divider().background(Color.white.opacity(0.05))
            }
        }
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: title, color: DS.textTertiary)
                .padding(.bottom, 12)
            content()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tealGlassCard()
    }
}

// MARK: - Panels

private struct DebugPanel: View {
    @Bindable var s: SettingsState
    @Environment(AppModel.self) private var appModel

    private var controller: BubbleGameController { appModel.gameController }

    var body: some View {
        @Bindable var appModel = appModel
        VStack(spacing: 12) {
            SectionCard(title: "Accessibility") {
                SettingRowView(
                    icon: "◉",
                    label: "Dwell Mode",
                    desc: "Click buttons by holding your gaze on them. For users who cannot use hand gestures.",
                    divider: false
                ) {
                    ToggleSwitch(value: $appModel.dwellModeEnabled)
                }
            }

            SectionCard(title: "Debug Mode") {
                SettingRowView(icon: "⬡", label: "Enable Debug Mode", desc: "Show arm coordinates, EEG signal, collision data", divider: false) {
                    ToggleSwitch(value: $appModel.debugMode)
                }
            }

            SectionCard(title: "JSON Playback") {
                SettingRowView(icon: "▶", label: "Auto-Play on Start", desc: "Load last JSON file automatically") {
                    ToggleSwitch(value: $s.autoPlayJson)
                }
                SettingRowView(icon: "◎", label: "Loop Playback", desc: "Repeat JSON sequence continuously", divider: false) {
                    ToggleSwitch(value: $s.loopJson)
                }
            }

            if appModel.debugMode {
                liveDebugOutput
            }
        }
    }

    private var liveDebugOutput: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: "Live Debug Output", color: DS.textTertiary)

            debugSubsection("Arm Debug") {
                VStack(spacing: 8) {
                    debugLine("Left Tip", controller.leftTipText)
                    debugLine("Right Tip", controller.rightTipText)
                    debugLine("Motion Vector", controller.motionVectorText)
                    debugLine("Active Bubble", controller.activeBubbleText)
                }
            }

            debugSubsection("Session") {
                VStack(spacing: 8) {
                    debugLine("State", controller.sessionState.rawValue.capitalized)
                    debugLine("Intent", controller.currentIntent.rawValue)
                    debugLine("Active Arm", controller.activeArm.rawValue.capitalized)
                    debugLine("Score", "\(controller.score)")
                    debugLine("Stage", "\(controller.currentStage)/\(StageConfig.totalStages)")
                    debugLine("EEG", controller.connectionState.displayText)
                }
            }

            debugSubsection("Arm Selection") {
                HStack(spacing: 8) {
                    debugChipButton("Left Arm", isActive: controller.activeArm == .left) {
                        controller.setActiveArm(.left)
                    }
                    debugChipButton("Right Arm", isActive: controller.activeArm == .right) {
                        controller.setActiveArm(.right)
                    }
                }
            }

            debugSubsection("Movement") {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        debugMiniButton("←") { controller.applyIntent(.moveLeft) }
                        debugMiniButton("→") { controller.applyIntent(.moveRight) }
                        debugMiniButton("↑") { controller.applyIntent(.moveUp) }
                        debugMiniButton("↓") { controller.applyIntent(.moveDown) }
                    }
                    HStack(spacing: 6) {
                        debugMiniButton("Fwd") { controller.applyIntent(.moveForward) }
                        debugMiniButton("Bwd") { controller.applyIntent(.moveBackward) }
                        debugMiniButton("Idle") { controller.applyIntent(.idle) }
                    }
                }
            }

            debugSubsection("JSON Playback") {
                HStack(spacing: 6) {
                    debugMiniButton("Load") {
                        appModel.jsonPlayback.loadJSON(named: "bci_test_data")
                    }
                    debugChipButton("Play", isActive: appModel.jsonPlayback.isPlaying) {
                        appModel.jsonPlayback.startPlayback(interval: 0.35)
                    }
                    debugMiniButton("Stop") {
                        appModel.jsonPlayback.stopPlayback()
                    }
                }
            }

            debugSubsection("Actions") {
                HStack(spacing: 6) {
                    Button("Reset Game") {
                        controller.resetGame()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red.opacity(0.7))
                    .controlSize(.small)

                    Button("Clear History") {
                        appModel.sessionStore.clearAll()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red.opacity(0.7))
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.innerBg, in: RoundedRectangle(cornerRadius: DS.radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMd)
                .strokeBorder(DS.innerBorder, lineWidth: 1)
        )
    }

    private func debugSubsection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(DS.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(DS.textTertiary)
            content()
        }
    }

    private func debugLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(DS.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DS.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func debugChipButton(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .tint(isActive ? accent : .gray.opacity(0.5))
            .controlSize(.small)
    }

    private func debugMiniButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }
}

private struct ImmersivePanel: View {
    @Bindable var s: SettingsState
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(spacing: 12) {
            SectionCard(title: "Immersive Environment") {
                Text("Choose the background environment displayed during gameplay in immersive mode.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(DS.textTertiary)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(EnvironmentChoice.allCases) { env in
                        envCard(env)
                    }
                }
            }

            SectionCard(title: "Window Layout") {
                SettingRowView(icon: "⊹", label: "HUD Position", desc: "Floating overlay alignment") {
                    ChipGroupView(value: $s.hudPos, options: [
                        .init(value: "top", label: "Top"),
                        .init(value: "center", label: "Center"),
                        .init(value: "bottom", label: "Bottom")
                    ])
                }
                SettingRowView(icon: "◎", label: "HUD Scale", desc: "Interface element size", divider: false) {
                    ChipGroupView(value: $s.hudScale, options: [
                        .init(value: "sm", label: "S"),
                        .init(value: "md", label: "M"),
                        .init(value: "lg", label: "L")
                    ])
                }
            }

            SectionCard(title: "Cursor") {
                @Bindable var appModel = appModel
                SettingRowView(
                    icon: "◎",
                    label: "Show Cursor",
                    desc: "Display the gaze dot during gameplay. Disable for a cleaner experience — bubbles still highlight and EEG targeting works normally.",
                    divider: false
                ) {
                    ToggleSwitch(value: $appModel.showCursor)
                }
            }
        }
        .onAppear { openPreviewImmersive() }
        .onDisappear { dismissPreviewImmersive() }
        .onChange(of: appModel.selectedEnvironment) { _, newEnv in
            if newEnv == .none {
                dismissPreviewImmersive()
            } else {
                openPreviewImmersive()
            }
        }
    }

    private func openPreviewImmersive() {
        Task { @MainActor in
            guard !appModel.isPreviewingEnvironment,
                  appModel.immersiveSpaceState == .closed,
                  appModel.selectedEnvironment != .none else { return }
            appModel.isPreviewingEnvironment = true
            switch await openImmersiveSpace(id: appModel.lobbySkyboxID) {
            case .opened:
                break
            case .userCancelled, .error:
                fallthrough
            @unknown default:
                appModel.isPreviewingEnvironment = false
            }
        }
    }

    private func dismissPreviewImmersive() {
        Task { @MainActor in
            guard appModel.isPreviewingEnvironment else { return }
            await dismissImmersiveSpace()
            appModel.isPreviewingEnvironment = false
        }
    }

    private func envCard(_ env: EnvironmentChoice) -> some View {
        let selected = appModel.selectedEnvironment == env
        let (c1, c2) = env.swatchHex

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                appModel.selectedEnvironment = env
            }
        } label: {
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    LinearGradient(
                        colors: [Color(hex: c1), Color(hex: c2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: 52)
                    .overlay(
                        Text(env.icon)
                            .font(.system(size: 20))
                            .foregroundStyle(selected ? accent : Color.white.opacity(0.4))
                    )

                    if selected {
                        Circle()
                            .fill(accent)
                            .frame(width: 8, height: 8)
                            .shadow(color: accent.opacity(0.7), radius: 4)
                            .padding(6)
                    }
                }

                Text(env.label)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(selected ? accent : DS.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(selected ? accent.opacity(0.10) : Color.white.opacity(0.03))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        selected ? accent.opacity(0.55) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .shadow(color: selected ? accent.opacity(0.2) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
    }
}

private struct AboutPanel: View {
    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 16) {
                NeuroLogoMark(size: 56)

                VStack(spacing: 4) {
                    Text("NEUROSPACE")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("BCI  ·  BUBBLE POP")
                        .font(DS.fontMeta)
                        .tracking(DS.metaTracking)
                        .foregroundStyle(DS.textTertiary)
                }

                VStack(spacing: 2) {
                    Text("Version 0.9.2 (build 142)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DS.textSecondary)
                    Text("visionOS 2.0+")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(DS.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .tealGlassCard()

            SectionCard(title: "Team") {
                aboutRow("Research", "Neural Rehabilitation Lab", divider: true)
                aboutRow("Platform", "visionOS / RealityKit", divider: true)
                aboutRow("Input", "EEG BCI Interface", divider: false)
            }
        }
    }

    private func aboutRow(_ label: String, _ value: String, divider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(DS.textTertiary)
                Spacer()
                Text(value)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(DS.textPrimary)
            }
            .padding(.vertical, 9)

            if divider {
                Divider().background(Color.white.opacity(0.05))
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    SettingsView(onBack: {})
        .environment(AppModel())
        .frame(width: 1100, height: 560)
}
