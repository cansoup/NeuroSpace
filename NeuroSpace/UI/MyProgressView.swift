import Foundation
import SwiftUI


private let accent = DS.teal

// MARK: - Progress data model

private struct ProgressSession: Identifiable {
    let id: UUID
    let displayNumber: Int
    let date: Date
    let time: String
    let duration: String
    let stage: Int
    let totalStages: Int
    let score: Int
    let arm: String
    let eegSignal: Int
    let stages: [StageBreakdownRow]
    let breakdown: BubbleBreakdown
    let isSynthesizedStages: Bool
    let isSynthesizedBreakdown: Bool
}

private struct StageBreakdownRow: Identifiable {
    let stage: Int
    let score: Int
    let time: String
    let bubbles: Int
    var id: Int { stage }
}

private struct BubbleBreakdown {
    let red: Int
    let blue: Int

    var max: Int { Swift.max(red, blue) }
    var total: Int { red + blue }
}

private enum ProgressData {
    /// Map a real SessionRecord (no per-stage / bubble color data) to a display row,
    /// synthesizing stages and breakdown so the layout still renders.
    static func from(record: SessionRecord, displayNumber: Int) -> ProgressSession {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"

        let stagesReached = max(1, record.stageReached)
        let perStageScore = record.score / stagesReached
        let perStageSeconds = max(1, record.durationSeconds / stagesReached)
        let perStageBubbles = max(1, record.score / 40 / stagesReached)
        let synthStages: [StageBreakdownRow] = (1...stagesReached).map { i in
            StageBreakdownRow(
                stage: i,
                score: perStageScore,
                time: String(format: "%d:%02d", perStageSeconds / 60, perStageSeconds % 60),
                bubbles: perStageBubbles
            )
        }

        let totalBubbles = max(0, record.score / 40)
        let breakdown = BubbleBreakdown(
            red:  Int(Double(totalBubbles) * 0.5),
            blue: Int(Double(totalBubbles) * 0.5)
        )

        return ProgressSession(
            id: record.id,
            displayNumber: displayNumber,
            date: record.date,
            time: timeFormatter.string(from: record.date),
            duration: record.formattedDuration,
            stage: record.stageReached,
            totalStages: record.totalStages,
            score: record.score,
            arm: "—",
            eegSignal: 0,
            stages: synthStages,
            breakdown: breakdown,
            isSynthesizedStages: true,
            isSynthesizedBreakdown: true
        )
    }
}

// MARK: - Main view

struct MyProgressView: View {
    let onBack: () -> Void

    @Environment(AppModel.self) private var appModel
    @State private var selectedId: UUID?

    private var sessions: [ProgressSession] {
        appModel.sessionStore.records.enumerated().map { idx, record in
            ProgressData.from(record: record, displayNumber: idx + 1)
        }
    }

    private var todayReference: Date { Date() }

    private var selected: ProgressSession? {
        if let id = selectedId, let s = sessions.first(where: { $0.id == id }) {
            return s
        }
        return sessions.first
    }

