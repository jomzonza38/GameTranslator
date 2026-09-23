# T-0008 — A failed batch request must not turn into a storm of per-line requests

| Field | Value |
|---|---|
| **Status** | REVIEW |
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

- **One rule for both providers:** `BatchFallback.shouldRetryPerLine(after:)` (new,
  in `LLMChatProvider.swift`). **No per-line fallback** — the error is rethrown
  (Req 1):
  - `rateLimitExceeded`, `missingApiKey`, `quotaExceeded`, `unsupportedLanguage`
  - `translationFailed` whose message starts with `HTTP 401`, `HTTP 403` or `HTTP 429`
    (OpenAI, Claude and Google Free report HTTP errors as `"HTTP <status>…"`; no typed
    auth error exists, and adding one would touch other providers and error texts)
  - `CancellationError`, `Task.isCancelled` (a stop), `URLError.cancelled` — bare or
    wrapped in `networkError`
  - offline errors: `notConnectedToInternet`, `networkConnectionLost`,
    `cannotFindHost`, `cannotConnectToHost`, `dnsLookupFailed`,
    `userAuthenticationRequired`
- **Req 3 decision — transient network errors:** *offline* errors are rethrown (every
  per-line request would fail the same way; the pipeline retries after its 3 s
  back-off). **Timeouts and other errors (e.g. HTTP 5xx, invalid response) still fall
  back**: a large batch can time out or be rejected where single short lines succeed,
  which is the case the fallback exists for.
- **LLMChatProvider.translateBatch:** the `catch` now rethrows unless the rule allows
  a retry. A reply that can't be parsed still falls through to `translateEach`
  (Req 2, unchanged).
- **GoogleFreeProvider.translateBatch:** restructured so only the batch request is
  inside `do/catch`. Before, the parallel fallback for a split mismatch ran *inside*
  the `do`, so if those per-line requests failed, the `catch` sent **all of them
  again** — a second storm. Now: batch fails → rule decides (parallel or rethrow);
  split mismatch → parallel once (Req 2).
- **Testability:** `GoogleFreeProvider.init(configuration:)` takes an optional
  `URLSessionConfiguration` (default `.default`, same timeouts and connection limit
  applied as before), so tests can plug in a stub `URLProtocol`. The app still calls
  `GoogleFreeProvider()`.
- **Error texts unchanged (Req 4):** errors are rethrown as they are.

## Result

**Outcome:** PASS — all criteria are `[test]`/`[code]`/`[build]` and pass
**Version:** 1.11.17 → 1.11.18
**Commit:** `6e589be`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `BatchFallbackTests.testLLMRateLimitIsRethrownWithoutPerLineRequests`: throws `rateLimitExceeded`, `complete` called once. |
| AC-2 | ✅ pass | `testLLMMissingApiKeyIsRethrownWithoutPerLineRequests`, `testLLMCancellationIsRethrownWithoutPerLineRequests` (+ `testLLMHTTP401…`): each throws, `complete` called once. |
| AC-3 | ✅ pass | `testLLMMissingNumberedLineFallsBackToPerLine`: reply lacks `[3]` → 3 translations, `complete` called 4× (1 batch + 3 per-line). |
| AC-4 | ✅ pass | Same rule in `GoogleFreeProvider`; tested through a stub `URLProtocol` (no real network): 429 → rethrown after 1 request; 403 → 1 request; split mismatch → 4 requests, 3 results; HTTP 500 → still falls back (4 requests). |
| AC-5 | ✅ pass | `Executed 74 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

Also `testNoPerLineRetryForRefusalsCancelAndOffline` /
`testPerLineRetryForTimeoutsServerErrorsAndBadReplies` pin down the rule itself.

### Build & test
```
Executed 74 tests, with 0 failures (0 unexpected) in 0.529 (0.569) seconds
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                        |  2 +-
 Sources/Providers/GoogleFreeProvider.swift  | 32 ++++++++++-------
 Sources/Providers/LLMChatProvider.swift     | 46 ++++++++++++++++++++++++-
 Tests/BatchFallbackTests.swift              | (new, 11 tests)
 tasks/BOARD.md, tasks/T-0008-…md            | (status + this report)
```

### Manual checks for the owner
None required by the spec. Optional: translate with OpenAI and an invalid key —
`GameTranslator.log` should show one failed request per retry (every ~3 s), not one
per on-screen line.

### Proposed follow-ups
- Providers report HTTP failures only as text (`"HTTP 401: …"`); a typed
  `TranslationError.http(status:)` would make rules like this one less string-based.
  Touches all providers and `TranslationProvider.swift` → separate task if wanted.

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-23 | → READY | Cowork | created from code audit v1.11.11 |
| 2026-09-23 | READY → IN_PROGRESS | Claude Code | started |
| 2026-09-23 | IN_PROGRESS → REVIEW | Claude Code | all ACs pass (no manual ACs) |
