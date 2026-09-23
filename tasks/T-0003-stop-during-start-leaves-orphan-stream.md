# T-0003 — Stopping while a session is starting must not leave capture running

| Field | Value |
|---|---|
| **Status** | REVIEW |
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
- > Amended 2026-09-23 (Cowork, from T-0001 review): after T-0001, `start` calls a
  shared `tearDown()` when `startCapture` fails. Requirement 3 includes this ordering:
  stop → new start → the *old* start then fails; the old failure must not tear down
  the new session. `ScreenCaptureService` also keeps stale `selectedWindow`/`streamOutput`
  after a failed start.
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

- **Core idea — a start generation** (`StartGeneration`, pure struct in
  `ScreenCaptureService.swift`): every start takes a token (`begin()`), every stop
  moves the counter on (`invalidate()`). A start that resumes after an `await` checks
  `isCurrent(token)`; if a stop or another start happened meanwhile it must not keep
  its result. Used at both levels:
  - **`ScreenCaptureService`**:
    - `startCapture` first calls `stopCapture()` (replaces anything running,
      including a stream left by an interrupted start), then takes a token.
    - After `await stream.startCapture()` it commits `stream`/`selectedWindow`/
      session/watchdog **only if the token is still current**, in one locked step.
      Otherwise it stops that stream at once and throws `CancellationError` → no
      orphan stream (Req 1, AC-1).
    - The old `guard !isCapturing else { return }` — which silently kept capturing
      the *old* window — is gone, and so is `isCapturing` (a stored `stream` now
      means "capturing") → a new start always captures the new window (Req 2).
    - `stopCapture()` no longer returns early when "not capturing": it always
      invalidates starts in flight, then stops whatever stream is stored.
    - All shared state (`stream`, `streamOutput`, `selectedWindow`, generation,
      session, watchdog) is now under the existing `sessionLock`. Start and stop
      are nonisolated `async` methods, so they really can run at the same time.
    - Frames from a stream whose start is no longer current are dropped. The output
      closure uses the `window` it was created for instead of reading `selectedWindow`.
    - The watchdog timer is created and resumed before the commit check; if the
      start turns out outdated it is cancelled right there. So a stop just after the
      commit always finds it and a suspended timer is never released (which would crash).
    - A failed start now leaves no stale `selectedWindow`/`streamOutput` (T-0001
      follow-up) — they are only stored on a successful, current start.
  - **`PipelineCoordinator`**: `start` takes a token after its early checks;
    `tearDown()` (user stop, failed start, unexpected stop) invalidates. After the
    `startCapture` await:
    - error and token outdated → it was stopped/restarted during start: log
      `Start was stopped before capture began`, **return without throwing and
      without tearing down** — covers the T-0001 review case "stop → new start → old
      start fails" (Req 3).
    - success but token outdated → return before `status = .running` (AC-2).
- **StatusBarController (outside *Files / Modules*, 1 line):** after
  `pipeline.start` it set the icon to "running" unconditionally. Since a start that
  was stopped midway now returns normally, the icon would stay filled after the
  user's stop. It now uses `updateStatusIcon(running: pipeline.isRunning)`.
- **Deadlock check (Req 3):** the lock is never held across an `await` or a
  delegate call, and no code path takes it twice.
- **Tests:** `StartGenerationTests` (4 tests) cover the orderings: stop during
  start, stop → new start → old start finishes, two starts. The `SCStream` side
  can't run in unit tests (needs a real window and Screen Recording permission) →
  covered by code review and AC-4.

## Result

**Outcome:** PARTIAL — all `[code]`/`[build]` criteria pass; AC-4 pending owner
**Version:** 1.11.13 → 1.11.14
**Commit:** not committed (waiting for owner)

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `ScreenCaptureService.startCapture`: commit only if `starts.isCurrent(generation)`, else `stream.stopCapture()` + `CancellationError`; `stopCapture()` always `invalidate()`s. `guard !isCapturing` removed; `startCapture` begins with `stopCapture()`, so a stale stream is replaced, not kept. |
| AC-2 | ✅ pass | `PipelineCoordinator.start`: `guard sessions.isCurrent(session)` in the `catch` and before `status = .running`; `tearDown()` invalidates and sets `isRunning = false`. |
| AC-3 | ✅ pass | No `SCShareableContent`, `CGRequestScreenCaptureAccess` or `CGPreflightScreenCaptureAccess` in added lines. |
| AC-4 | ⏳ pending owner | Steps below. |
| AC-5 | ✅ pass | `Executed 60 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 60 tests, with 0 failures (0 unexpected) in 0.077 (0.108) seconds
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                         |   2 +-
 Sources/App/StatusBarController.swift        |   3 +-   (reason above)
 Sources/Services/PipelineCoordinator.swift   |  14 +++
 Sources/Services/ScreenCaptureService.swift  | 122 ++++++++++++++-------
 Tests/StartGenerationTests.swift             | (new, 4 tests)
 tasks/BOARD.md, tasks/T-0003-…md             | (status + this report)
```
(`tasks/T-0002-…md` and one BOARD line also show in `git diff`: the T-0002
commit hash recorded after the owner's commit — not part of this task.)

### Manual checks for the owner
Install with `./build.sh` first.

**AC-4**
1. Open a game. Press ⌃⌥T, pick the game window, and **immediately** press ⌃⌥T
   again. Repeat 5 times.
   Expected: no crash or freeze; after the last stop the purple screen-recording
   indicator in the menu bar disappears within a few seconds; the icon is the outline
   one and the menu shows "🎮 เลือก Window...". No "เริ่มจับภาพไม่ได้" alert for these
   stops. The log may show `Start was stopped before capture began` or
   `Capture start was stopped before it finished — discarding its stream`.
2. Press ⌃⌥T and pick a **different** window (e.g. another app).
   Expected: that window is translated (overlay over it, log `Starting capture of
   window: <its title>` then `✓ Capture started successfully`).

### Proposed follow-ups
- none

---

## Review

**Cowork, 2026-09-23 — code review passed; waiting for owner's AC-4 before DONE.**

| AC | Verdict | Note |
|---|---|---|
| AC-1 | ✅ accepted | Stream committed only if its start generation is still current, else stopped + `CancellationError`; `guard !isCapturing` removed; `startCapture` replaces any stale stream. |
| AC-2 | ✅ accepted | Coordinator checks its own generation in `catch` and before `.running`; covers the T-0001 review case (stop → new start → old start fails) without tearing down the new session. |
| AC-3 | ✅ accepted | No permission-dialog calls added. |
| AC-4 | ⏳ pending owner | Needs v1.11.14 installed. |
| AC-5 | ✅ accepted | 60 tests, TEST + BUILD SUCCEEDED reported. |

- `StatusBarController` one-line change outside *Files / Modules* — justified (icon would stay filled after a stop during start). ✅
- Lock never held across `await` or delegate calls — checked. ✅
- Minor, no action: if the service ever cancels a start the coordinator still considers current, the user would see "เริ่มจับภาพไม่ได้" with a cancellation text. Not reachable today (`start` is guarded by `isRunning`).
- Version 1.11.13 → 1.11.14 ✅. Not committed yet.

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-23 | → PLANNED | Cowork | created from code audit; READY once T-0001 is DONE |
| 2026-09-23 | PLANNED → READY | Cowork | T-0001 DONE |
| 2026-09-23 | READY → IN_PROGRESS | Claude Code | started |
| 2026-09-23 | IN_PROGRESS → REVIEW | Claude Code | code/build ACs pass; AC-4 manual pending owner |
