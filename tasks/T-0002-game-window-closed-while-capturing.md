# T-0002 — Closing the game while translating must stop cleanly and tell the user

| Field | Value |
|---|---|
| **Status** | REVIEW |
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
- > Amended 2026-09-23 (Cowork, from T-0001 manual test): picking a window whose app
  had just been quit **started capture successfully** twice (log: `Starting capture of
  window: เปิด` → `✓ Capture started successfully` → one `OCR … 0 texts` → nothing
  more). So a closed window does not reliably make `startCapture` throw, and it is
  not proven that `didStopWithError` fires either. Requirement 1 therefore also
  covers "capture started on a window that no longer exists" and "stream silently
  delivers no frames because the window is gone". Hint: check whether the window
  still exists (e.g. via its window ID) rather than relying only on the delegate.
  AC-4 should be checked both ways: quit the game while translating, and pick a
  window whose app was already quit.

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

- **Two detectors, one report** (`ScreenCaptureService`):
  1. The `SCStream` now gets the service as its `SCStreamDelegate`;
     `stream(_:didStopWithError:)` logs the error and reports.
  2. A **window watchdog** (`DispatchSourceTimer` on the capture queue, every 1 s)
     checks with `CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID)`
     whether the captured window still exists. Two misses in a row
     (`WindowGoneDetector`, threshold 2) → report `.windowClosed`. This covers the
     amended cases: capture that *started* on an already-closed window, and a stream
     that silently delivers nothing. `.optionIncludingWindow` also returns
     minimised/off-screen windows, so a minimised game is not mistaken for closed
     (that case stays out of scope as specified). A `nil` result from the API counts
     as "exists" so an API glitch never stops a working session.
  - For `didStopWithError`, the reason is `.windowClosed` if the window is gone,
    otherwise `.streamFailed(error)` (different Thai message).
- **At most once, never for our own stop (Req 5 / AC-2):** the service keeps an
  `ActiveSession` (stream identity + window ID) under an `NSLock`.
  `stopCapture()` clears it and cancels the watchdog *before* stopping the stream,
  and a report only goes out if its session is still the active one — checked and
  cleared in one locked step, so the watchdog and the delegate can't both report.
  Callbacks from an old stream are ignored the same way.
- **Coordinator:** the unused `didEncounterError` delegate method was replaced by
  `didStopUnexpectedly(_:)`. `handleUnexpectedStop` (MainActor) does nothing if not
  running, logs `✗ Game window closed — stopping translation` (or the stream error),
  runs the same `tearDown()` as a user stop (from T-0001), sets `lastError` to the
  Thai message and calls the new `onStoppedUnexpectedly` callback.
- **How the user is told (Req 2):** the message goes into the menu's existing ⚠️
  line — "หยุดแปลแล้ว เพราะหน้าต่างเกมถูกปิด" — and the status icon switches to
  not-running. No `NSAlert` (modal, steals focus from a restarting game) and no
  `UserNotifications` (would add a new macOS permission prompt). The message is
  cleared by the next start (`start()` resets `lastError`).
- **StatusBarController:** sets `onStoppedUnexpectedly` to clear the window title,
  rebuild the menu and reset the icon — the same three steps as `stopTranslation()`.
- **Detection delay:** 1–2 s after the window disappears (first check after 1 s,
  second miss confirms).
- **Tests:** `WindowGoneDetectorTests` (4 tests) cover the gone/not-gone decision.
  The stream and watchdog wiring needs a real `SCStream`/window, so it is covered by
  code review and AC-4/AC-5.
- **Not done here (T-0003):** T-0001's review note — a late failure of an old
  `start` tearing down a new session — and the stale `selectedWindow`/`streamOutput`
  after a failed `startCapture` are left for T-0003, which owns the start/stop ordering.

## Result

