import Foundation
import SwiftData

@Model
final class Session {
    @Attribute(.unique) var id: UUID
    var goalText: String
    var goalID: UUID?
    var startedAt: Date
    var endedAt: Date
    var distractionCount: Int
    var dayOfWeek: Int
    var timeOfDayBucket: String

    init(
        id: UUID = UUID(),
        goalText: String,
        goalID: UUID? = nil,
        startedAt: Date,
        endedAt: Date,
        distractionCount: Int = 0,
        dayOfWeek: Int,
        timeOfDayBucket: String
    ) {
        self.id = id
        self.goalText = goalText
        self.goalID = goalID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distractionCount = distractionCount
        self.dayOfWeek = dayOfWeek
        self.timeOfDayBucket = timeOfDayBucket
    }

    var durationMinutes: Int {
        Int(endedAt.timeIntervalSince(startedAt) / 60)
    }
}
