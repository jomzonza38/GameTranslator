# T-0008 — A failed batch request must not turn into a storm of per-line requests

| Field | Value |
|---|---|
| **Status** | READY |
| **Type** | fix |
| **Priority** | P2 |
| **Version impact** | patch |
| **Milestone** | M2 — Reliability & UX |
| **Depends on** | — |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-23 by Cowork (code audit v1.11.11, finding 8) |

## Objective
When a batch translation fails because of rate limiting, a bad API key, quota or
cancellation, the app must not immediately send one request per line in parallel.
That makes rate limits worse (Google Free may block the user) and costs extra money
with OpenAI/Claude.

## Context
- `GoogleFreeProvider.translateBatch` (`Sources/Providers/GoogleFreeProvider.swift`)
  catches **every** error from the combined request and calls `translateParallel`
  (N concurrent requests).
- `LLMChatProvider.translateBatch` (`Sources/Providers/LLMChatProvider.swift`) also
  swallows every error from `complete(...)` and calls `translateEach` (N requests).
- The per-line fallback is still wanted when the batch *succeeded* but could not be
  split/parsed (line count mismatch, bad numbering) — that is its purpose.
- The pipeline already backs off per text after a thrown error
  (`RegionPipelineState.failedAt`, 3 s).

## Requirements
1. Rate limit (429 / `rateLimitExceeded`), auth errors (401/403 / `missingApiKey`),
   quota errors and task cancellation from the batch request are thrown to the
   caller without per-line fallback.
2. Split/parse mismatches still fall back to per-line translation (unchanged).
3. Transient network errors/timeouts: Claude Code decides (fallback or rethrow) and
   records the choice in Implementation Notes.
4. Error messages shown to the user are unchanged.

## Out of scope
- DeepL and Google Cloud providers (no such fallback).
- Retry/back-off policy in the pipeline; caching of fallback text (backlog).

## Constraints
- CLAUDE.md stability rules apply.

## Files / Modules
- `Sources/Providers/GoogleFreeProvider.swift`
- `Sources/Providers/LLMChatProvider.swift`
- `Tests/GoogleFreeProviderTests.swift`, `Tests/LLMPromptTests.swift` or a new test file

## Acceptance Criteria
- **AC-1** [test] With a fake LLM provider whose `complete` throws
  `rateLimitExceeded`, `translateBatch` of 3 texts throws it and `complete` was
  called exactly once.
- **AC-2** [test] Same for `missingApiKey` and for `CancellationError`.
- **AC-3** [test] With a fake LLM reply missing one numbered line, `translateBatch`
  falls back to per-line calls and returns 3 translations.
- **AC-4** [code] Google Free follows the same rule (rate limit/cancel rethrown,
  split mismatch → parallel), with a test if the network call can be injected;
  otherwise explain why.
- **AC-5** [build] Unit tests and Release build succeed.

## Testing Requirements
- AC-1…AC-3 unit tests (no real network).

## Definition of Done
- [ ] All acceptance criteria pass
- [ ] Unit tests added; full suite passes
- [ ] Release build succeeds
- [ ] Version bumped per CLAUDE.md (patch)
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
| 2026-09-23 | → READY | Cowork | created from code audit v1.11.11 |