**Outcome:** PARTIAL — all `[code]`/`[build]` criteria pass; AC-4 and AC-5 pending owner
**Version:** 1.11.12 → 1.11.13
**Commit:** `275e90d` (owner asked to commit while the task was in REVIEW)

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `SCStream(..., delegate: self)` + `SCStreamDelegate.stream(_:didStopWithError:)` and the window watchdog both call `reportUnexpectedStop` → delegate `didStopUnexpectedly` → `PipelineCoordinator.handleUnexpectedStop` → `tearDown()` (same as `stop()`). |
| AC-2 | ✅ pass | `stopCapture()` calls `endSession()` before `stream.stopCapture()`; reports require the session to still be active; `handleUnexpectedStop` also returns early when `!isRunning` (user stop sets it false first). |
| AC-3 | ✅ pass | Added lines contain no `SCShareableContent`, `CGRequestScreenCaptureAccess`, `CGPreflightScreenCaptureAccess`, `runModal` or `activate(`. Only `CGWindowListCopyWindowInfo`, which the app already uses and which shows no dialog. |
| AC-4 | ⏳ pending owner | Steps below. |
| AC-5 | ⏳ pending owner | Steps below. |
| AC-6 | ✅ pass | `Executed 56 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 56 tests, with 0 failures (0 unexpected) in 0.075 (0.100) seconds
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                               |   2 +-
 Sources/App/StatusBarController.swift              |   7 ++
 Sources/Services/PipelineCoordinator.swift         |  29 +++++-
 Sources/Services/ScreenCaptureService.swift        | 112 ++++++++++++++++++++-
 Tests/WindowGoneDetectorTests.swift                |  (new, 4 tests)
 tasks/BOARD.md, tasks/T-0002-…md                   |  (status + this report)
```

### Manual checks for the owner
Install with `./build.sh` first.

**AC-4 (Overlay, game quits while translating)**
1. Settings → display mode Overlay. Open a game (TextEdit works for a quick check).
2. ⌃⌥T → pick the game window; wait until translations show.
3. Quit the game.
Expected within ~2 s: overlay disappears; menu shows "🎮 เลือก Window..." and the
line "⚠️ หยุดแปลแล้ว เพราะหน้าต่างเกมถูกปิด"; status icon is the outline (not
filled) one; no crash or freeze. Log has `Captured window … no longer exists` (or
`Capture stream stopped: …`) followed by `✗ Game window closed — stopping translation`.

**AC-4b (window already closed when picked — from the T-0001 amendment)**
1. ⌃⌥T to open the picker, quit the game while the picker is open, click its window.
Expected: capture may start, but within ~2 s the same stop + message as above.

**AC-5 (Panel mode, then restart the game)**
1. Repeat AC-4 with display mode Panel → the panel disappears after the game quits.
2. Start the game again, press ⌃⌥T → picker opens → pick it → translation works and
   the ⚠️ message is gone from the menu.

**Also check (Req 5):** start translating, then press ⌃⌥T (or menu ⏹ หยุดแปล) to stop
normally → no "หน้าต่างเกมถูกปิด" message appears.

### Proposed follow-ups
- A minimised/hidden game keeps the session "running" with no frames (out of scope
  here by spec). If that matters, it needs its own task (e.g. pause the overlay).
- The ⚠️ message only lives in the menu; if the owner wants a visible toast over the
  game, that would be a separate UX task (non-activating panel, no new permission).

---

## Review

**Cowork, 2026-09-23 — code review passed; waiting for owner's AC-4 / AC-5 before DONE.**

| AC | Verdict | Note |
|---|---|---|
| AC-1 | ✅ accepted | Delegate + 1 s watchdog both funnel into one locked `reportUnexpectedStop` → `handleUnexpectedStop` → `tearDown()`. Covers the amended case (capture started on a closed window). |
| AC-2 | ✅ accepted | Session cleared before our own `stopCapture()`; `handleUnexpectedStop` also guards `isRunning`. |
| AC-3 | ✅ accepted | Only `CGWindowListCopyWindowInfo` added — no permission dialog. No alert / no UserNotifications — good call. |
| AC-4 | ⏳ pending owner | Installed app is still v1.11.12 (log 23:15) — not tested yet. |
| AC-5 | ⏳ pending owner | same |
| AC-6 | ✅ accepted | 56 tests, TEST + BUILD SUCCEEDED reported. |

- Scope/version OK (1.11.12 → 1.11.13). Committed as `275e90d` during REVIEW at the owner's request — fine; a fix, if needed, goes in a corrective task.
- **Extra manual check requested (risk, not a defect yet):** the watchdog tracks one window ID. Some games destroy and recreate their window when switching fullscreen ↔ windowed; that would now stop translation with "หน้าต่างเกมถูกปิด". Owner: toggle fullscreen in a game while translating and note the result. If it stops, Cowork will open a follow-up task (e.g. re-attach to the same app's new window) — it does not fail this task.
- Follow-ups noted: minimised game (out of scope), on-screen toast (UX, later). Not turned into tasks yet.

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-23 | → READY | Cowork | created from code audit v1.11.11 |
| 2026-09-23 | READY → IN_PROGRESS | Claude Code | started |
| 2026-09-23 | IN_PROGRESS → REVIEW | Claude Code | code/build ACs pass; AC-4, AC-5 manual pending owner |
