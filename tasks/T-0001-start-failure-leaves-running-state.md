# T-0001 — A failed start must not leave the app stuck in "running"

| Field | Value |
|---|---|
| **Status** | READY |
| **Type** | fix |
| **Priority** | P2 |
| **Version impact** | patch |
| **Milestone** | M1 — Stability |
| **Depends on** | — |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-23 — draft by Claude Code from the code audit; **Cowork to review and set READY** |

## Objective
If starting a translation session fails (for example the game window was closed
or the game restarted between picking the window and starting capture), the app
must return cleanly to the idle state: no leftover overlay/panel, menu and hotkey
behave as "not running", and the user can pick a window again. This is part of
the owner's stability rule 2 (no broken state after the game is restarted).

## Context
- `PipelineCoordinator.start(window:)` (`Sources/Services/PipelineCoordinator.swift`)
  sets `isRunning = true`, `status = .capturing`, `selectedWindow`, shows the
  overlay or panel, and only **then** awaits `screenCapture.startCapture(...)`.
- If `startCapture` throws, `StatusBarController.startTranslation(window:)` shows the
  alert "เริ่มจับภาพไม่ได้", but nothing resets the coordinator: it stays
  `isRunning == true` with the overlay/panel on screen.
- Found in the 2026-09-23 audit (see `ROADMAP.md` backlog); not yet reproduced in
  the real app.

## Requirements
1. When `start(window:)` throws at any point, the coordinator ends in the idle
   state it had before the call: not running, status idle, overlay and panel
   hidden, no selected window, capture stopped.
2. The user sees the existing Thai error alert (unchanged wording is fine) and
   the error is logged to `GameTranslator.log`.
3. After the failure, ⌃⌥T / the menu start the normal "pick a window" flow again.

## Out of scope
- Changing the window picker, permission flow or `build.sh`.
- Detecting a game window that closes *while* capturing (separate task if needed).
  > Amended 2026-09-23 (Cowork): that is now T-0002; a stop pressed *during* start is T-0003 (depends on this task).

## Constraints
- CLAUDE.md stability rules apply — in particular no new call that can pop the
  Screen Recording dialog.
- `PipelineCoordinator` and `StatusBarController` are `@MainActor`.

## Files / Modules
- `Sources/Services/PipelineCoordinator.swift`
- `Sources/App/StatusBarController.swift` (only if the menu/icon need refreshing)
- `Tests/…` (only if the reset logic can be tested without a real `SCWindow`)

## Acceptance Criteria
- **AC-1** [code] On every throwing path of `start(window:)` after state was
  changed, the state is rolled back (running flag, status, selected window,
  overlay/panel, capture).
- **AC-2** [code] No new `SCShareableContent`, `CGRequestScreenCaptureAccess()` or
  other call that can show the Screen Recording dialog.
- **AC-3** [manual] Steps: 1) open a game, 2) press ⌃⌥T to open the window picker,
  3) quit the game while the picker is open, 4) choose the game's (now closed)
  window. Expected: the error alert appears, no overlay/panel remains, the menu bar
  icon shows "not running", and pressing ⌃⌥T opens the picker again.
- **AC-4** [build] Unit tests and Release build succeed.

## Testing Requirements
- Add a unit test if the rollback can be exercised without a real `SCWindow`
  without a large refactor; otherwise explain in Implementation Notes why not.
- Manual check AC-3 by the owner.

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
| 2026-09-23 | → PLANNED | Claude Code | bootstrap draft from audit; Cowork to review, edit or cancel |
| 2026-09-23 | PLANNED → READY | Cowork | draft reviewed, spec accepted; related T-0002, T-0003 |
