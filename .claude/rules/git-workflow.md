# Git workflow

## Branch model

One feature branch per sprint. Built up locally, opened as a single PR into `main` when the sprint is complete. No long-lived sprint branches on origin, no nested sub-PRs.

| Sprint | Branch name |
| --- | --- |
| 1 — Foundation (models, timer, history skeleton) | `sprint-1-foundation` |
| 2 — Intelligence (Keychain, Claude API, insights) | `sprint-2-intelligence` |
| 3 — Live Activities (widget extension, lock screen, Dynamic Island) | `sprint-3-live-activities` |
| 4 — Polish (charts, accessibility, performance, App Store assets) | `sprint-4-polish` |

`main` is always shippable. Direct commits to `main` are forbidden — the only path is a merged PR.

If a hotfix or one-off is needed outside a sprint, create `fix/<short-description>` or `chore/<short-description>` and open a PR the same way.

## Commit format — Conventional Commits

```
<type>(<scope>): <imperative summary>

<optional body explaining the why>
```

Commit messages should NOT include AI co-author trailers. The git author is Sheharyar Ahmed only. Do not append `Co-Authored-By: Claude …`, `Generated-By: …`, or any equivalent attribution line — neither in commit bodies nor in PR descriptions generated via `gh pr create`.

### Types

| Type | When |
| --- | --- |
| `feat` | New user-visible capability |
| `fix` | Bug fix |
| `refactor` | Code change that doesn't alter behavior |
| `perf` | Performance improvement with measurable change |
| `test` | Adding or improving tests |
| `docs` | Documentation only |
| `chore` | Tooling, config, dependency bumps |
| `style` | Formatting, lint fixes (no logic change) |

### Scopes (by architectural layer)

`model`, `service`, `state`, `view`, `widget`, `rules`, `docs`, `ci`, `xcode`.

Pick the layer the change centers on. Multi-layer changes pick the most-impacted layer in the subject and mention others in the body.

### Examples

```
feat(service): implement ClaudeService with async/await request flow

Adds ClaudeService.requestInsight(for:) calling claude-sonnet-4-5 via
URLSession. Maps 401/429/5xx to ClaudeServiceError cases.
```

```
fix(view): prevent TimerView from instantiating SessionManager directly
```

```
refactor(state): hoist distraction-count tracking into AppState
```

```
docs(rules): clarify SwiftData mutation boundary in architecture.md
```

## Pull request template

Title: `<type>(<scope>): <imperative summary>` — same format as commits, ≤ 72 chars.

Body:

```markdown
## Summary

<2–4 bullets on what changed and why. Focus on the why.>

## Architecture impact

<Which of the 5 layers does this touch? Any new cross-layer dependencies?
If unchanged, write "No layer changes — feature additions within Views only."
focusframe-architect should be able to verify this.>

## Test plan

- [ ] Unit tests added/updated for new service logic
- [ ] UI tests added/updated for new user flows
- [ ] `xcodebuild test` passes locally on iPhone 17 Pro simulator
- [ ] `swiftlint --strict` passes
- [ ] Manual smoke check on simulator: <list scenarios>

## Screenshots / recording

<Required for any view-layer change. Lock-screen and Dynamic Island
screenshots required for any widget-target change.>

## Notes

<Anything reviewers should know — known limitations, follow-up issues,
schema migrations, secrets handling.>
```

Save the body to `.github/pull_request_template.md` so `gh pr create --body-file` picks it up automatically.

## What never to do

- **Force-push to `main`.** Denied at the settings level (`.claude/settings.json`) and forbidden by policy.
- **Amend or rebase a pushed commit.** If you need to fix a published commit, open a follow-up commit. Force-with-lease on a sprint branch is fine before the PR is opened, but never after review has started.
- **Merge without review.** Even solo. Open the PR, sleep on it, re-read your own diff, then merge.
- **Commit `Secrets.xcconfig`, API keys, `.env*` files, or `APIKeys.swift`.** All are gitignored — keep them that way.
- **Skip pre-commit hooks** (`--no-verify`) or signing (`--no-gpg-sign`). If a hook fails, fix the underlying issue.
- **`git reset --hard` or `git clean -f`** as a shortcut. Stash, branch, or commit first; investigate before discarding.
- **`git push --force` to a branch with an open PR** — rebase locally, then `--force-with-lease` if absolutely necessary, only on your own sprint branch, only before reviewers have commented.

## Merge strategy

- **Squash merge** sprint PRs into `main`. The squashed commit message is the PR title + body summary, preserving the conventional-commits format. Individual local commits during a sprint are scratch history.
- **Tag** each sprint completion: `git tag -a sprint-N -m "Sprint N complete"` and push the tag. Useful for binary-search regression hunting later.

## Initial repo state checklist

When bootstrapping the Xcode project:

- [ ] Create `.github/pull_request_template.md` with the body above
- [ ] Confirm `.gitignore` already covers `Secrets.xcconfig`, `.env*`, `xcuserdata/`, `Package.resolved`, build artifacts
- [ ] First commit on `main` is the Xcode project scaffold + this `.claude/` infrastructure — nothing else
- [ ] Create `sprint-1-foundation` and start there
