# T-0002 — Closing the game while translating must stop cleanly and tell the user

| Field | Value |
|---|---|
| **Status** | READY |
| **Type** | fix |
| **Priority** | P1 |
| **Version impact** | patch |
| **Milestone** | M1 — Stability |
| **Depends on** | — |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-23 by Cowork (code audit v1.11.11, finding 1) |

## Objective
When the game window disappears while a session is running (game quits, crashes or
restarts) the app must notice, stop capture, clear the overlay/panel and tell the
user in Thai. Today the app keeps showing old translations over nothing and still
thinks it is running. This is stability goal 2.

## Context
- `ScreenCaptureService.startCapture` creates `SCStream(filter:configuration:delegate: nil)`
  (`Sources/Services/ScreenCaptureService.swift`), so the app never hears that the
  stream stopped.
- `ScreenCaptureDelegate.screenCaptureService(_:didEncounterError:)` exists and
  `PipelineCoordinator` implements it (sets `lastError`), but nothing ever calls it.
- After the stream dies: `isRunning` stays `true`, the overlay keeps the last
  boxes, the menu shows "⏹ หยุดแปล", and the status icon stays filled.
- Hint: `SCStreamDelegate.stream(_:didStopWithError:)` is called when the captured
  window closes. Frames simply stopping (window minimised / hidden) is a different
  case and is out of scope.
- Related: T-0001 (failed *start*), T-0003 (stop during start).

## Requirements
1. When the capture stream stops on its own while running, the app ends in the same
   idle state as after the user presses "⏹ หยุดแปล": capture stopped, overlay and
   panel hidden, not running, menu and status icon show "not running".
2. The user is told in Thai that translation stopped because the game window was
   closed (a notification, alert or menu message — Claude Code chooses; it must not
   block the main thread or steal focus from a game that is restarting).
3. The event and the underlying error are written to `GameTranslator.log`.
4. Afterwards ⌃⌥T opens the window picker normally and a new session works.
5. Stopping the stream ourselves (user presses stop / quits) must not show this message.

## Out of scope
- Detecting a minimised/hidden window that stops delivering frames.
- Automatically re-attaching to the game when it starts again.
- Changes to the permission flow or `build.sh`.

## Constraints
- CLAUDE.md stability rules apply — no new call that can show the Screen Recording
  dialog, no force-unwraps, no blocking waits on the main thread.
- UI text in Thai.

## Files / Modules
- `Sources/Services/ScreenCaptureService.swift`
- `Sources/Services/PipelineCoordinator.swift`
- `Sources/App/StatusBarController.swift` (menu/icon refresh)

## Acceptance Criteria
- **AC-1** [code] The capture stream has a delegate and an unexpected stop reaches
  `PipelineCoordinator`, which runs the same teardown as a user stop.
- **AC-2** [code] A stop requested by the app itself does not trigger the
  "game window closed" message.
- **AC-3** [code] No new `SCShareableContent`, `CGRequestScreenCaptureAccess()` or
  other call that can show the Screen Recording dialog.
- **AC-4** [manual] Steps: 1) start translating a game in Overlay mode, 2) quit the
  game. Expected: within a few seconds the overlay disappears, a Thai message says
  translation stopped, the menu shows "🎮 เลือก Window...", the icon is not filled,
  and the app does not crash or freeze.
- **AC-5** [manual] Steps: repeat AC-4 in Panel mode, then start the game again and
  press ⌃⌥T. Expected: panel gone after the game quits; picker opens and a new
  session translates normally.
- **AC-6** [build] Unit tests and Release build succeed.

## Testing Requirements
- Unit test for the teardown decision if it can be separated from `SCStream`
  without a large refactor; otherwise explain why in Implementation Notes.
- Owner runs AC-4 and AC-5.

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
| 2026-09-23 | → READY | Cowork | created from code audit v1.11.11 |
