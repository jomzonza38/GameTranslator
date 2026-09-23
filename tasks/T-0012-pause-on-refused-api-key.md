# T-0012 — Stop retrying while the API key is refused, and say so

| Field | Value |
|---|---|
| **Status** | PLANNED |
| **Type** | fix |
| **Priority** | P2 |
| **Version impact** | patch |
| **Milestone** | M3 — Providers & settings hygiene |
| **Depends on** | T-0010 |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-24 by Cowork (code audit v1.11.11 backlog + owner testing) |

## Objective
When the provider refuses the API key (HTTP 401/403, missing key) or the quota is used
up, the app must stop sending requests and tell the user what to fix, instead of
retrying every ~3 s for as long as text is on screen.

## Context
- Seen in the owner's test 2026-09-24 00:10: invalid Claude key → `✗ Translation error:
  … HTTP 401 …` every ~3.4 s, indefinitely (`PipelineCoordinator.retryDelay = 3`,
  per-text `failedAt` back-off).
- Errors are shown in the menu since T-0006 (`lastError`). T-0008 already stops
  per-line fallback on these errors; `BatchFallback.shouldRetryPerLine` classifies them.
- Depends on T-0010 because that task changes when/how a new key is applied, which is
  the natural "retry now" signal.

## Requirements
1. After an auth error (401/403 / `missingApiKey`) or quota error, translation requests
   pause: no further requests until the key or provider changes (or the user stops and
   starts again).
2. While paused, the menu shows a Thai message saying the key was refused / quota used
   up and which provider (Claude Code picks wording); capture and overlay stay as they are.
3. Saving a new key or switching provider resumes translation automatically.
4. Rate limits (429) and network errors keep the current back-off (not paused).

## Out of scope
- Automatic key validation in Settings; notifications outside the menu.

## Constraints
- CLAUDE.md stability rules apply.

## Files / Modules
- `Sources/Services/PipelineCoordinator.swift`, `Sources/Services/TranslationService.swift`
- `Sources/Providers/LLMChatProvider.swift` (`BatchFallback`) if the classification is reused
- `Tests/…`

## Acceptance Criteria
- **AC-1** [test] The pause decision: 401/403/missing key/quota → pause; 429, timeout, 5xx → no pause.
- **AC-2** [code] While paused no provider request is made; key or provider change clears the pause.
- **AC-3** [manual] Steps: 1) set an invalid Claude key, translate a game for 30 s. Expected: log shows one (or very few) 401 lines, not one every 3 s; menu shows the Thai message. 2) Enter the real key. Expected: translation resumes without restarting.
- **AC-4** [build] Unit tests and Release build succeed.

## Testing Requirements
- AC-1 unit test; owner runs AC-3.

## Definition of Done
- [ ] All acceptance criteria pass (`[manual]` ones confirmed by the owner)
- [ ] Unit tests added/updated as required; full suite passes
- [ ] Release build succeeds
- [ ] Version bumped per CLAUDE.md
- [ ] `git diff` contains only changes justified by this task
- [ ] Result section complete; Cowork review passed

---

## Questions

## Implementation Notes

## Result

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → PLANNED | Cowork | created for M3; READY when T-0010 is DONE |
