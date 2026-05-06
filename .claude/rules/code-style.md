# Code style

## Defer to swiftui-pro

`.claude/skills/swiftui-pro/SKILL.md` is the source of truth for:

- Swift 6 strict concurrency (`async`/`await`, actors, `@Sendable`, data-race avoidance) — `references/swift.md`
- Deprecated SwiftUI API and modern replacements (`foregroundStyle`, `clipShape`, `Tab`, `@Entry`, `sensoryFeedback`, …) — `references/api.md`
- View composition, `#Preview`, animation, button-action extraction — `references/views.md`
- `@Observable`, `@State`, `@Bindable`, `@Environment`, SwiftData property wrappers — `references/data.md`
- `NavigationStack`/`NavigationSplitView`, `navigationDestination(for:)`, sheets, alerts — `references/navigation.md`
- Constants enums for fonts/colors/spacing, 44×44 tap targets, `ContainerRelativeFrame` — `references/design.md`
- Dynamic Type, VoiceOver, Reduce Motion — `references/accessibility.md`
- View-branching ternaries, no `AnyView`, `task()` over `onAppear()`, `LazyVStack` — `references/performance.md`
- No secrets in repo, Keychain mandate, `Localizable.xcstrings`, SwiftLint compliance — `references/hygiene.md`

When reviewing or writing SwiftUI code, load the relevant reference and follow it.

## FocusFrame overlays (not in swiftui-pro)

### Hard rules

- **No `!`, no `try!`, no `as!`** in app code. Use optional binding, `??`, or `do/try/catch`. Test code may use `try` with `XCTest` failure semantics — but never `!` even there.
- **One type per file.** `struct`/`class`/`enum`/`@Model`/`actor`. The only co-location allowed is a protocol + its default-implementation extension when both exist solely to support that protocol.
- **No Combine, no completion-handler APIs** for new code. `URLSession.data(for:)` not `dataTask(with:completionHandler:)`. Use `AsyncStream` or actors for event streams, not `Publisher`.

### Networking

- All Anthropic API calls go through `ClaudeService`. No `URLSession` calls in views, in `AppState`, or in any other service.
- `URLSession.shared.data(for: URLRequest)` with `async`/`await` — never `dataTaskPublisher`, never `dataTask` with completion handler.
- Request and response bodies are `Codable` structs with explicit `CodingKeys`. No `[String: Any]` JSON parsing.
- Errors model the API surface: `enum ClaudeServiceError: Error { case unauthorized, rateLimited(retryAfter: TimeInterval?), serverError(statusCode: Int), decoding(Error), transport(Error) }`. Map HTTP status codes to cases in one place.

### Logging

- `os.Logger` only. Subsystem `com.sheryahmed.focusframe`, categories per service (`session`, `claude`, `keychain`, `liveactivity`).
- `print` is a lint failure. `NSLog` is a lint failure.
- Never log API keys, never log full Claude responses (truncate to first 80 chars at `.debug` level), never log user goal text at `.info` or higher (PII potential).

### Secrets

- All access to the Anthropic API key goes through `KeychainService`. No raw `SecItemAdd` / `SecItemCopyMatching` outside that file.
- DEBUG bootstrap fallback reads `Secrets.xcconfig` (gitignored) at first launch only, copies into Keychain, then never reads the xcconfig again. Release builds skip this path entirely.
- No key in `Info.plist`, no key in committed `xcconfig`, no key behind `#if DEBUG` as a string literal.

### SwiftData

- All `modelContext.insert` / `delete` / `save` calls happen inside a service. Views may use `@Query` for read-only fetches.
- `@Query` predicates use compile-checked Swift expressions, not `NSPredicate(format:)` strings.
- One `@Model` class per file; do not co-locate `Session` and `Insight` even though they're related.

### File organization

- `FocusFrame/Models/<TypeName>.swift` — one `@Model` per file.
- `FocusFrame/Services/<ServiceName>.swift` — one service per file. Service-private helper types live in the same file only if they're trivial (`<30 lines`) and not used elsewhere.
- `FocusFrame/State/AppState.swift` — single file.
- `FocusFrame/Features/<Feature>/<View>.swift` — one view per file. Feature-scoped components nest under `FocusFrame/Features/<Feature>/Components/`.
- `FocusFrame/Common/` — design tokens, shared extensions, formatters. Anything used by 2+ features.
- `FocusFrameLiveActivity/` — widget extension files, kept flat.

### Concurrency

- `@MainActor` on `AppState` and on any type touching SwiftData via `ModelContext` (which is main-actor-bound).
- Services that do networking are non-isolated and use `async` methods; they must be `Sendable`.
- No `DispatchQueue.main.async` — replace with `await MainActor.run { … }` or annotate the type/method `@MainActor`.
- `Task { … }` at view boundaries (`.task { }` modifier preferred). Capture `[weak self]` only where the closure outlives the owner.

### Naming

- Types: `UpperCamelCase`, descriptive. `SessionManager`, not `SessionMgr` or `SM`.
- Methods: imperative verb-first. `startSession()`, `requestInsight(for:)`, `persist(_:)`.
- Booleans: `is…`, `has…`, `should…`. `isActive`, `hasInsight`, `shouldShowOnboarding`.
- Async methods: no `async` suffix unless a sync overload coexists. `loadSessions()`, not `loadSessionsAsync()`.
- SwiftData properties: noun, no Hungarian prefix. `goal`, `startedAt`, `endedAt`, `distractionCount`.

## When in doubt

If a style question isn't answered here or in swiftui-pro, prefer the option that reduces ambiguity for a future reader. When two options are equally clear, match the surrounding code.
