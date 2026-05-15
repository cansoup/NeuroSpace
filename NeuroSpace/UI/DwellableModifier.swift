import SwiftUI

extension View {
    /// Accessibility helper: when `enabled` is true, fires `action` after the
    /// user's gaze hovers over this view for `duration` seconds. Cancels if
    /// hover ends early. A teal stroke along the edges of an enclosing
    /// `RoundedRectangle(cornerRadius: cornerRadius)` animates the progress.
    ///
    /// When `enabled` is false this is a pass-through and `action` is never
    /// invoked here — the underlying control's own tap path stays untouched.
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

    @State private var progress: Double = 0.0
    @State private var task: Task<Void, Never>? = nil

    func body(content: Content) -> some View {
        content
            .overlay {
                if enabled && progress > 0 {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .trim(from: 0, to: progress)
                        .stroke(
                            DS.teal,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .opacity(0.85)
                        .allowsHitTesting(false)
                        .animation(.linear(duration: 0.05), value: progress)
                }
            }
            .onHover { isHovering in
                guard enabled else { return }
                if isHovering {
                    startDwell()
                } else {
                    cancelDwell()
                }
            }
            .onChange(of: enabled) { _, newValue in
                if !newValue { cancelDwell() }
            }
            .onDisappear { cancelDwell() }
    }

    @MainActor
    private func startDwell() {
        cancelDwell()
        progress = 0
        let steps = 30
        let interval = duration / Double(steps)
        task = Task { @MainActor in
            for i in 1...steps {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                progress = Double(i) / Double(steps)
            }
            if Task.isCancelled { return }
            action()
            // Reset so re-hovering re-arms.
            progress = 0
        }
    }

    private func cancelDwell() {
        task?.cancel()
        task = nil
        progress = 0
    }
}