    private var streakDays: Int {
        let cal = Calendar.current
        var streak = 0
        var cursor = cal.startOfDay(for: Date())
        let dates = Set(appModel.sessionStore.records.map { cal.startOfDay(for: $0.date) })
        while dates.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    private var weekNumber: Int {
        Calendar.current.component(.weekOfYear, from: Date())
    }

    var body: some View {
        VStack(spacing: 14) {
            header

            HStack(alignment: .top, spacing: 14) {
                leftRail.frame(width: 320)

                ScrollView(.vertical, showsIndicators: false) {
                    if let s = selected {
                        SessionDetailPanel(session: s)
                            .id(s.id)
                    } else {
                        emptyDetail
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .onAppear {
            if selectedId == nil { selectedId = sessions.first?.id }
        }
    }

    private var headerMetaText: String {
        let streak = streakDays
        let streakPart = streak > 0 ? "\(streak)-DAY STREAK" : "NO ACTIVE STREAK"
        return "WEEK \(weekNumber)  ·  \(streakPart)"
    }

    private var emptyDetail: some View {
        VStack(spacing: 8) {
            Text("No sessions yet")
                .font(DS.fontBody)
                .foregroundStyle(DS.textSecondary)
            Text("Complete a session to see your progress here.")
                .font(DS.fontMeta)
                .foregroundStyle(DS.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            NeuroLogoMark(size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("My Progress")
                    .font(DS.fontH2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text(headerMetaText)
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

    // MARK: - Left rail

    private var leftRail: some View {
        VStack(spacing: 12) {
            WeekOverview(sessions: sessions, today: todayReference)
            SummaryStats(sessions: sessions, streakOverride: streakDays)
            SessionHistoryList(
                sessions: sessions,
                selectedId: $selectedId
            )
        }
    }
}

// MARK: - Stage badge (5 mini bars + label)

private struct StageBadge: View {
    let stage: Int
    let total: Int

    private var color: Color {
        let pct = Double(stage) / Double(total)
        if pct >= 1.0 { return DS.teal }
        if pct >= 0.6 { return DS.bubbleBlue }
        if pct >= 0.4 { return DS.gold }
        return DS.textTertiary
    }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(i < stage ? color : Color.white.opacity(0.08))
                        .frame(width: 14, height: 5)
                        .shadow(color: i < stage ? color.opacity(0.3) : .clear, radius: 2)
                }
            }
            Text("\(stage)/\(total)")
                .font(DS.fontSmall)
                .fontWeight(.bold)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Week overview

private struct WeekOverview: View {
    let sessions: [ProgressSession]
    let today: Date

    private struct DayBar: Identifiable {
        let id: Int
        let label: String
        let session: ProgressSession?
        let isToday: Bool
    }

    private var days: [DayBar] {
        let cal = Calendar(identifier: .gregorian)
        let labelFormatter = DateFormatter()
        labelFormatter.locale = Locale(identifier: "en_US_POSIX")
        labelFormatter.dateFormat = "EEE"

        return (0..<7).map { i in
            let date = cal.date(byAdding: .day, value: -(6 - i), to: today) ?? today
            let session = sessions.first { cal.isDate($0.date, inSameDayAs: date) }
            return DayBar(
                id: i,
                label: labelFormatter.string(from: date),
                session: session,
                isToday: cal.isDate(date, inSameDayAs: today)
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "This Week", color: DS.textTertiary)
                .padding(.bottom, 10)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days) { day in
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            Color.clear.frame(height: 60)

                            if let s = day.session {
                                let h = min(60.0, Double(s.score) / 35.0)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        LinearGradient(
                                            colors: [accent, Color(hex: 0x00B48C).opacity(0.6)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(height: max(8, h))
                                    .shadow(color: accent.opacity(0.3), radius: 4)
                            } else {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.05))
                                    .frame(height: 6)
                            }
                        }

                        Text(day.label)
                            .font(.system(size: 8, weight: day.isToday ? .bold : .regular, design: .monospaced))
                            .foregroundStyle(
                                day.isToday ? accent
                                : (day.session != nil ? DS.textSecondary : DS.textTertiary)
                            )
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tealGlassCard()
    }
}

// MARK: - Summary stats

private struct SummaryStats: View {
    let sessions: [ProgressSession]
    let streakOverride: Int

    private struct Stat {
        let label: String
        let value: String
        let unit: String?
        let color: Color
    }

    private var stats: [Stat] {
        let total = sessions.count
        let best = sessions.map(\.score).max() ?? 0
        let avgStage = total > 0
            ? Double(sessions.reduce(0) { $0 + $1.stage }) / Double(total)
            : 0
        return [
            Stat(label: "Total Sessions", value: "\(total)", unit: nil, color: DS.teal),
            Stat(label: "Best Score", value: "\(best)", unit: "pts", color: DS.gold),
            Stat(label: "Avg Stage", value: String(format: "%.1f", avgStage), unit: nil, color: DS.purple),
            Stat(label: "Day Streak", value: "\(streakOverride)", unit: "days", color: DS.bubbleBlue)
        ]
    }

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Overall Stats", color: DS.textTertiary)
                .padding(.bottom, 10)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(stats.indices, id: \.self) { i in
                    let s = stats[i]
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.label)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(DS.textTertiary)

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(s.value)
                                .font(.system(size: 22, weight: .bold, design: .monospaced))
                                .foregroundStyle(s.color)
                            if let unit = s.unit {
                                Text(unit)
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundStyle(DS.textTertiary)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.innerBg, in: RoundedRectangle(cornerRadius: DS.radiusMd))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusMd)
                            .strokeBorder(DS.innerBorder, lineWidth: 1)
                    )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tealGlassCard()
    }
}

// MARK: - Session history list

private struct SessionHistoryList: View {
    let sessions: [ProgressSession]
    @Binding var selectedId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Session History", color: DS.textTertiary)
                .padding(.bottom, 12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 7) {
                    ForEach(sessions) { session in
                        SessionRow(
                            session: session,
                            isSelected: session.id == selectedId
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedId = session.id
                            }
                        }
                    }
                }
                .padding(.trailing, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .tealGlassCard()
    }
}

private struct SessionRow: View {
    let session: ProgressSession
    let isSelected: Bool

    private var displayNumberText: String {
        String(format: "%02d", session.displayNumber)
    }

    private var sessionMetaText: String {
        "\(session.time) · \(session.arm) arm"
    }

    private var stageColor: Color {
        if session.stage >= 5 { return DS.teal }
        if session.stage >= 3 { return DS.bubbleBlue }
        return DS.textSecondary
    }

    private var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: session.date)
    }

    var body: some View {
        HStack(spacing: 10) {
            numberBadge
            sessionText

            Spacer(minLength: 4)

            StageBadge(stage: session.stage, total: session.totalStages)
            durationText

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isSelected ? accent : Color.white.opacity(0.3))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            isSelected ? accent.opacity(0.10) : Color.white.opacity(0.03),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isSelected ? accent.opacity(0.4) : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
        .offset(x: isSelected ? -4 : 0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .contentShape(Rectangle())
    }

    private var numberBadge: some View {
        let fill = isSelected ? accent.opacity(0.18) : Color.white.opacity(0.06)
        let stroke = isSelected ? accent.opacity(0.4) : Color.white.opacity(0.08)

        return Text(displayNumberText)
            .font(DS.fontSmall)
            .fontWeight(.bold)
            .foregroundStyle(isSelected ? accent : DS.textTertiary)
            .frame(width: 28, height: 28)
            .background(fill, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(stroke, lineWidth: 1)
            )
    }

    private var sessionText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dateText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? accent : DS.textPrimary)
            Text(sessionMetaText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DS.textTertiary)
        }
    }

    private var durationText: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(session.duration)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(stageColor)
            Text("duration")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(DS.textTertiary)
        }
    }
}

