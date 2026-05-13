import SwiftUI

/// Live monitor of incoming BCI predictions. Drop on any view that has access
/// to AppModel; updates automatically as `bciClient.lastPrediction` changes.
struct BCILiveStreamView: View {
    @Environment(AppModel.self) private var appModel

    private static let confidenceThreshold: Double = 0.75

    private var prediction: BCIPredictionMessage? {
        appModel.bciClient.lastPrediction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            classRow

            confidenceBar

            probabilitiesBlock

            historyStrip
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(prediction == nil ? DS.textTertiary : DS.teal)
                .frame(width: 7, height: 7)
                .shadow(color: (prediction == nil ? Color.clear : DS.teal).opacity(0.7), radius: 4)

            Text("EEG LIVE STREAM")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(DS.textTertiary)

            Spacer()

            if let p = prediction {
                Text("\(Int(p.processingTimeMs)) ms")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DS.textTertiary)
            } else {
                Text("Waiting…")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DS.textTertiary)
            }
        }
    }

    // MARK: - Predicted class

    private var classRow: some View {
        HStack(spacing: 10) {
            ForEach(PredictedClass.allCases, id: \.self) { cls in
                classChip(for: cls)
            }
        }
    }

    private func classChip(for cls: PredictedClass) -> some View {
        let isActive = prediction?.predictedClass == cls
        let above = prediction?.aboveThreshold ?? false
        let color = color(for: cls)

        return VStack(spacing: 4) {
            Text(cls.rawValue.uppercased())
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(isActive ? color : DS.textTertiary)
            Text(isActive ? (above ? "ABOVE" : "BELOW") : " ")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(isActive ? (above ? DS.success : DS.warning) : .clear)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            (isActive ? color.opacity(0.18) : Color.white.opacity(0.03)),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isActive ? color.opacity(0.55) : Color.white.opacity(0.10),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Confidence

    private var confidenceBar: some View {
        let conf = prediction?.confidence ?? 0
        let activeColor = prediction.map { color(for: $0.predictedClass) } ?? DS.textTertiary

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("CONFIDENCE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(DS.textTertiary)
                Spacer()
                Text(String(format: "%.2f", conf))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(activeColor)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                    Capsule()
                        .fill(activeColor)
                        .frame(width: geo.size.width * CGFloat(conf))
                    // threshold marker
                    Rectangle()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: 1, height: 10)
                        .offset(x: geo.size.width * CGFloat(Self.confidenceThreshold), y: 0)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Per-class probabilities

    private var probabilitiesBlock: some View {
        let probs = prediction?.probabilities

        return VStack(spacing: 6) {
            probabilityRow("Left",  probs?.left  ?? 0, color: DS.bubbleBlue)
            probabilityRow("Right", probs?.right ?? 0, color: DS.bubbleRed)
            probabilityRow("Both",  probs?.both  ?? 0, color: DS.purple)
        }
    }

    private func probabilityRow(_ label: String, _ value: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(DS.textSecondary)
                .frame(width: 44, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.05))
                    Capsule()
                        .fill(color.opacity(0.85))
                        .frame(width: geo.size.width * CGFloat(value))
                }
            }
            .frame(height: 5)

            Text(String(format: "%.0f%%", value * 100))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(DS.textPrimary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - History strip

    private var historyStrip: some View {
        HStack(spacing: 3) {
            Text("RECENT")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(DS.textTertiary)
                .padding(.trailing, 4)

            ForEach(Array(appModel.bciClient.predictionHistory.suffix(20).enumerated()),
                    id: \.offset) { _, p in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: p.predictedClass)
                        .opacity(p.aboveThreshold ? 0.95 : 0.35))
                    .frame(width: 9, height: 14)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Helpers

    private func color(for cls: PredictedClass) -> Color {
        switch cls {
        case .left:  return DS.bubbleBlue
        case .right: return DS.bubbleRed
        case .both:  return DS.purple
        }
    }
}

extension PredictedClass: CaseIterable {
    public static var allCases: [PredictedClass] { [.left, .right, .both] }
}

#Preview(windowStyle: .automatic) {
    BCILiveStreamView()
        .environment(AppModel())
        .padding(40)
        .frame(width: 560)
}
