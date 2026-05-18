import SwiftUI

extension View {
    /// Accessibility helper: when `enabled` is true, fires `action` after the
    /// user's gaze rests on this view for `duration` seconds. Cancels
    /// automatically if hover ends early or the enclosing button becomes
    /// disabled. A teal stroke along an enclosing rounded rectangle of
    /// `cornerRadius` animates the progress.
    ///
    /// When `enabled` is false this is a pure pass-through — the underlying
    /// control's normal tap behaviour stays untouched.
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

    /// Reflects any `.disabled(...)` applied above this modifier — we should
    /// not dwell-fire actions on disabled controls.
    @Environment(\.isEnabled) private var isEnabled

    @State private var isHovering: Bool = false
    @State private var progress: Double = 0.0

    func body(content: Content) -> some View {
        content
            .overlay(progressOverlay)
            .onHover { hovering in
                // Gate on both the feature switch and the underlying control's
                // enabled state so disabled buttons cannot dwell-fire.
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
            // .task auto-cancels whenever the id (isHovering) changes, so we
            // never have to manage a separate Task handle. This avoids the
            // race the older modifier hit where a stale step-counter task
            // would keep mutating @State after hover-out and never fire the
            // action.
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
                    try? await Task.sleep(nanoseconds: 33_000_000)  // ~30 fps
                }
                guard !Task.isCancelled else { return }
                action()
                // Require the user to glance away and back to re-arm — avoids
                // a single sustained gaze triggering the action repeatedly.
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