// MARK: - Session detail panel

private struct SessionDetailPanel: View {
    let session: ProgressSession

    private var weekdayDateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: session.date)
    }

    private var metaLine: String {
        var parts = ["Started \(session.time)"]
        if session.arm != "—" {
            parts.append("\(session.arm) Arm")
        }
        if session.eegSignal > 0 {
            parts.append("EEG \(session.eegSignal)%")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 12) {
            headerCard
            stageBreakdownCard
            bubbleBreakdownCard
        }
    }

    private var headerCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: "Session Detail", color: DS.textTertiary)

                    Text(weekdayDateText)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.textPrimary)

                    Text(metaLine)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DS.textTertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    SectionLabel(text: "Final Stage", color: DS.textTertiary)

                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(session.stage)")
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundStyle(accent)
                        Text("/\(session.totalStages)")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(DS.textTertiary)
                    }
                }
            }

            HStack(spacing: 8) {
                metricTile(label: "Total Score", value: "\(session.score)", unit: "pts", color: accent)
                metricTile(label: "Duration", value: session.duration, unit: nil, color: DS.gold)
                metricTile(label: "Bubbles Pop", value: "\(session.breakdown.total)", unit: nil, color: DS.purple)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tealGlassCard()
    }

    private func metricTile(label: String, value: String, unit: String?, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(DS.textTertiary)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(color)

            if let unit {
                Text(unit)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(DS.innerBg, in: RoundedRectangle(cornerRadius: DS.radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMd)
                .strokeBorder(DS.innerBorder, lineWidth: 1)
        )
    }

    private var stageBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Stage Breakdown", color: DS.textTertiary)
                .padding(.bottom, 12)

            VStack(spacing: 6) {
                ForEach(Array(session.stages.enumerated()), id: \.element.id) { idx, row in
                    stageRowView(row, idx: idx)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tealGlassCard()
    }

    private func stageRowView(_ row: StageBreakdownRow, idx: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(row.stage)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .frame(width: 26, height: 26)
                .background(accent.opacity(0.08 + Double(idx) * 0.03), in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(accent.opacity(0.25), lineWidth: 1)
                )

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 4)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.55)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * min(1.0, Double(row.score) / 500.0), height: 4)
                }
            }
            .frame(height: 4)

            Text("+\(row.score)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .frame(width: 50, alignment: .trailing)

            Text(row.time)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DS.textTertiary)
                .frame(width: 40, alignment: .trailing)

            HStack(spacing: 4) {
                Circle().fill(DS.purple.opacity(0.7)).frame(width: 6, height: 6)
                Text("\(row.bubbles)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DS.textTertiary)
            }
            .frame(width: 32, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DS.innerBg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var bubbleBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Bubble Breakdown", color: DS.textTertiary)
                .padding(.bottom, 10)

            VStack(spacing: 10) {
                BubbleBar(label: "Red", count: session.breakdown.red, max: session.breakdown.max, color: DS.bubbleRed)
                BubbleBar(label: "Blue", count: session.breakdown.blue, max: session.breakdown.max, color: DS.bubbleBlue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tealGlassCard()
    }
}

private struct BubbleBar: View {
    let label: String
    let count: Int
    let max: Int
    let color: Color

    private var pct: Double {
        max > 0 ? Double(count) / Double(max) : 0
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                HStack(spacing: 7) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .shadow(color: color.opacity(0.6), radius: 3)
                    Text(label)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(DS.textSecondary)
                }
                Spacer()
                Text("×\(count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 4)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.6)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * pct, height: 4)
                }
            }
            .frame(height: 4)
        }
    }
}

#Preview(windowStyle: .automatic) {
    MyProgressView(onBack: {})
        .environment(AppModel())
        .frame(width: 1100, height: 560)
}
