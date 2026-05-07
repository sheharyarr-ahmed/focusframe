# Architecture

FocusFrame is built in five layers with strict directional dependencies. The `focusframe-architect` subagent enforces these rules; this document is the spec it enforces against.

## Dependency direction

```
Views ──► State ──► Services ──► Data Models
                                       ▲
              Live Activity (Widget) ──┘
```

A layer may import and depend on layers to its right. A layer may NOT import or depend on layers to its left. Any violation is an architectural regression and blocks merge.

## Folder layout

```
FocusFrame/
├── App/
│   └── FocusFrameApp.swift          @main, ModelContainer, AppState wiring
├── Models/                           SwiftData @Model classes (one per file)
│   ├── Session.swift
│   ├── Goal.swift
│   └── Insight.swift
├── Services/                         pure-Swift services, no UI imports
│   ├── SessionManager.swift
│   ├── DistractionDetector.swift
│   ├── ClaudeService.swift
│   └── KeychainService.swift
├── State/
│   └── AppState.swift                @Observable, @MainActor, owns services
├── Features/
│   ├── Timer/
│   │   ├── TimerView.swift
│   │   └── Components/
│   │       └── LiveTimerLabel.swift
│   ├── History/
│   │   ├── HistoryView.swift
│   │   └── SessionDetailView.swift
│   ├── Settings/
│   │   └── SettingsView.swift
│   └── Root/
│       └── RootView.swift            TabView container
├── Common/
│   ├── DesignTokens.swift            colors, fonts, spacing
│   ├── Formatters.swift              date/duration formatters
│   └── Logger+App.swift              os.Logger categories
└── Resources/
    ├── Assets.xcassets
    └── Localizable.xcstrings

FocusFrameLiveActivity/                 separate Widget Extension target
├── FocusSessionAttributes.swift
├── FocusSessionLiveActivity.swift
└── Info.plist

FocusFrameTests/                       unit tests
FocusFrameUITests/                     UI tests
```

## Layer 1 — Data Models

**Path:** `FocusFrame/Models/`

**What goes here:** `@Model` final classes representing persisted entities. Stored properties, init, trivial computed accessors. Conformance to `Codable`/`Hashable`/`Identifiable` if needed.

