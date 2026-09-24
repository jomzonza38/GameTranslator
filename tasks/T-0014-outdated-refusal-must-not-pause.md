# T-0014 — A refusal from an outdated request must not pause translation

| Field | Value |
|---|---|
| **Status** | REVIEW |
| **Type** | fix |
| **Priority** | P3 |
| **Version impact** | patch |
| **Milestone** | M3 — Providers & settings hygiene |
| **Depends on** | T-0012 |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-24 by Cowork (review of T-0012) |

## Objective
If the user fixes the API key or switches provider while a request is still in flight,
a 401/403/quota reply to that **old** request must not pause translation. Today it
can, and the app then stays paused with a working key until the user changes the key
again or stops and starts.

## Context
- `PipelineCoordinator.translatePending` awaits `translationService.translateBatch`.
  During that await, Settings can call `updateProvider()` on the main actor. That
  happens on key save (T-0010: Return, focus loss, 1 s pause) or on a provider pick.
- `updateProvider()` clears `isTranslationPaused` only if it is already set. A
  refusal that arrives afterwards sets it again (`catch` in `translatePending`),
  using the **new** provider's name in the message.
- Likely trigger: the owner types or pastes a key → the 1 s pause-save sends a
  half-typed or wrong key → the user corrects it while that request is in flight.
- Hint: remember which provider/key "generation" a request was sent with, and only
  pause (and only show the refusal) if it is still current. The scope string from
  T-0011 is not enough on its own: a key change keeps the same provider.

## Requirements
1. A key/quota refusal pauses translation only if the provider and key are unchanged
   since that request was sent.
2. A refusal from an outdated request doesn't set the Thai pause message either (a
   normal back-off for those texts is fine).
3. T-0012 behaviour for a current request is unchanged.

## Out of scope
- Cancelling in-flight requests on provider change.

## Constraints
- CLAUDE.md stability rules apply.

## Files / Modules
- `Sources/Services/PipelineCoordinator.swift` (maybe `TranslationService.swift`)
- `Tests/…`

## Acceptance Criteria
- **AC-1** [test] or [code] A refusal for a request sent before `updateProvider()` does not set the pause; one for the current provider/key does. (Use a unit test if the decision can be extracted; otherwise point to it in the diff.)
- **AC-2** [code] The pause message always names the provider that actually refused.
- **AC-3** [build] Unit tests and Release build succeed.

## Testing Requirements
- AC-1 as above. No manual step: the timing is hard to reproduce by hand.

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

- **Started while PLANNED** on the owner's direct instruction; builds on T-0012 (in
  REVIEW, committed `2cd55eb`).
- **Generation (hint followed):** `PipelineCoordinator.providerGeneration` goes up by
  one in every `updateProvider()` — provider picked, key saved (T-0010), start. This
  covers key changes that keep the same provider, which T-0011's scope string can't
  see.
- **Before each request**, `translatePending` records the generation plus the
  provider's name and whether it uses a key.
- **After a failure**, the new pure `TranslationRefusal.outcome(...)` decides:
  - `.pause(message:)` — a refusal and the generation is still current. Pause and
    show the message (T-0012 behaviour, Req 3).
  - `.ignoreOutdated` — a refusal, but the key/provider changed while it was in flight.
    **No pause and no menu message** (Req 1, 2). The texts keep the normal 3 s back-off
    (`failedAt`, set as before), and the log says `Refusal was for the previous
    key/provider (…) — not pausing`.
  - `.notARefusal` — `lastError` = the error, normal back-off (unchanged).
- **AC-2:** the pause message uses the provider name recorded **when the request was
  sent**, not `currentProviderName` read after the await. In practice it can only be
  the current provider now (any change moves the generation → `.ignoreOutdated`), but
  it can't be wrong by construction.
- **Small remaining window (accepted):** `TranslationService.translateBatch` reads its
  `provider` when the call starts running, which can be a moment after the coordinator
  recorded the generation. If `updateProvider()` lands exactly in that gap, a refusal
  by the *new* key is treated as outdated once. The result is only one extra request
  after the 3 s back-off, and then the next refusal pauses normally. It never causes a
  wrong pause.

## Result

**Outcome:** PASS — all criteria are `[test]`/`[code]`/`[build]` and pass
**Version:** 1.11.23 → 1.11.24
**Commit:** `a4a0760`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `TranslationRefusalTests.testRefusalSentBeforeUpdateProviderIsIgnored` (401 and quota with generation 3 → current 4 → `.ignoreOutdated`), `testRefusalOfCurrentKeyPauses` (3 → 3 → `.pause`), `testOtherErrorsAreNotRefusalsWhateverTheGeneration`. Coordinator uses it in `translatePending`'s `catch`; `updateProvider()` increments `providerGeneration`. |
| AC-2 | ✅ pass | Message built from `requestProvider` (captured before the request); `testPauseMessageNamesTheProviderThatRefused`. |
| AC-3 | ✅ pass | `Executed 96 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 96 tests, with 0 failures (0 unexpected) in 0.400 (0.449) seconds
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                        |  2 +-
 Sources/Providers/LLMChatProvider.swift     | 25 ++++  TranslationRefusal.outcome
 Sources/Services/PipelineCoordinator.swift  | 30 +++--  providerGeneration, request snapshot, outcome switch
 Tests/TranslationRefusalTests.swift         | 45 ++++  (4 new tests)
 tasks/BOARD.md, tasks/T-0014-…md            | (status + this report)
```

### Manual checks for the owner
None (timing is hard to reproduce by hand, as the spec says).

### Proposed follow-ups
- none

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → PLANNED | Cowork | from T-0012 review; READY when T-0012 is DONE |
| 2026-09-24 | PLANNED → IN_PROGRESS | Claude Code | started on the owner's direct instruction ("ทำ T-0014") while T-0012 is in REVIEW (committed `2cd55eb`) |
| 2026-09-24 | IN_PROGRESS → REVIEW | Claude Code | all ACs pass (no manual ACs) |
