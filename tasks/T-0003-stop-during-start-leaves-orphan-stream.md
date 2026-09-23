# T-0003 — Stopping while a session is starting must not leave capture running

| Field | Value |
|---|---|
| **Status** | PLANNED |
| **Type** | fix |
| **Priority** | P1 |
| **Version impact** | patch |
| **Milestone** | M1 — Stability |
| **Depends on** | T-0001 |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-23 by Cowork (code audit v1.11.11, finding 2) |

## Objective
If the user stops (⌃⌥T, menu, Quit) while a session is still starting, the app must
end fully stopped: no capture stream left running, no screen-recording indicator,
and the next start must capture the window the user picks. Today a stop that lands
during start can leave a hidden stream running on the old window.

## Context
- `PipelineCoordinator.start(window:)` sets `isRunning = true` and then awaits
  `screenCapture.startCapture(...)`. `stop()` can run during that await.
- `ScreenCaptureService.stopCapture()` returns early when `isCapturing == false`,
  which is still the case while `startCapture` is awaiting `stream.startCapture()`.
  When the await finishes, the service sets `stream` and `isCapturing = true`:
  the stream keeps running although the coordinator is stopped.
- The next `startCapture(window:)` hits `guard !isCapturing else { return }` and
  returns at once — frames keep coming from the **old** window.
- `start` also sets `status = .running` after the await even if stopped meanwhile.
- Depends on T-0001 because both change the start path; do T-0001 first to avoid
  conflicting edits.

## Requirements
1. A stop that happens at any point during start leaves the app idle: no active
   `SCStream`, not running, status idle, overlay/panel hidden.
2. A start after such a stop captures the newly picked window.
3. Start and stop requested repeatedly and quickly never crash or deadlock.

## Out of scope
- Game window closing during capture (T-0002).
- Failed start rollback itself (T-0001).

## Constraints
- CLAUDE.md stability rules apply; no new call that can show the Screen Recording dialog.
- `PipelineCoordinator` is `@MainActor`; `ScreenCaptureService` is not.

## Files / Modules
- `Sources/Services/PipelineCoordinator.swift`
- `Sources/Services/ScreenCaptureService.swift`
- `Tests/…` if the state handling can be tested without a real `SCStream`

## Acceptance Criteria
- **AC-1** [code] `ScreenCaptureService` cannot end with a running stream after a
  stop was requested while it was starting, and `startCapture` for a new window is
  not silently skipped because of a stale stream.
- **AC-2** [code] `PipelineCoordinator.start` does not report `.running` (or leave
  `isRunning == true`) when a stop happened during start.
- **AC-3** [code] No new call that can show the Screen Recording dialog.
- **AC-4** [manual] Steps: 1) press ⌃⌥T, pick a game window, and immediately press
  ⌃⌥T again (repeat 5 times). Expected: after the last stop the purple
  screen-recording indicator in the menu bar disappears within a few seconds and
  the app is idle. 2) Pick a *different* window. Expected: that window is translated.
- **AC-5** [build] Unit tests and Release build succeed.

## Testing Requirements
- Unit test if the start/stop sequencing can be isolated; otherwise explain why.
- Owner runs AC-4.

## Definition of Done
- [ ] All acceptance criteria pass (`[manual]` ones confirmed by the owner)
- [ ] Unit tests added/updated as required; full suite passes
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
| 2026-09-23 | → PLANNED | Cowork | created from code audit; READY once T-0001 is DONE |
