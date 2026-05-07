# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project identity

FocusFrame is a native iOS 26 focus-session tracker. The user states a goal in plain English, starts a session timer, and the app tracks focus duration with a Live Activity on the lock screen and Dynamic Island. When a session ends, session metadata (duration, goal, time-of-day, distraction count, day of week) is sent to the Anthropic Claude API to receive a 2–3 sentence reflective insight, persisted locally via SwiftData. A 30-day history view surfaces session count, total focus time, and trend lines.

Distraction detection v1: app foreground/background transitions via `ScenePhase` and `UIApplication.willResignActiveNotification`. ARKit gaze tracking is v2 — out of scope.

## Stack & versions

- **iOS**: 26.0 minimum deployment target (no backward compatibility)
- **Swift**: 6.3 strict concurrency
- **Xcode**: 26.4
- **Frameworks**: SwiftUI 6, SwiftData, ActivityKit, Swift Charts, `os.Logger`
- **Bundle ID**: `com.sheryahmed.focusframe`
- **Widget Extension target**: `FocusFrameLiveActivityExtension` (bundle id `com.sheryahmed.focusframe.LiveActivity`, source folder `FocusFrameLiveActivity/`)
- **Anthropic model**: `claude-sonnet-4-5`
- **Simulator targets**: iPhone 17 Pro, iPhone 17 Pro Max
- **Repo**: `github.com/sheharyarr-ahmed/focusframe`, default branch `main`

## Architecture in one screen

Five layers, strict directional dependency (left depends only on right):

```
Views ──► State (@Observable AppState) ──► Services ──► Data Models (@Model)
                                                                ▲
                                  Live Activity (Widget Ext) ───┘
```

1. **Data Models** — SwiftData `@Model` classes: `Session`, `Goal`, `Insight`. UUID foreign keys, no relationships in v1.
2. **Services** — `SessionManager`, `DistractionDetector`, `ClaudeService`, `KeychainService`. Pure Swift, no UI imports, fully unit-testable.
3. **State** — single `@Observable AppState` owns service instances and exposes view-facing state. Views never instantiate services directly.
4. **Views** — `RootView` (TabView), `TimerView`, `HistoryView`, `SessionDetailView`, `SettingsView`, plus reusable `LiveTimerLabel`.
5. **Live Activity** — separate Widget Extension target (`FocusFrameLiveActivityExtension`, source folder `FocusFrameLiveActivity/`) with `FocusSessionAttributes` and `FocusSessionLiveActivity`. State flows main-app → widget via ActivityKit's native `ContentState` IPC; no App Group in v1 (see Free-tier Apple Developer constraints below).

Full rules and anti-patterns: `.claude/rules/architecture.md`.

### Session state machine

`idle → active → ended`. Only `ended` sessions persist to SwiftData; `active`/`paused` (v2) live in memory on `SessionManager`. Force-kill mid-session loses the in-flight session — deliberate v1 simplification.

## Common commands

> Scheme name `FocusFrame` and widget target `FocusFrameLiveActivity` are placeholders. After bootstrapping the Xcode project, run `xcodebuild -list` and update this file if the actual names differ.

```bash
# Build for simulator
xcodebuild -scheme FocusFrame \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build

# Run unit + UI tests
xcodebuild -scheme FocusFrame \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test

# Boot the simulator and install the latest build
xcrun simctl boot 'iPhone 17 Pro' || true
xcrun simctl launch booted com.sheryahmed.focusframe

# Lint (run before opening a PR)
swiftlint --strict

# Sprint PR
gh pr create --base main --head sprint-N-<name> \
  --title "feat(<scope>): <summary>" \
  --body-file .github/pull_request_template.md
```

## Where to look

| Need | Path |
| --- | --- |
| Project-wide rules (style, architecture, git) | `.claude/rules/` |
| Architecture deep-dive (5 layers, dependencies, state machine) | `.claude/rules/architecture.md` |
| Code style (Swift 6, force-unwrap, networking, logging) | `.claude/rules/code-style.md` |
| Git workflow (sprint branches, Conventional Commits, PR template) | `.claude/rules/git-workflow.md` |
| SwiftUI review reference (Paul Hudson's `swiftui-pro`) | `.claude/skills/swiftui-pro/SKILL.md` |
| Custom architectural advisor subagent | `.claude/agents/focusframe-architect.md` |
| SwiftData schema for `Session`, `Goal`, `Insight` | `agent_docs/data-models.md` |
| Anthropic API contract (system prompt, request shape, error policy) | `agent_docs/claude-api-contract.md` |
| Live Activity / Widget Extension design | `agent_docs/live-activity-design.md` |

## Don't-do list

- **No UIKit** unless a SwiftUI equivalent does not exist. Bridge with `UIViewRepresentable` only when justified.
- **No third-party dependencies** without explicit approval. Default to standard library + Apple frameworks.
- **No force-unwrap, no `try!`, no `as!`.** Optional binding or `??` instead. Crashing on nil is not error handling.
- **No API key in source code, ever.** Not behind `#if DEBUG`, not in committed `xcconfig`, not in `Info.plist`. See `agent_docs/claude-api-contract.md` for the supplied flow.
- **No Combine, no completion handlers** for new code. Modern Swift concurrency (`async`/`await`, actors) only.
- **No multi-type files.** One `struct`/`class`/`enum`/`@Model` per file (protocol + default conformance can co-locate).
- **No service instantiation inside Views.** Views observe `AppState`; `AppState` owns services.
- **No Android, no React Native, no Flutter, no Objective-C.** Native Swift only.

## Brand

Dark `#0F0F0F` background, mint `#6EE7B7` accent. Define as constants in `FocusFrame/Common/DesignTokens.swift`; do not hardcode hex literals in views. Follow Apple Human Interface Guidelines for tap targets, Dynamic Type, VoiceOver — `swiftui-pro/references/design.md` and `accessibility.md` are the source of truth.

## Free-tier Apple Developer constraints

App Groups capability is deferred until a paid Apple Developer Program membership is enabled. Apple rejected registration of the bundle id `com.sheryahmed.focusframe` for an App Group on the free tier (the id is globally claimed in Apple's developer database; only paid-tier accounts can resolve the conflict). ActivityKit's native `ContentState` IPC handles widget state passing for v1 — the widget extension reads `attributes` and `state` from `ActivityViewContext`, not from a shared container. **Do not introduce `UserDefaults(suiteName:)`, App Group file containers, or any `group.com.sheryahmed.focusframe` references in code or entitlements.** Re-evaluate when the paid tier is enabled and a stable bundle id is registered; at that point a new sprint should fold App Groups in for shared SwiftData / shared UserDefaults if needed.

## Sprint plan (reference)

| Sprint | Branch | Scope |
| --- | --- | --- |
| 1 | `sprint-1-foundation` | Data models, `SessionManager`, `TimerView`, basic `HistoryView` |
| 2 | `sprint-2-intelligence` | `KeychainService`, `ClaudeService`, `Insight` flow, `SettingsView` |
| 3 | `sprint-3-live-activities` | Widget Extension, lock-screen + Dynamic Island, distraction detector |
| 4 | `sprint-4-polish` | Swift Charts trends, accessibility audit, performance pass, App Store assets |

One PR per sprint into `main`. Pattern detail: `.claude/rules/git-workflow.md`.
