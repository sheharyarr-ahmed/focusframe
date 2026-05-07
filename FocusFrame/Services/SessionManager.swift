import Foundation
import Observation
import SwiftData

struct ActiveSession: Equatable {
    let goalText: String
    let startedAt: Date
}

@Observable
@MainActor
final class SessionManager {
    private(set) var currentSession: ActiveSession?

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var elapsedSeconds: Int {
        guard let session = currentSession else { return 0 }
        return Int(Date.now.timeIntervalSince(session.startedAt))
    }

    func startSession(goalText: String) {
        let trimmed = goalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, currentSession == nil else { return }
        currentSession = ActiveSession(goalText: trimmed, startedAt: .now)
    }

    func endSession() {
        guard let active = currentSession else { return }
        let endedAt = Date.now

        let goalID = upsertGoal(text: active.goalText)
        let dayOfWeek = Calendar.current.component(.weekday, from: active.startedAt)
        let bucket = Self.timeOfDayBucket(for: active.startedAt)

        let session = Session(
            goalText: active.goalText,
            goalID: goalID,
            startedAt: active.startedAt,
            endedAt: endedAt,
            distractionCount: 0,
            dayOfWeek: dayOfWeek,
            timeOfDayBucket: bucket
        )
        modelContext.insert(session)
        try? modelContext.save()

        currentSession = nil
    }

    private func upsertGoal(text: String) -> UUID {
        let normalized = text
        var descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate { $0.text.localizedStandardContains(normalized) }
        )
        descriptor.fetchLimit = 1

        if let existing = try? modelContext.fetch(descriptor).first,
           existing.text.localizedCaseInsensitiveCompare(text) == .orderedSame {
            existing.useCount += 1
            existing.lastUsedAt = .now
            return existing.id
        }

        let new = Goal(text: text)
        modelContext.insert(new)
        return new.id
    }

    static func timeOfDayBucket(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5...11: return "morning"
        case 12...16: return "afternoon"
        case 17...21: return "evening"
        default: return "late-night"
        }
    }
}
