# Live Activity design

Authoritative reference for the Widget Extension that renders FocusFrame on the lock screen and Dynamic Island. Implementation lives in the `FocusFrameLiveActivity` target; lifecycle is driven from `SessionManager` in the main app target.

## Targets and entitlements

- **Main app target**: `FocusFrame` (bundle id `com.sheryahmed.focusframe`)
- **Widget Extension target**: `FocusFrameLiveActivity` (placeholder — confirm name via `xcodebuild -list` after Xcode bootstrap)
- **App Group** (both targets): `group.com.sheryahmed.focusframe`
- **Info.plist key on main app**: `NSSupportsLiveActivities = YES`
- **Info.plist key on main app**: `NSSupportsLiveActivitiesFrequentUpdates = YES` (we update on each distraction event and once per minute for the timer; well within budget but the entitlement is required for the more frequent path)

The widget extension cannot import the main app target. Any types shared between the two (notably `FocusSessionAttributes`) live in files that are added to **both** target memberships, not in a separate framework — the data shape is small and a framework target is over-engineering for v1.

## `FocusSessionAttributes`

The static portion of the activity — values that do not change for the session's lifetime.

```swift
import ActivityKit
import Foundation

struct FocusSessionAttributes: ActivityAttributes {
    public typealias FocusSessionState = ContentState

    public struct ContentState: Codable, Hashable {
        // Dynamic — updated via Activity.update(...)
        var elapsedSeconds: Int
        var distractionCount: Int
        var isPaused: Bool        // v2 only; always false in v1
    }

    // Static — set once at Activity.request(...)
    let sessionID: UUID
    let goalText: String
    let startedAt: Date
    let plannedDurationMinutes: Int?   // nil for open-ended sessions
}
```

**Why `elapsedSeconds` is in `ContentState` even though `Text(timerInterval:)` ticks on its own:**

`Text(timerInterval:)` renders a self-updating timer label in the Live Activity without us pushing updates every second — the system handles ticking. We still store `elapsedSeconds` in `ContentState` so the badge / progress arc in the lock-screen layout can react to elapsed time at update boundaries (every minute or on distraction events), without recomputing from `startedAt` every render.

## Lock-screen layout

The lock-screen presentation is a single tall card. Brand: `#0F0F0F` background, `#6EE7B7` mint accent.

```
┌──────────────────────────────────────────────────────┐
│  ●  FocusFrame                              ⏱ 12:34  │  ← header row
│                                                      │
│  Draft Q3 budget memo                                │  ← goal title (1–2 lines)
│                                                      │
│  ┌──────────────────────────────────┐  ⚠ 2 distract. │  ← progress + distractions
│  │■■■■■■■■■■■■■░░░░░░░░░░░░░░░░░░░  │                │
│  └──────────────────────────────────┘                │
└──────────────────────────────────────────────────────┘
```

- **Header row**: app glyph + "FocusFrame" on the left; live timer (`Text(timerInterval:)`) on the right.
- **Goal title**: `goalText`, `font(.title3)`, `lineLimit(2)`, mint foreground.
- **Progress bar**: only when `plannedDurationMinutes != nil`. Width proportional to `elapsedSeconds / (plannedDurationMinutes * 60)`, clamped to 1.0. Mint fill on `#1F1F1F` track.
- **Distraction badge**: `Label("\(distractionCount) distractions", systemImage: "exclamationmark.triangle")`, hidden when `distractionCount == 0`.

When `plannedDurationMinutes == nil`, replace the progress bar with a centered live timer at `font(.largeTitle)` and drop the header timer.

## Dynamic Island layouts

### Compact (leading + trailing)

```
[●]                                          [⏱ 12:34]
```

- Leading: app glyph (`Image(systemName: "circle.fill")` in mint).
- Trailing: live timer (`Text(timerInterval:)`).

### Expanded (long-press / proactive)

```
┌───────────────────────────────────────────────┐
│ Draft Q3 budget memo                          │  ← center: goal text
├───────────────────────────────────────────────┤
│ ⏱ 12:34                          ⚠ 2          │  ← bottom: timer + distractions
└───────────────────────────────────────────────┘
```

- Center region: `goalText`, `lineLimit(1)`, truncate middle.
- Bottom-leading: live timer (`Text(timerInterval:)`).
- Bottom-trailing: distraction count with the warning glyph; hidden when zero.
- No leading/trailing regions used — keeps the expanded layout uncluttered.

