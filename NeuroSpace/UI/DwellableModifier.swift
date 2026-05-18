import SwiftUI

extension View {
    func dwellable(
        _ enabled: Bool,
        duration: Double,
        cornerRadius: CGFloat = 14,
        action: @escaping () -> Void
    ) -> some View {
        modifier(DwellableModifier(
            enabled: enabled,
            duration: duration,
            cornerRadius: cornerRadius,
            action: action
        ))
    }
}

private struct DwellableModifier: ViewModifier {
    let enabled: Bool
    let duration: Double
    let cornerRadius: CGFloat
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    @State private var isHovering: Bool = false
    @State private var progress: Double = 0.0

    func body(content: Content) -> some View {
        content
            .overlay(progressOverlay)
            .onHover { hovering in
                guard enabled, isEnabled else {
                    isHovering = false
                    return
                }
                isHovering = hovering
            }
            .onChange(of: enabled) { _, newValue in
                if !newValue {
                    isHovering = false
                    progress = 0
                }
            }
            .onChange(of: isEnabled) { _, newValue in
                if !newValue {
                    isHovering = false
                    progress = 0
                }
            }
            .task(id: isHovering) {
                guard isHovering else {
                    progress = 0
                    return
                }
                let start = Date()
                while !Task.isCancelled {
                    let elapsed = Date().timeIntervalSince(start)
                    progress = min(1.0, elapsed / duration)
                    if elapsed >= duration { break }
                    try? await Task.sleep(nanoseconds: 33_000_000)
                }
                guard !Task.isCancelled else { return }
                action()
                // Force a hover-out before next fire so a sustained gaze
                // doesn't retrigger the action.
                progress = 0
                isHovering = false
            }
    }

    @ViewBuilder
    private var progressOverlay: some View {
        if progress > 0 {
            RoundedRectangle(cornerRadius: cornerRadius)
                .trim(from: 0, to: progress)
                .stroke(
                    DS.teal,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .opacity(0.85)
                .allowsHitTesting(false)
        }
    }
}
