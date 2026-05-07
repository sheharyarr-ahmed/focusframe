# Anthropic Claude API contract

Authoritative reference for `ClaudeService`. Any drift between this document and the implementation is a bug — fix the document or fix the code, but do not let them disagree silently.

## Endpoint

- **Base URL**: `https://api.anthropic.com`
- **Path**: `/v1/messages`
- **Method**: `POST`

## Headers

| Header | Value | Notes |
| --- | --- | --- |
| `x-api-key` | `<user-supplied key>` | Loaded from Keychain at request time. Never logged. |
| `anthropic-version` | `2023-06-01` | Pin the version explicitly; do not omit. |
| `content-type` | `application/json` | |

## Model

`claude-sonnet-4-5` — locked. Do not silently change. Model swap requires a feature-flag rollout and explicit user approval; track in the PR body's "Architecture impact" section.

## System prompt (verbatim)

```
You are a focused-work coach. After a user finishes a focus session, you write a short reflective insight grounded in the session details they share. Use the second person. Write 2–3 sentences in plain prose — no emojis, no bullet points, no headings, no markdown. Be specific to what they did. Acknowledge the effort honestly; do not flatter, and do not lecture. If the distraction count was high or the session was short, be supportive without being saccharine. End with a forward-looking sentence that names what they might pay attention to next time.
```

Stored as a Swift string literal constant in `ClaudeService.swift`. Treat changes to this prompt as a behavior change — bump a `promptVersion` integer alongside any edit so insights from different prompt versions stay distinguishable in logs.

## User message template

The user message is plain text (not JSON-as-text). Render this template with the session's actual values:

```
Goal: {goalText}
Duration: {durationMinutes} minutes
Time of day: {timeOfDayBucket}
Distractions: {distractionCount}
Day of week: {dayOfWeekName}
```

Where:

- `{goalText}` — the literal goal string the user typed
- `{durationMinutes}` — integer minutes, computed from `endedAt - startedAt`
- `{timeOfDayBucket}` — one of `morning` / `afternoon` / `evening` / `late-night` (boundaries defined in `data-models.md`)
- `{distractionCount}` — integer count of foreground/background transitions during the session
- `{dayOfWeekName}` — `"Monday"` … `"Sunday"`, formatted via `Calendar.current` and a `DateFormatter` with `EEEE`

Sanitize `{goalText}` only minimally: trim leading/trailing whitespace, cap at 280 characters. Do NOT escape characters — Anthropic's API accepts arbitrary UTF-8 in message content.

## Request body

```json
{
  "model": "claude-sonnet-4-5",
  "max_tokens": 200,
  "system": "<system prompt verbatim>",
  "messages": [
    {
      "role": "user",
      "content": "Goal: Draft Q3 budget memo\nDuration: 45 minutes\nTime of day: morning\nDistractions: 2\nDay of week: Tuesday"
    }
  ]
}
```

`max_tokens: 200` is comfortably above the expected 2–3 sentence response (~80 tokens) and gives room for the model to finish a thought without truncation. Do not raise without a reason — a higher cap costs more and tempts the model to ramble.

No `temperature` override — use the default. No `tool_use`, no `stream` (v1 displays insights once the response is complete).

## Response shape (success)

```json
{
  "id": "msg_01...",
  "type": "message",
  "role": "assistant",
  "model": "claude-sonnet-4-5",
  "content": [
    {
      "type": "text",
      "text": "You stayed with the budget memo for forty-five focused minutes despite two interruptions, which is a real result. The fact that you did this in the morning suggests your sharpest hours are working in your favor; treat that window as protected. Tomorrow, see if closing Slack before you start cuts those interruptions to zero."
    }
  ],
  "stop_reason": "end_turn",
  "stop_sequence": null,
  "usage": { "input_tokens": 92, "output_tokens": 71 }
}
```

`ClaudeService` extracts `content[0].text` (asserting `content[0].type == "text"`) and inserts an `Insight` row with:

