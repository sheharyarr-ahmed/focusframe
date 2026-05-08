@preconcurrency import ActivityKit
import Foundation
import Observation
import OSLog
import SwiftData

struct ActiveSession: Equatable {
    let sessionID: UUID
    let goalText: String
    let startedAt: Date
}

@Observable
@MainActor
final class SessionManager {
    private(set) var currentSession: ActiveSession?

    private let modelContext: ModelContext
    private let claudeService: ClaudeService
    private let distractionDetector: DistractionDetector
    private var liveActivity: Activity<FocusSessionAttributes>?

    init(
        modelContext: ModelContext,
        claudeService: ClaudeService,
        distractionDetector: DistractionDetector
    ) {
        self.modelContext = modelContext
        self.claudeService = claudeService
        self.distractionDetector = distractionDetector

        let orphans = Activity<FocusSessionAttributes>.activities
        if !orphans.isEmpty {
            Logger.liveActivity.info("cleaning \(orphans.count, privacy: .public) orphan activities")
            Task {
                for activity in orphans {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }

    var elapsedSeconds: Int {
        guard let session = currentSession else { return 0 }
        return Int(Date.now.timeIntervalSince(session.startedAt))
    }

    func startSession(goalText: String) {
        let trimmed = goalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, currentSession == nil else { return }

        let active = ActiveSession(
            sessionID: UUID(),
            goalText: trimmed,
            startedAt: .now
        )
        currentSession = active
        distractionDetector.sessionStarted()
        Logger.session.info("session started")

        Task { [weak self] in
            await self?.startLiveActivity(for: active)
        }
    }

    func endSession() {
        guard let active = currentSession else { return }
        let endedAt = Date.now
        let distractionCount = distractionDetector.distractionCount
        let elapsedSeconds = Int(endedAt.timeIntervalSince(active.startedAt))

        Task { [weak self] in
            await self?.endLiveActivity(
                distractionCount: distractionCount,
                elapsedSeconds: elapsedSeconds
            )
        }

        let goalID = upsertGoal(text: active.goalText)
        let dayOfWeek = Calendar.current.component(.weekday, from: active.startedAt)
        let bucket = Self.timeOfDayBucket(for: active.startedAt)

        let session = Session(
            id: active.sessionID,
            goalText: active.goalText,
            goalID: goalID,
            startedAt: active.startedAt,
            endedAt: endedAt,
            distractionCount: distractionCount,
            dayOfWeek: dayOfWeek,
            timeOfDayBucket: bucket
        )
        modelContext.insert(session)
        try? modelContext.save()

        currentSession = nil
        distractionDetector.sessionEnded()
        Logger.session.info("session ended id=\(session.id, privacy: .public) distractions=\(distractionCount, privacy: .public)")

        Task { [weak self] in
            await self?.fireInsight(for: session)
        }
    }

    func retryInsight(for session: Session) {
        Task { [weak self] in
            await self?.fireInsight(for: session, isRetry: true)
        }
    }

    func deleteSession(_ session: Session) {
        let sessionID = session.id
        let logGoal = session.goalText

        if let active = currentSession, active.sessionID == sessionID {
            Task { [weak self] in
                await self?.endLiveActivity(distractionCount: 0, elapsedSeconds: 0)
            }
            currentSession = nil
            distractionDetector.sessionEnded()
        }

        var descriptor = FetchDescriptor<Insight>(
            predicate: #Predicate { $0.sessionID == sessionID }
        )
        descriptor.fetchLimit = 1
        if let insight = try? modelContext.fetch(descriptor).first {
            modelContext.delete(insight)
        }

        modelContext.delete(session)
        try? modelContext.save()

        Logger.session.info("session deleted id=\(sessionID, privacy: .public) goal=\(logGoal, privacy: .public)")
    }

    func handleDistractionUpdate() {
        Task { [weak self] in
            await self?.pushLiveActivityUpdate()
        }
    }

    private func startLiveActivity(for active: ActiveSession) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Logger.liveActivity.info("activities not enabled — skipping")
            return
        }

        let attributes = FocusSessionAttributes(
            sessionID: active.sessionID,
            goalText: active.goalText,
            startedAt: active.startedAt,
            plannedDurationMinutes: nil
        )
        let initialState = FocusSessionAttributes.ContentState(
            elapsedSeconds: 0,
            distractionCount: 0,
            isPaused: false
        )
        let content = ActivityContent(state: initialState, staleDate: nil)

        do {
            liveActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            Logger.liveActivity.info("activity started")
        } catch {
            Logger.liveActivity.error("activity request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func pushLiveActivityUpdate() async {
        guard let active = currentSession, let activity = liveActivity else { return }
        let elapsed = Int(Date.now.timeIntervalSince(active.startedAt))
        let newState = FocusSessionAttributes.ContentState(
            elapsedSeconds: elapsed,
            distractionCount: distractionDetector.distractionCount,
            isPaused: false
        )
        await activity.update(ActivityContent(state: newState, staleDate: nil))
        Logger.liveActivity.info("activity updated count=\(self.distractionDetector.distractionCount, privacy: .public)")
    }

    private func endLiveActivity(distractionCount: Int, elapsedSeconds: Int) async {
        guard let activity = liveActivity else { return }
        let finalState = FocusSessionAttributes.ContentState(
            elapsedSeconds: elapsedSeconds,
            distractionCount: distractionCount,
            isPaused: false
        )
        await activity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: .immediate
        )
        liveActivity = nil
        Logger.liveActivity.info("activity ended")
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
