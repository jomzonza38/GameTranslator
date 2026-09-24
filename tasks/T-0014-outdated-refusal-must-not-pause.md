# T-0014 — A refusal from an outdated request must not pause translation

| Field | Value |
|---|---|
| **Status** | PLANNED |
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

## Result

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → PLANNED | Cowork | from T-0012 review; READY when T-0012 is DONE |