### Minimal (other live activities competing)

```
[●]
```

- Single mint dot. No text. The user re-discovers the session by tapping into the full Dynamic Island.

## Lifecycle (driven by `SessionManager`)

### Start

```swift
func startSession(goal: String, plannedMinutes: Int?) async throws {
    // ... persist Session in-memory, arm DistractionDetector, etc. ...

    let attributes = FocusSessionAttributes(
        sessionID: session.id,
        goalText: goal,
        startedAt: session.startedAt,
        plannedDurationMinutes: plannedMinutes
    )
    let initialState = FocusSessionAttributes.ContentState(
        elapsedSeconds: 0,
        distractionCount: 0,
        isPaused: false
    )
    let content = ActivityContent(state: initialState, staleDate: nil)

    activity = try Activity.request(
        attributes: attributes,
        content: content,
        pushType: nil
    )
}
```

### Update

Called from `SessionManager` whenever:

1. A distraction event fires (foreground/background transition) — push the new `distractionCount` immediately.
2. A minute-tick `Timer` fires — push the updated `elapsedSeconds` (so the progress arc / badge reflect reality even if the user hasn't unlocked).

```swift
private func pushUpdate() async {
    let newState = FocusSessionAttributes.ContentState(
        elapsedSeconds: Int(Date.now.timeIntervalSince(startedAt)),
        distractionCount: distractionCount,
        isPaused: false
    )
    await activity?.update(ActivityContent(state: newState, staleDate: nil))
}
```

Stale date: `nil` in v1. We update at least every 60 seconds so the system never considers the activity stale. If we ever drop to less frequent updates, set `staleDate` to ~2× the update interval.

### End

```swift
func endSession() async {
    // ... transition to ended, persist Session, request Insight, etc. ...

    await activity?.end(
        ActivityContent(state: finalState, staleDate: nil),
        dismissalPolicy: .immediate
    )
    activity = nil
}
```

`.immediate` dismissal — when the user ends a session, the lock-screen card should disappear at once. Lingering past-session cards confuse the user.

### Force-kill recovery

If the app is force-killed mid-session, `Activity.activities` will still contain the in-flight activity on next launch. v1 policy (consistent with the session-loss policy in `architecture.md`):

- On app launch, iterate `Activity<FocusSessionAttributes>.activities` and call `.end(...)` on any leftover activity with `.immediate` dismissal.
- Do not attempt to reconstruct the in-flight `Session` — it was never persisted. The user has to start over.

This keeps the lock-screen state consistent with the SwiftData state.

## Update budgets and pitfalls

- ActivityKit allots a small budget per hour for each activity. A 60-second tick + occasional distraction events is well within the limit.
- Do NOT push updates more frequently than every 30 seconds for the timer — `Text(timerInterval:)` ticks visually on its own; pushing for the timer alone wastes budget.
- Do NOT include large data in `ContentState` — every byte costs encoding/IPC overhead. The current shape (~50 bytes encoded) is fine.
- Keep `ContentState: Hashable` honest. Mutations to a property must change the hash, or the system may dedupe an update and the lock screen will lag behind reality.

## Localization

Strings shown in the Live Activity (`"FocusFrame"`, `"distractions"`, etc.) live in `Localizable.xcstrings` like every other user-visible string. The widget target needs the strings file added to its target membership. Goal text is rendered as-is — never localized.

## Accessibility

- Lock-screen card and Dynamic Island regions need `.accessibilityLabel` on icon-only views (the mint dot, the warning glyph).
- The live timer is read by VoiceOver as elapsed-time when focused — `Text(timerInterval:)` handles this natively, do not override.
- Respect Reduce Motion: any animated transitions (e.g., distraction badge appearing) should fall back to opacity changes when `@Environment(\.accessibilityReduceMotion)` is true.

## Testing

- Unit-test the `ContentState` derivation logic (elapsed-seconds math, distraction-count merging) in `FocusFrameTests` against the pure types.
- Manually test lock-screen rendering on a physical device (the simulator's Live Activity preview is unreliable for layout fidelity past iOS 17). Capture a screenshot for the PR.
- Manually test Dynamic Island on iPhone 17 Pro / Pro Max simulator — both compact and expanded states. Capture a screen recording for the PR.
- Force-kill recovery: start a session in DEBUG, kill from Xcode, relaunch, confirm no leftover lock-screen card.
