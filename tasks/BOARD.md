# Task Board

Index of all tasks. The **Status line inside each task file is the source of
truth**; whoever changes a status updates this row in the same step.
Lifecycle and who may set each status: `WORKFLOW.md` §3.

**Next ID:** T-0015

## Active

| ID | Title | Status | Priority | Depends on | Next step by |
|---|---|---|---|---|---|
| [T-0010](T-0010-api-key-fields-save-cleanly.md) | API key fields must save cleanly: trimmed, not on every keystroke, no session leak | REVIEW (committed `0f15d05`) | P2 | — | Owner (AC-4 manual) → Cowork DONE |
| [T-0011](T-0011-cache-per-provider-no-chatter-caching.md) | Cached translations must belong to the provider and language that made them | REVIEW (committed `5beb3ad`) | P2 | — | Owner (AC-4 manual) → Cowork DONE |
| [T-0012](T-0012-pause-on-refused-api-key.md) | Stop retrying while the API key is refused, and say so | REVIEW (committed `2cd55eb`) | P2 | T-0010 (in REVIEW) | Owner (AC-3 manual) → Cowork DONE |
| [T-0014](T-0014-outdated-refusal-must-not-pause.md) | A refusal from an outdated request must not pause translation | REVIEW (committed `a4a0760`) | P3 | T-0012 (in REVIEW) | Cowork (review) |

## Closed

<!-- Move rows here when a task becomes DONE, REVIEW_FAILED or CANCELLED. -->

| ID | Title | Final status | Closed | Commit | Follow-up |
|---|---|---|---|---|---|
| [T-0001](T-0001-start-failure-leaves-running-state.md) | A failed start must not leave the app stuck in "running" | DONE | 2026-09-23 | `4df883b` | — |
| [T-0008](T-0008-batch-fallback-no-request-storm.md) | A failed batch request must not turn into a storm of per-line requests | DONE | 2026-09-23 | `6e589be` | — |
| [T-0002](T-0002-game-window-closed-while-capturing.md) | Closing the game while translating must stop cleanly and tell the user | DONE | 2026-09-24 | `275e90d` | — |
| [T-0005](T-0005-ocr-continuation-resumed-once.md) | OCR must never resume its continuation twice | DONE | 2026-09-24 | `878b62f` | — |
| [T-0009](T-0009-multi-monitor-coordinates.md) | Overlay, panel and region selector placed correctly on multi-monitor setups | DONE | 2026-09-24 | `7574368` | — |
| [T-0003](T-0003-stop-during-start-leaves-orphan-stream.md) | Stopping while a session is starting must not leave capture running | DONE | 2026-09-24 | `99117eb` | — |
| [T-0004](T-0004-build-sh-must-fail-on-signing-error.md) | build.sh must stop loudly when code signing fails | DONE | 2026-09-24 | `7a9618f` | — |
| [T-0006](T-0006-menu-shows-live-errors-and-status.md) | The menu must show the current error, status and stats | DONE | 2026-09-24 | `0c8273a` | — |
| [T-0007](T-0007-cancel-region-selector-restores-overlay.md) | Cancelling region selection must bring the overlay back | DONE | 2026-09-24 | `a6be575` | — |
| [T-0013](T-0013-tests-do-not-write-owner-log.md) | Unit tests must not write to the owner's GameTranslator.log | DONE | 2026-09-24 | `7c3eced` | — |
