import Foundation

@Observable
final class SessionStore {
    private static let storageKey = "sessionHistory"
    private(set) var records: [SessionRecord] = []

    init() {
        load()
    }

    func save(_ record: SessionRecord) {
        records.insert(record, at: 0)
        persist()
    }

    func clearAll() {
        records.removeAll()
        persist()
    }

    var lastSession: SessionRecord? {
        records.first
    }

    var todayCount: Int {
        let cal = Calendar.current
        return records.filter { cal.isDateInToday($0.date) }.count
    }

    var todayTotalSeconds: Int {
        let cal = Calendar.current
        return records.filter { cal.isDateInToday($0.date) }.reduce(0) { $0 + $1.durationSeconds }
    }

    var todayTotalScore: Int {
        let cal = Calendar.current
        return records.filter { cal.isDateInToday($0.date) }.reduce(0) { $0 + $1.score }
    }

    var weeklyDays: [Bool] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let mondayOffset = (weekday + 5) % 7
        guard let monday = cal.date(byAdding: .day, value: -mondayOffset, to: today) else {
            return Array(repeating: false, count: 7)
        }
        return (0..<7).map { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: monday) else { return false }
            return records.contains { cal.isDate($0.date, inSameDayAs: day) }
        }
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([SessionRecord].self, from: data) else { return }
        records = decoded
    }
}
