import Foundation

struct SessionRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let stageReached: Int
    let totalStages: Int
    let score: Int
    let durationSeconds: Int

    init(stageReached: Int, totalStages: Int, score: Int, durationSeconds: Int) {
        self.id = UUID()
        self.date = Date()
        self.stageReached = stageReached
        self.totalStages = totalStages
        self.score = score
        self.durationSeconds = durationSeconds
    }

    var formattedDuration: String {
        let m = durationSeconds / 60
        let s = durationSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM"
        return f.string(from: date)
    }
}
