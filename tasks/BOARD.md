# Task Board

Index of all tasks. The **Status line inside each task file is the source of
truth**; whoever changes a status updates this row in the same step.
Lifecycle and who may set each status: `WORKFLOW.md` §3.

**Next ID:** T-0010

## Active

| ID | Title | Status | Priority | Depends on | Next step by |
|---|---|---|---|---|---|
| [T-0002](T-0002-game-window-closed-while-capturing.md) | Closing the game while translating must stop cleanly and tell the user | REVIEW (committed `275e90d`) | P1 | — | Owner (AC-4, AC-5 manual) → Cowork DONE |
| [T-0003](T-0003-stop-during-start-leaves-orphan-stream.md) | Stopping while a session is starting must not leave capture running | REVIEW (committed `99117eb`) | P1 | T-0001 ✅ | Owner (AC-4 manual) → Cowork DONE |
| [T-0004](T-0004-build-sh-must-fail-on-signing-error.md) | build.sh must stop loudly when code signing fails | REVIEW (committed `7a9618f`) | P1 | — | Cowork (review) + owner (AC-4, AC-5 manual) |
| [T-0005](T-0005-ocr-continuation-resumed-once.md) | OCR must never resume its continuation twice | REVIEW (committed `878b62f`) | P2 | — | Cowork (review) + owner (AC-3 manual) |
| [T-0006](T-0006-menu-shows-live-errors-and-status.md) | The menu must show the current error, status and stats | REVIEW | P2 | — | Cowork (review) + owner (AC-3 manual) |
| [T-0007](T-0007-cancel-region-selector-restores-overlay.md) | Cancelling region selection must bring the overlay back | READY | P2 | — | Claude Code |
| [T-0008](T-0008-batch-fallback-no-request-storm.md) | A failed batch request must not turn into a storm of per-line requests | READY | P2 | — | Claude Code |
| [T-0009](T-0009-multi-monitor-coordinates.md) | Overlay, panel and region selector placed correctly on multi-monitor setups | READY | P3 | — | Claude Code |

## Closed

<!-- Move rows here when a task becomes DONE, REVIEW_FAILED or CANCELLED. -->

| ID | Title | Final status | Closed | Commit | Follow-up |
|---|---|---|---|---|---|
| [T-0001](T-0001-start-failure-leaves-running-state.md) | A failed start must not leave the app stuck in "running" | DONE | 2026-09-23 | `4df883b` | — |
