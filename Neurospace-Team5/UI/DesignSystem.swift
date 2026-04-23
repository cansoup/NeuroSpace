import SwiftUI

// MARK: - Color Tokens

enum DS {
    // Background
    static let bgBase    = Color(hex: 0x060a12)
    static let bgDeep    = Color(hex: 0x030609)
    static let bgRaised  = Color(hex: 0x0d1220)

    // Accent
    static let teal      = Color(hex: 0x00D4AA)
    static let purple    = Color(hex: 0x9B7FEA)
    static let pink      = Color(hex: 0xE040FB)
    static let gold      = Color(hex: 0xFFD166)

    // Bubble Points
    static let bubbleRed   = Color(hex: 0xFF6B6B)
    static let bubbleBlue  = Color(hex: 0x5B9BFF)
    static let bubbleGreen = Color(hex: 0x4CC98A)
    static let bubbleGold  = Color(hex: 0xFFD166)

    // Status
    static let success = Color(hex: 0x4CC98A)
    static let error   = Color(hex: 0xFF5050)
    static let warning = Color(hex: 0xFFD166)
    static let info    = Color(hex: 0x5B9BFF)

    // Glass
    static let glassBg     = Color.white.opacity(0.055)
    static let glassBorder = Color.white.opacity(0.10)
    static let innerBg     = Color.white.opacity(0.04)
    static let innerBorder = Color.white.opacity(0.07)

    // Corner Radii
    static let radiusSm:   CGFloat = 10
    static let radiusMd:   CGFloat = 12
    static let radiusLg:   CGFloat = 18
    static let radiusXl:   CGFloat = 22
    static let radiusPill: CGFloat = 100

    // Spacing
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 14
    static let space5: CGFloat = 20
    static let space6: CGFloat = 24
    static let space7: CGFloat = 28
    static let space8: CGFloat = 32

    // MARK: - Typography
    // Mapped from Space Grotesk → .rounded, Space Mono → .monospaced

    /// Hero brand title — Space Grotesk 700 · 36px · tracking -0.02em
    static let fontHero = Font.system(size: 36, weight: .bold, design: .rounded)
    static let heroTracking: CGFloat = -0.7   // -0.02em × 36

    /// Heading 2 — Space Grotesk 700 · 28px
    static let fontH2 = Font.system(size: 28, weight: .bold, design: .rounded)

    /// Heading 3 — Space Grotesk 700 · 22px
    static let fontH3 = Font.system(size: 22, weight: .bold, design: .rounded)

    /// Button / CTA — Space Grotesk 600 · 17px
    static let fontButton = Font.system(size: 17, weight: .semibold, design: .rounded)

    /// Button small — Space Grotesk 600 · 15px
    static let fontButtonSm = Font.system(size: 15, weight: .semibold, design: .rounded)

    /// Body / description — Space Grotesk 400 · 13px · line-height 1.55
    static let fontBody = Font.system(size: 13, weight: .regular, design: .rounded)

    /// Section label — Space Mono 400 · 9px · tracking 0.18em · uppercase
    static let fontLabel = Font.system(size: 9, weight: .regular, design: .monospaced)
    static let labelTracking: CGFloat = 1.6   // 0.18em × 9

    /// Data / coordinates — Space Mono 400 · 13px · teal
    static let fontData = Font.system(size: 13, weight: .regular, design: .monospaced)

    /// Meta / status bar — Space Mono 400 · 10px · tracking 0.05em
    static let fontMeta = Font.system(size: 10, weight: .regular, design: .monospaced)
    static let metaTracking: CGFloat = 0.5    // 0.05em × 10

    /// Small label — Space Mono 400 · 11px
    static let fontSmall = Font.system(size: 11, weight: .regular, design: .monospaced)

    // Text Colors
    static let textPrimary   = Color.white.opacity(0.9)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary  = Color.white.opacity(0.3)
    static let textMeta      = Color.white.opacity(0.25)
}

// MARK: - Glass Card Modifier

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = DS.radiusLg
    var borderColor: Color = DS.glassBorder

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(radius: CGFloat = DS.radiusLg, border: Color = DS.glassBorder) -> some View {
        modifier(GlassCard(cornerRadius: radius, borderColor: border))
    }

    func tealGlassCard(radius: CGFloat = DS.radiusXl) -> some View {
        modifier(GlassCard(cornerRadius: radius, borderColor: DS.teal.opacity(0.2)))
    }
}

// MARK: - Section Label

struct SectionLabel: View {
    let text: String
    var color: Color = DS.textTertiary

    var body: some View {
        Text(text)
            .font(DS.fontLabel)
            .tracking(DS.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
