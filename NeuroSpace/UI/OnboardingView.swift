import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var appModel
    let onContinue: () -> Void

    @State private var portText: String = ""

    private var host: String { appModel.bciHost }
    private var port: Int { Int(portText) ?? appModel.bciPort }

    private var isConnected: Bool { appModel.isEEGConnected }
    private var isConnecting: Bool {
        if case .connecting = appModel.bciClient.state { return true }
        return false
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                    .padding(.bottom, 22)

                titleBlock
                    .padding(.bottom, 24)

                illustrationCard
                    .padding(.bottom, 18)

                connectTile
                    .padding(.bottom, isConnected ? 14 : 20)

                if isConnected {
                    BCILiveStreamView()
                        .padding(.bottom, 18)
                }

                footer
            }
            .padding(EdgeInsets(top: 36, leading: 42, bottom: 32, trailing: 42))
            .frame(width: 560)
            .tealGlassCard()
            .shadow(color: .black.opacity(0.55), radius: 30, y: 20)
            .shadow(color: DS.teal.opacity(0.08), radius: 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { portText = "\(appModel.bciPort)" }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            NeuroLogoMark(size: 28)
            Text("NEUROSPACE  ·  WELCOME")
                .font(DS.fontLabel)
                .tracking(DS.labelTracking)
                .foregroundStyle(DS.textTertiary)
            Spacer()
            RoundedRectangle(cornerRadius: 3)
                .fill(DS.teal)
                .frame(width: 20, height: 3)
                .shadow(color: DS.teal.opacity(0.7), radius: 4)
        }
    }

    // MARK: - Title

    private var titleBlock: some View {
        VStack(spacing: 8) {
            SectionLabel(text: "Welcome", color: DS.textTertiary)

            Text("Welcome to Neurospace")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, DS.teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.top, 4)

            (Text("Pop bubbles using ")
                + Text("your mind").foregroundColor(DS.teal).fontWeight(.semibold)
                + Text(" — no hand gestures required."))
                .font(DS.fontBody)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
    }

    // MARK: - Illustration card (brain + EEG wave)

    private var illustrationCard: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [DS.teal.opacity(0.18), .clear],
                    center: .center, startRadius: 0, endRadius: 70
                ))
                .frame(width: 140, height: 140)
                .offset(x: -180, y: -50)

            Circle()
                .fill(RadialGradient(
                    colors: [DS.purple.opacity(0.14), .clear],
                    center: .center, startRadius: 0, endRadius: 70
                ))
                .frame(width: 140, height: 140)
                .offset(x: 180, y: 50)

            HStack(spacing: 18) {
                BrainGlyph(size: 88, active: isConnected)
                EEGWaveformView()
                    .frame(width: 280, height: 68)
                    .opacity(isConnected ? 1.0 : 0.45)
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .background(DS.teal.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(DS.teal.opacity(0.15), lineWidth: 1)
        )
        .clipped()
    }

    // MARK: - Connect tile

    private var connectTile: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(DS.teal.opacity(0.12))
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(DS.teal.opacity(0.30), lineWidth: 1)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(DS.teal)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect your EEG headset")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.textPrimary)
                    Text(connectSubtitle)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                statusControl
            }

            HStack(spacing: 8) {
                hostField
                portField
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var hostField: some View {
        @Bindable var appModel = appModel
        return HStack(spacing: 6) {
            Text("HOST")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(DS.textTertiary)
            TextField("192.168.x.y", text: $appModel.bciHost)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(DS.textPrimary)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .disabled(isConnecting)
                .onSubmit { connect() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var portField: some View {
        HStack(spacing: 6) {
            Text("PORT")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(DS.textTertiary)
            TextField("8765", text: $portText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(DS.textPrimary)
                .autocorrectionDisabled(true)
                .keyboardType(.numberPad)
                .disabled(isConnecting)
                .onSubmit { connect() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 130)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var connectSubtitle: String {
        switch appModel.bciClient.state {
        case .connected:
            return "Receiving predictions from \(host):\(port)"
        case .connecting:
            return "Connecting to \(host):\(port)…"
        case .failed(let msg):
            return "Failed: \(msg)"
        case .disconnected:
            return "Enter the bridge_server IP and tap Connect"
        }
    }

    @ViewBuilder
    private var statusControl: some View {
        switch appModel.bciClient.state {
        case .connected:
            StatusPillView(kind: .success, text: "Connected")
        case .connecting:
            StatusPillView(kind: .info, text: "Connecting…")
        case .failed:
            Button(action: connect) {
                StatusPillView(kind: .warn, text: "Retry")
            }
            .buttonStyle(.plain)
        case .disconnected:
            Button(action: connect) {
                StatusPillView(kind: .info, text: "Connect")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: isConnected ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isConnected ? DS.success : DS.textTertiary)
                Text(isConnected ? "ALL DEVICES READY" : "AWAITING DEVICE")
                    .font(DS.fontMeta)
                    .tracking(DS.metaTracking)
                    .foregroundStyle(isConnected ? DS.success : DS.textTertiary)
            }
            Spacer()
            // TODO: re-enable gating once EEG flow is wired — `disabled: !isConnected`
            ContinueButton(disabled: false, action: onContinue)
        }
    }

    private func connect() {
        let resolvedPort = Int(portText) ?? appModel.bciPort
        appModel.bciPort = resolvedPort
        portText = "\(resolvedPort)"
        appModel.bciClient.connect(host: appModel.bciHost, port: resolvedPort)
    }
}

// MARK: - Brain glyph

private struct BrainGlyph: View {
    let size: CGFloat
    var active: Bool = true

    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [DS.teal.opacity(0.35), DS.teal.opacity(0.18), .clear],
                    center: UnitPoint(x: 0.4, y: 0.35),
                    startRadius: 0,
                    endRadius: size * 0.55
                ))

            Image(systemName: "brain.head.profile")
                .font(.system(size: size * 0.62, weight: .light))
                .foregroundStyle(DS.teal)
                .shadow(color: DS.teal.opacity(active ? 0.85 : 0.4),
                        radius: active && pulse ? 18 : 10)
        }
        .frame(width: size, height: size)
        .scaleEffect(active && pulse ? 1.04 : 1.0)
        .onAppear {
            guard active else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Status pill

private enum PillKind {
    case success, info, warn

    var color: Color {
        switch self {
        case .success: return DS.success
        case .info:    return DS.info
        case .warn:    return DS.warning
        }
    }
}

private struct StatusPillView: View {
    let kind: PillKind
    let text: String

    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(kind.color)
                .frame(width: 7, height: 7)
                .shadow(color: kind.color.opacity(0.8), radius: 4)
                .opacity(pulse ? 0.3 : 1)
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(kind.color)
                .tracking(0.5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(kind.color.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(kind.color.opacity(0.45), lineWidth: 1))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever()) {
                pulse = true
            }
        }
    }
}

// MARK: - Continue button

private struct ContinueButton: View {
    let disabled: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("Continue")
                Image(systemName: "arrow.right")
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(disabled ? DS.textTertiary : DS.teal)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(buttonBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        disabled ? Color.white.opacity(0.10) : DS.teal.opacity(0.55),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: DS.teal.opacity(disabled ? 0 : (hover ? 0.35 : 0.15)),
                radius: hover ? 14 : 6
            )
            .scaleEffect(hover && !disabled ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hover = $0 }
        .animation(.easeInOut(duration: 0.18), value: hover)
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if disabled {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        } else {
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(
                    colors: [DS.teal.opacity(0.22), DS.teal.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
    }
}

#Preview(windowStyle: .automatic) {
    OnboardingView(onContinue: {})
        .environment(AppModel())
        .frame(width: 1100, height: 560)
}
