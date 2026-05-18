import SwiftUI

/// Floating panel attached to the immersive scene during the
/// left/right/both calibration cue sequence. Shows the current cue, an
/// indicator dot row, and the steady-focus reminder.
struct ImmersiveCalibrationPanel: View {
    let cue: CalibrationCue

    private var cueIndex: Int {
        CalibrationCue.allCases.firstIndex(of: cue) ?? 0
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("Calibration")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                Text(cue.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(cue.prompt)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                ForEach(CalibrationCue.allCases.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == cueIndex ? Color.green : Color.secondary.opacity(0.30))
                        .frame(width: index == cueIndex ? 28 : 9, height: 9)
                }
            }
            .frame(height: 12)

            Text("Keep your body still and focus only on the imagined movement.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 26)
        .frame(width: 420)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26))
    }
}
