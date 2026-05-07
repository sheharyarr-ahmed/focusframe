import Foundation
import Observation
import OSLog
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
    private let claudeService: ClaudeService

    init(modelContext: ModelContext, claudeService: ClaudeService) {
        self.modelContext = modelContext
        self.claudeService = claudeService
    }

    var elapsedSeconds: Int {
        guard let session = currentSession else { return 0 }
        return Int(Date.now.timeIntervalSince(session.startedAt))
    }

    func startSession(goalText: String) {
        let trimmed = goalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, currentSession == nil else { return }
        currentSession = ActiveSession(goalText: trimmed, startedAt: .now)
        Logger.session.info("session started")
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
        Logger.session.info("session ended id=\(session.id, privacy: .public)")

        Task { [weak self] in
            await self?.fireInsight(for: session)
        }
    }

    func retryInsight(for session: Session) {
        Task { [weak self] in
            await self?.fireInsight(for: session, isRetry: true)
        }
    }

    private func fireInsight(for session: Session, isRetry: Bool = false) async {
        let insight = ensureInsightRow(for: session, isRetry: isRetry)

        do {
            let text = try await claudeService.generateInsight(for: session)
            insight.text = text
            insight.status = Insight.Status.succeeded.rawValue
            insight.generatedAt = .now
            try? modelContext.save()
            Logger.claude.info("insight succeeded session=\(session.id, privacy: .public)")
        } catch {
            insight.status = Insight.Status.failed.rawValue
            try? modelContext.save()
            Logger.claude.error("insight failed session=\(session.id, privacy: .public)")
        }
    }

    private func ensureInsightRow(for session: Session, isRetry: Bool) -> Insight {
        let sessionID = session.id
        var descriptor = FetchDescriptor<Insight>(
            predicate: #Predicate { $0.sessionID == sessionID }
        )
        descriptor.fetchLimit = 1

        if let existing = try? modelContext.fetch(descriptor).first {
            if isRetry {
                existing.status = Insight.Status.pending.rawValue
                existing.text = ""
                try? modelContext.save()
            }
            return existing
        }

        let new = Insight(
            sessionID: session.id,
            text: "",
            model: "claude-sonnet-4-5",
            status: Insight.Status.pending.rawValue
        )
        modelContext.insert(new)
        try? modelContext.save()
        return new
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