**What does NOT go here:**
- Network calls
- SwiftData fetches (`FetchDescriptor`, `@Query` — those live in services or views)
- Business logic ("if duration > X, do Y" — that's a service responsibility)
- View-tier types (no `Color`, no `Image`)

**Allowed imports:** `Foundation`, `SwiftData`.

**v1 relationship policy:** No SwiftData `@Relationship` macros. Cross-entity references use `UUID` foreign keys (e.g., `Insight.sessionID: UUID`). The migration to relationships is a v2 conversation.

Schema reference: `agent_docs/data-models.md`.

## Layer 2 — Services

**Path:** `FocusFrame/Services/`

**What goes here:** Pure Swift classes/actors that perform a single domain function. `SessionManager` (lifecycle), `DistractionDetector` (foreground/background tracking), `ClaudeService` (API I/O), `KeychainService` (secret storage). Services own all SwiftData mutations and all networking.

**What does NOT go here:**
- `import SwiftUI` or `import UIKit` — flag immediately
- `@Observable` (that's a State-layer macro; services use protocols + dependency injection)
- View-tier reactive primitives — services expose `async` methods or `AsyncStream`, not `@Published`

**Allowed imports:** `Foundation`, `SwiftData`, `os.log`, `Security` (Keychain), `ActivityKit` (only `SessionManager`, only to drive Live Activity lifecycle).

**Testability rule:** every service must be unit-testable without launching SwiftUI. If a test requires `XCUIApplication`, the logic was in the wrong layer.

## Layer 3 — State

**Path:** `FocusFrame/State/AppState.swift`

**What goes here:** A single `@Observable @MainActor final class AppState` that:
- Owns service instances as stored properties (composition root)
- Exposes view-facing state (`currentSession: Session?`, `isShowingSettings: Bool`, …)
- Coordinates cross-service flows (start session → drive Live Activity → arm distraction detector)

**What does NOT go here:**
- Direct SwiftData mutation (delegate to services)
- Networking (delegate to `ClaudeService`)
- Multiple `AppState`-equivalents per feature — there is exactly one

**Allowed imports:** `SwiftUI`, `Observation`, all service modules.

**Why one `AppState`:** v1 is small enough that a feature-scoped state object is over-engineering. When a feature genuinely needs isolated state (e.g., complex settings flow with its own state machine), introduce a feature-scoped `@Observable` and inject it via `.environment(_:)` — but `AppState` remains the root.

## Layer 4 — Views

**Path:** `FocusFrame/Features/<Feature>/`

**What goes here:** SwiftUI `View` structs. View modifiers. View-scoped components (under `Components/`). `#Preview` blocks.

**What does NOT go here:**
- Service instantiation (`SessionManager()` in a view body — flag)
- `URLSession`, `Keychain`, `Activity.request`, `modelContext.insert/delete`
- More than one top-level type per file

**SwiftData read access:** views may use `@Query` for read-only fetches (e.g., `HistoryView`'s 30-day list). All writes go through services via `AppState`.

**Allowed imports:** `SwiftUI`, `SwiftData` (for `@Query`), `Charts`, the feature's own `Components/` subdirectory, `Common/`.

**Component reuse:** if a view component is used by 2+ features, promote it to `Common/`. If used by exactly one, keep it under that feature's `Components/`.

## Layer 5 — Live Activity (Widget Extension)

**Path:** `FocusFrameLiveActivity/` (separate target)

**What goes here:**
- `FocusSessionAttributes: ActivityAttributes` — static and `ContentState` (dynamic) shapes
- `FocusSessionLiveActivity: Widget` — the lock-screen and Dynamic Island UI
- Widget-only assets

**What does NOT go here:**
- Imports of the main app target — widget extensions cannot link the app target
- Networking, persistence, business logic — the widget renders state passed in via `Activity.update(_:)`

**Allowed imports:** `ActivityKit`, `WidgetKit`, `SwiftUI`. Shared types (`FocusSessionAttributes`, `DesignTokens`) live in their canonical files and are added to BOTH targets via Xcode File Inspector → Target Membership. No App Group in v1 (free-tier Apple Developer constraint — see CLAUDE.md).

**Lifecycle ownership:** `Activity<FocusSessionAttributes>.request(...)`, `.update(...)`, `.end(...)` are called from `SessionManager` in the main app target. The widget itself is presentational.

Design reference: `agent_docs/live-activity-design.md`.

## Session state machine

```
   ┌──────┐  Start   ┌────────┐  End    ┌───────┐
   │ idle │ ───────► │ active │ ──────► │ ended │
   └──────┘          └────────┘         └───────┘
                       │   ▲
                  Pause│   │Resume    (v2 only)
                       ▼   │
                     ┌────────┐  End
                     │ paused │ ──────► ended
                     └────────┘
```

- `idle`, `active`, `paused` are in-memory states on `SessionManager`. They are not persisted.
- `ended` is the only state that produces a SwiftData row. The transition `active → ended` (or `paused → ended` in v2) is the persistence boundary.
- Insights are inserted only after a successful Claude API response. A `Session` may exist without a corresponding `Insight` (API failure path).
- **Force-kill mid-session:** the in-flight session is lost. v1 simplification — no BGTask, no `URLSession` background config, no resurrection. Documented user-facing behavior.

## Cross-cutting rules

### SwiftData mutation boundary

Only services call `modelContext.insert`, `.delete`, or `.save`. Anywhere else is a violation.

```swift
// ❌ View calls insert directly
struct SessionDetailView: View {
    @Environment(\.modelContext) var ctx
    var body: some View {
        Button("Delete") { ctx.delete(session) }   // wrong layer
    }
}

// ✅ View asks AppState; AppState delegates to service
struct SessionDetailView: View {
    @Environment(AppState.self) var state
    var body: some View {
        Button("Delete") { state.delete(session) }
    }
}
```

### Secrets boundary

Only `KeychainService` calls `SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete`. No raw Keychain APIs anywhere else.

### Live Activity drive boundary

Only `SessionManager` calls `Activity.request` / `.update` / `.end`. Views never touch ActivityKit directly.

### Test boundary

`FocusFrameTests` exercises Models and Services. `FocusFrameUITests` exercises Views via `XCUIApplication`. State-layer tests live in `FocusFrameTests` because `AppState` is testable without UI (services injectable via init).
