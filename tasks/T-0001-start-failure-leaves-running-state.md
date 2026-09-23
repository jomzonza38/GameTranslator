# T-0001 — A failed start must not leave the app stuck in "running"

| Field | Value |
|---|---|
| **Status** | DONE |
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

- **Approach:** the body of `stop()` was moved into a private `tearDown()` (not
  running, cancel pipeline task, drop pending frame, stop capture, hide overlay and
  panel, status idle, clear regions and selected window). `stop()` now calls it
  after its `isRunning` guard. In `start(window:)` the `startCapture` call is
  wrapped in `do/catch`; on failure it logs `✗ Capture failed to start: …`, calls
  `tearDown()`, sets `lastError` and rethrows, so `StatusBarController` still shows
  the existing alert "เริ่มจับภาพไม่ได้". Sharing one teardown keeps stop and the
  failure path from drifting apart.
- **Throwing paths:** `start` has three. `missingApiKey` and `invalidWindow` throw
  before any state is changed (nothing to undo). `startCapture` is the only one
  after state changes → now rolled back.
- **`lastError`** is set to the failure message after the rollback (before the call
  it was whatever the previous session left). It is not listed in Requirement 1;
  keeping the message lets the menu show it (T-0006). Cowork may ask to drop it.
- **Not rolled back on purpose:** `settings.selectGame(...)` (current game profile)
  and the recreated translation provider. Both are harmless and are set again on
  the next start; neither is in Requirement 1.
- **StatusBarController unchanged:** the menu and icon are only switched to
  "running" after `start` succeeds, and the window picker is guarded by
  `pipeline.isRunning` (line ~449), which is now false after a failure — so ⌃⌥T
  opens the picker again without any change there.
- **ScreenCaptureService unchanged:** when its `startCapture` throws it has not set
  `isCapturing`/`stream`, so `stopCapture()` inside `tearDown()` is a no-op and no
  stream is left running. Its stale `selectedWindow`/`streamOutput` fields are
  overwritten on the next start.
- **No unit test:** `start(window:)` requires a real `SCWindow` (cannot be created
  in tests without Screen Recording permission and a live window), and
  `PipelineCoordinator` builds real capture/overlay objects in `init`. Testing the
  rollback would need injecting the capture service — a larger refactor than this
  fix. Covered by the `[code]` review and the `[manual]` check instead.

## Result

**Outcome:** PARTIAL — all `[code]`/`[build]` criteria pass; AC-3 pending owner
**Version:** 1.11.11 → 1.11.12
**Commit:** not committed (waiting for owner)

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `PipelineCoordinator.start(window:)`: the only throw after state changes (`startCapture`) is caught → `tearDown()` resets `isRunning`, pipeline task, pending frame, capture, overlay, panel, `status = .idle`, `currentRegions`, `selectedWindow`; error rethrown. Earlier throws happen before any state change. |
| AC-2 | ✅ pass | `git diff` adds no `SCShareableContent`, `CGRequestScreenCaptureAccess` or `CGPreflightScreenCaptureAccess` call (grep of added lines: none). |
| AC-3 | ⏳ pending owner | Steps below. |
| AC-4 | ✅ pass | Verify commands: `Executed 52 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 52 tests, with 0 failures (0 unexpected) in 0.070 (0.094) seconds
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                               |  2 +-
 Sources/Services/PipelineCoordinator.swift         | 23 +++++++++++++++++-----
 tasks/BOARD.md                                     |  (status)
 tasks/T-0001-start-failure-leaves-running-state.md |  (this report)
```

### Manual checks for the owner
AC-3 — install with `./build.sh`, then:
1. Open a game (any windowed app works too).
2. Press ⌃⌥T — the window picker opens.
3. Quit the game while the picker is still open.
4. Click the game's (now closed) window in the picker.

Expected: alert "เริ่มจับภาพไม่ได้" appears; no overlay or panel stays on screen;
the menu bar icon is the "not running" icon; `~/Desktop/GameTranslator.log` has a
line `✗ Capture failed to start: …`; pressing ⌃⌥T again opens the picker.
(If step 4 unexpectedly *succeeds* in starting capture, note it — then the failure
path can't be reached this way and AC-3 needs another trigger.)

### Proposed follow-ups
- The menu is not rebuilt after a failed start, so the `⚠️` error line only shows
  on the next rebuild — belongs to T-0006.
- `ScreenCaptureService.startCapture` keeps stale `selectedWindow`/`streamOutput`
  after a failure (harmless today; could be cleaned when T-0002/T-0003 touch it).

---

## Review

**Cowork, 2026-09-23 — code review passed; waiting for owner's AC-3 before DONE.**

| AC | Verdict | Note |
|---|---|---|
| AC-1 | ✅ accepted | Checked the diff: the only throw after state changes (`startCapture`) is caught, `tearDown()` resets every item in Requirement 1, error is rethrown so the existing alert shows. `missingApiKey`/`invalidWindow` throw before any state change. |
| AC-2 | ✅ accepted | No new permission-dialog calls in the diff. |
| AC-3 | ⏳ pending owner | Steps in *Manual checks for the owner*. |
| AC-4 | ✅ accepted | 52 tests, TEST + BUILD SUCCEEDED reported. |

- Scope: changed files match *Files / Modules*; version bumped once (1.11.11 → 1.11.12, patch). ✅
- `lastError` kept after a failed start — accepted (useful for T-0006).
- No unit test — reason accepted (needs a real `SCWindow`; injection is a larger refactor). Test coverage of `PipelineCoordinator` stays in the backlog.
- Note for T-0003 (not a defect of this task): `tearDown()` has no session check. If the user stops *and starts a new session* while an old `startCapture` is still awaiting, the old start's failure would tear down the new session. T-0003 must cover this ordering.
- Follow-ups accepted: menu refresh → already T-0006; stale `selectedWindow`/`streamOutput` in `ScreenCaptureService` → add to T-0002/T-0003 context.

- 2026-09-23 23:07 owner: build OK. Log of v1.11.12 shows a normal start ("✓ Capture started successfully", translations via Claude Haiku) — no regression. The failure path (`✗ Capture failed to start`) is not in the current log (log is cleared at each launch), so AC-3 is not yet evidenced; asked the owner to confirm.
- 2026-09-23 23:17 / 23:19 owner ran AC-3 twice (TextEdit window "เปิด" picked after
  quitting TextEdit). Both times capture **started successfully** — the failure path
  was not reached, so AC-3 cannot be triggered this way. The closed-window behaviour
  moves to T-0002 (spec amended).

Decision: stays **REVIEW** until the owner confirms AC-3, then Cowork sets DONE and T-0003 → READY.

**Final decision 2026-09-23: DONE.** AC-3 waived by the owner — the failure path
cannot be triggered manually (macOS starts capture on a closed window). Accepted on
code review + build/tests; normal start verified in the owner's log (no regression).

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-23 | → PLANNED | Claude Code | bootstrap draft from audit; Cowork to review, edit or cancel |
| 2026-09-23 | PLANNED → READY | Cowork | draft reviewed, spec accepted; related T-0002, T-0003 |
| 2026-09-23 | READY → IN_PROGRESS | Claude Code | started |
| 2026-09-23 | IN_PROGRESS → REVIEW | Claude Code | code/build ACs pass; AC-3 manual pending owner |
| 2026-09-23 | REVIEW → DONE | Cowork | AC-3 waived by owner (not reproducible); closed-window case moved to T-0002 |
