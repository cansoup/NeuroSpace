//
//  StageEndBubblesView.swift
//  NeuroSpace
//
//

import SwiftUI



enum StageEndChoice: String {
    case lobby = "StageEnd_lobby"
    case retry = "StageEnd_retry"
    case next  = "StageEnd_next"
}


struct StageEndLabel: View {
    let text: String
    let color: Color
    let isActive: Bool
    let dwellProgress: Double
    let dwellDuration: Double

    private var secondsLeft: Int {
        let remaining = dwellDuration * (1.0 - dwellProgress)
        return max(0, Int(ceil(remaining)))
    }

    var body: some View {
        VStack(spacing: 8) {

            
            if isActive {
                ZStack {
                    // Track
                    Circle()
                        .stroke(color.opacity(0.2), lineWidth: 3)
                        .frame(width: 36, height: 36)

                    // Fill arc — grows clockwise
                    Circle()
                        .trim(from: 0, to: dwellProgress)
                        .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 36, height: 36)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.05), value: dwellProgress)

                    // Countdown number
                    Text("\(secondsLeft)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                }
                .transition(.scale.combined(with: .opacity))
            }

            
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .shadow(color: color.opacity(0.9), radius: 4)
                Text(text)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(isActive ? .white : DS.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Color(hex: 0x060D1C, alpha: isActive ? 0.95 : 0.75),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(color.opacity(isActive ? 0.80 : 0.30), lineWidth: 1)
            )
            .shadow(color: color.opacity(isActive ? 0.5 : 0.0), radius: 10)
            .scaleEffect(isActive ? 1.08 : 1.0)
        }
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}
