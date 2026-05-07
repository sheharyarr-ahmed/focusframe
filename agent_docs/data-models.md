# SwiftData schema — `Session`, `Goal`, `Insight`

Authoritative reference for the v1 data layer. All three live in `FocusFrame/Models/`, one type per file. No SwiftData `@Relationship` macros in v1 — cross-entity references use `UUID` foreign keys.

## `Session`

```swift
import Foundation
import SwiftData

@Model
final class Session {
    @Attribute(.unique) var id: UUID
    var goalText: String
    var goalID: UUID?              // FK to Goal, nullable for ad-hoc goals
    var startedAt: Date
    var endedAt: Date              // populated only when state machine reaches `ended`
    var distractionCount: Int
    var dayOfWeek: Int             // Calendar.current.component(.weekday, from: startedAt)
    var timeOfDayBucket: String    // "morning" | "afternoon" | "evening" | "late-night"

    init(
        id: UUID = UUID(),
        goalText: String,
        goalID: UUID? = nil,
        startedAt: Date,
        endedAt: Date,
        distractionCount: Int,
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
```

**Lifecycle:**

- Created in memory by `SessionManager.startSession(goal:)`. Not persisted while `active` or `paused`.
- Inserted into the model context by `SessionManager.endSession()` once `endedAt` is set.
- Deleted only via explicit user action in `SessionDetailView` (cascading: also delete the `Insight` row whose `sessionID` matches).

**Time-of-day bucket boundaries** (fixed; document here so the API contract uses identical bucketing):

| Bucket | Hours (24h, local time) |
| --- | --- |
| `morning` | 05:00–11:59 |
| `afternoon` | 12:00–16:59 |
| `evening` | 17:00–21:59 |
| `late-night` | 22:00–04:59 |

Compute once at session start from `startedAt`. Do not recompute at end — the bucket reflects when the session began.

## `Goal`

```swift
import Foundation
import SwiftData

@Model
final class Goal {
    @Attribute(.unique) var id: UUID
    var text: String
    var createdAt: Date
    var lastUsedAt: Date
    var useCount: Int

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = .now,
        lastUsedAt: Date = .now,
        useCount: Int = 1
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }
}
```

**Purpose:** persist user goal strings so the UI can autocomplete recent goals. Goals are deduplicated by `text` (case-insensitive) inside `SessionManager.startSession(goal:)`: if a matching goal exists, increment `useCount` and update `lastUsedAt`; otherwise insert.

**Lifecycle:**

- Inserted by `SessionManager` on first use of a goal text.
- `useCount` and `lastUsedAt` updated each time the same text starts a new session.
- Never auto-deleted in v1. Manual cleanup via `SettingsView` is a v2 idea.

## `Insight`

```swift
import Foundation
import SwiftData

@Model
final class Insight {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID            // FK to Session.id
    var text: String               // the 2–3 sentence Claude response (empty while pending)
    var model: String              // "claude-sonnet-4-5" — denormalized for future model migrations
    var generatedAt: Date
    var status: String             // "pending" | "succeeded" | "failed" — see Status enum below

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        text: String = "",
        model: String,
        generatedAt: Date = .now,
        status: String = "pending"
    ) {
        self.id = id
        self.sessionID = sessionID
        self.text = text
        self.model = model
        self.generatedAt = generatedAt
        self.status = status
    }
}

extension Insight {
    enum Status: String {
        case pending, succeeded, failed
    }
    var statusEnum: Status { Status(rawValue: status) ?? .pending }
}
```

**Lifecycle:**

- Inserted by `SessionManager.fireInsight(for:)` immediately after a `Session` is persisted — initially with `status = "pending"` and empty `text`.
- Updated to `status = "succeeded"` with populated `text` when `ClaudeService.generateInsight(for:)` returns successfully.
- Updated to `status = "failed"` when `ClaudeService.generateInsight(for:)` throws. The row remains so the UI can surface a Retry affordance.
- A `Session` may exist without an `Insight` only if the app is force-killed between session save and the pending Insight insert — extremely narrow window, treated like a permanent missing-insight state in the UI.
- Deleted by cascade when its parent `Session` is deleted (manual cascade — no SwiftData relationship machinery).

**Status field rationale:** A persisted `status` makes Insight rows the single source of truth for generation state — the UI can render pending/succeeded/failed identically across launches, and Retry can target failed rows directly. `String` storage (not raw enum) sidesteps SwiftData's enum-attribute quirks; the `Status` enum extension gives callers a typed read API.

## Query patterns

### 30-day history view

```swift
@Query(
    filter: #Predicate<Session> { $0.endedAt > thirtyDaysAgo },
    sort: \Session.endedAt,
    order: .reverse
)
var recentSessions: [Session]
```

`thirtyDaysAgo` is computed at view init from `Calendar.current.date(byAdding: .day, value: -30, to: .now)`.

### Joining sessions with insights (no relationship)

```swift
// In a service:
func insight(for session: Session) -> Insight? {
    let sessionID = session.id
    var descriptor = FetchDescriptor<Insight>(
        predicate: #Predicate { $0.sessionID == sessionID }
    )
    descriptor.fetchLimit = 1
    return try? modelContext.fetch(descriptor).first
}
```

For `SessionDetailView`, the service joins on demand. Performance note: with v1 expected scale (≤ 1000 sessions/year), per-row lookup is fine. Revisit if profiling shows query cost.

### Goal autocomplete

```swift
@Query(
    sort: [SortDescriptor(\Goal.lastUsedAt, order: .reverse)],
)
var recentGoals: [Goal]
```

Take `prefix(5)` in the view for the autocomplete list.

## Migration policy

v1 ships with this schema and SwiftData's lightweight migration. When a schema change is needed:

1. Bump the schema version.
2. Add a `VersionedSchema` and a `MigrationStage`.
3. Test the migration on a simulator with realistic data before merging.

**v2 candidates** (not in v1):

- Convert `Session ↔ Insight` UUID FK to a SwiftData `@Relationship`.
- Add `DistractionEvent` as a child collection on `Session` (replaces `distractionCount` scalar).
- Add `pausedRanges: [DateInterval]` for the v2 pause/resume flow.

Document any schema change in the PR body's "Architecture impact" section.

## What lives in `Session` vs. derived in views

`durationMinutes` is computed, not stored — it's derivable from `startedAt`/`endedAt` and SwiftData would otherwise hold redundant state that can drift.

`dayOfWeek` and `timeOfDayBucket` are stored even though they're derivable from `startedAt`, because:

1. The Anthropic API contract expects them as separate fields.
2. Charts queries filter by them and benefit from indexed access.
3. Recomputing at query time means re-running `Calendar` math on every row in `HistoryView`.

This is the only deliberate denormalization in v1. Keep the list short.