- `sessionID` = the originating `Session.id`
- `text` = the extracted text, trimmed
- `model` = `"claude-sonnet-4-5"`
- `generatedAt` = `.now`

## Error handling

| HTTP status | Cause | `ClaudeServiceError` case | Recovery |
| --- | --- | --- | --- |
| (pre-flight) | Keychain returned `nil` — no key configured | `.missingAPIKey` | Surface a banner in `SettingsView` prompting key entry. No HTTP request was made. |
| 401 | Server rejected the key (invalid / revoked) | `.invalidAPIKey` | Surface a banner in `SettingsView` prompting re-entry. Clear the Keychain entry. |
| 403 | Permissions / org-level block | `.forbidden` | Surface error; user must contact Anthropic. |
| 429 | Rate limited | `.rateLimited(retryAfter:)` | Read `retry-after` header. Exponential backoff: retry once after the header value (or 4s default), then twice more at 2× / 4× the previous delay. After 3 failures, give up for this session. |
| 5xx | Server error | `.serverError(statusCode:)` | Persist the `Session` without an `Insight`. On next app launch, scan for sessions without insights from the last 24h and offer a "Generate insight" affordance. Do not auto-retry on a timer — that drains battery. |
| Network error / timeout | Offline, DNS, etc. | `.networkUnavailable(underlying:)` | Same as 5xx: persist the session, offer manual retry. |
| Decoding error | Schema drift | `.decodingFailed(underlying:)` | Log at `.error`. Persist the session without an insight. Do not retry; the schema fix is a code change. |

`ClaudeService.generateInsight(for:)` throws `ClaudeServiceError` cases. `.missingAPIKey` is distinct from `.invalidAPIKey` — the former means the user has not yet entered a key (no HTTP request was made), the latter means the key was rejected by the server.

## Storage rules

- Insights persist via the `Insight` SwiftData model (see `agent_docs/data-models.md`).
- The API key persists only in Keychain (account `com.sheryahmed.focusframe`, service `anthropic-api-key`). It is never written to UserDefaults, AppStorage, NSUbiquitousKeyValueStore, files, plists, or logs.
- The full Claude response body is NOT persisted — only the extracted `text`. Token usage counts may be logged at `.debug` for cost monitoring; do not surface them to users.
- The user message (with the goal text) is NOT persisted on the request side — only the resulting insight. The original goal text already lives on `Session.goalText`.

## Logging policy

- Subsystem: `com.sheryahmed.focusframe`, category: `claude`.
- `.info`: request initiated (without body), response status code, elapsed time.
- `.debug`: first 80 chars of the response text, token counts.
- `.error`: error case + status code on failure.
- **Never logged at any level**: API key, full request body, full response text, full goal text.

```swift
logger.info("claude-request session=\(session.id, privacy: .public) status=\(response.statusCode)")
logger.error("claude-error case=\(error.tag, privacy: .public)")
```

Use `privacy: .public` only for non-PII fields. Default OSLog privacy redacts user-supplied strings — keep it that way for `goalText` and response `text`.

## Security checklist

Run before every PR that touches `ClaudeService` or `KeychainService`:

- [ ] `git grep -n 'sk-ant'` returns no hits in tracked files
- [ ] `git grep -n 'anthropic.com'` returns hits only in `ClaudeService.swift`, this document, and any `URLSession` request-construction site
- [ ] `git grep -n 'apiKey\|api_key\|API_KEY'` shows the key referenced only by name, never as a string literal
- [ ] `Secrets.xcconfig` is in `.gitignore` (already present)
- [ ] `Info.plist` and `Settings.bundle` contain no key

If any of these fail, block the merge until resolved.

## Cost & rate-limiting note

Sonnet 4.5 input ~$3/MTok, output ~$15/MTok at this writing. Per-session usage is roughly 100 input + 80 output tokens — call it $0.0015 per insight. At 5 sessions/day per user, $0.20/month/user. Well within the personal-use envelope. If usage grows, revisit with a Haiku tier for non-premium users.

For development, set a low monthly cap on the API key in the Anthropic console so a runaway loop can't drain the account.
