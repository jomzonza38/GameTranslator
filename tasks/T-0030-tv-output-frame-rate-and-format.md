# T-0030 — TV Output: set the capture frame rate safely and keep the chosen format

| Field | Value |
|---|---|
| **Status** | REVIEW |
| **Type** | fix |
| **Priority** | P1 (urgent) |
| **Version impact** | patch |
| **Milestone** | M7 — TV Output |
| **Depends on** | — (stacks on T-0027's code; owner commits T-0027 first) |
| **Corrects** | T-0027 |
| **Follow-up** | — |
| **Created** | 2026-09-26 by Cowork |

## Objective
Starting TV Output must never crash, whatever frame rates the capture card reports, and the picture must
really run in the format the app chose — so the owner's latency test (T-0027 AC-8) measures the right thing.

## Context
From the T-0027 review (see its *Review*, F-1/F-2):
- **F-1:** `CaptureCardService.startVideoOnQueue` sets `activeVideoMin/MaxFrameDuration` to
  `CMTime(value: 1000, timescale: fps × 1000)`. With discrete rates (UVC: range min = max) at 59.94 or
  29.97, that value is not exactly a supported one → `NSInvalidArgumentException` → app quits.
- **F-2:** the device is unlocked before `session.startRunning()`; on macOS the session can re-apply its
  preset at start and replace the chosen `activeFormat`/frame rate, while the menu shows the chosen one.
- Hint: use the chosen `AVFrameRateRange`'s own `minFrameDuration` (or a duration inside
  `[minFrameDuration, maxFrameDuration]` of that exact range object) instead of rebuilding it from a
  Double; keep the configuration lock across `startRunning()` (Apple's documented pattern on macOS), and
  read back `device.activeFormat` / `activeVideoMinFrameDuration` after start for the menu and log.

## Requirements
1. The frame duration set on the device is always one the chosen format supports, including discrete
   59.94 / 29.97 / 60 / 30 ranges. No code path can set an unsupported value.
2. The chosen format and frame rate are still active after the session starts.
3. The menu and log show the format and frame rate **actually active** after start (read back), not the
   intended ones. If they differ from the choice, the log says so.
4. Nothing else in T-0027's behaviour changes.

## Out of scope
- Anything in T-0028/T-0029; the choice rules of `bestFormatIndex`.

## Constraints
- CLAUDE.md stability rules apply. Thai UI strings.

## Files / Modules
- `Sources/Services/CaptureCardService.swift`, `Tests/TVOutputTests.swift`

## Acceptance Criteria
- **AC-1** [test] Frame-rate choice returns a supported duration for discrete ranges at 60, 59.94
  (60000/1001), 30 and 29.97, and for continuous ranges (target 60 inside / only below / only above).
- **AC-2** [code] No `CMTime` built from a Double fps is assigned to `activeVideoMin/MaxFrameDuration`.
- **AC-3** [code] The device stays locked for configuration until after `startRunning()`; the reported
  format/rate come from the device after start.
- **AC-4** [build] Unit tests and Release build succeed.
- **AC-5** [manual] T-0027 AC-5, AC-6, AC-7, AC-8 (steps in T-0027 *Manual checks*) on this build. The
  menu's format line = the log's "active after start" line. Record both latency medians here.

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
- **Stacked on uncommitted T-0027** (owner: "เริ่มทำทั้งหมด"). T-0027's files are untracked, so the
  working tree holds both tasks. For one commit per task, T-0027 would be committed with its own code
  (1.16.0) and this task on top (1.16.1). Or both go in together if the owner prefers.
- **F-1.** Frame-rate ranges now carry the device's own `minFrameDuration`/`maxFrameDuration`
  (`CaptureFrameRateRange`). `CaptureCardSelection.frameDuration(for:)` returns only:
  exactly `CMTime(1, 60)` (integers) when a range contains it (exact `CMTimeCompare`), else a range's own
  duration: the fastest range below 60 (59.94 → 1001/60000, 29.97 → 1001/30000), else the slowest
  range above 60. Right before setting it, `isSupported(_:by:)` checks it again against the ranges
  of `device.activeFormat`; if that fails, nothing is set and the device keeps its default. The old
  `frameRate(for:) -> Double` and the `CMTime(1000, fps×1000)` build are gone.
- **F-2.** `lockForConfiguration()` → `activeFormat` + durations → `startRunning()` → `unlockForConfiguration()`.
  After start, the menu/log text and the picture size (letterbox) come from `device.activeFormat` and
  `device.activeVideoMinFrameDuration`. Log: `active after start: …`, plus
  `⚠️ active format differs from the chosen one (…)` when it isn't what was chosen.
- The generation check moved to before the configuration (it used to be right before `startRunning()`);
  the check after `startRunning()` is unchanged, so a stop during start still cancels.
- F-3 (log note in `TVOutputController`) not done: that file isn't in *Files / Modules* and the review
  called it "acceptable". → follow-up.

## Result

**Outcome:** PARTIAL — `[test]`/`[code]`/`[build]` criteria pass; AC-5 pending owner
**Version:** 1.16.0 → 1.16.1 (T-0027 was 1.15.1 → 1.16.0, not committed yet)
**Commit:** `f3201bf`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `TVOutputTests`: `testDiscreteSixty`, `testDiscrete5994UsesTheRangesOwnDuration` (also asserts 1/60 is *not* supported there — the crash case), `testDiscreteThirty`, `testDiscrete2997`, `testContinuousRangeContainingSixty`, `testContinuousRangeOnlyBelowSixty`, `testContinuousRangeOnlyAboveSixtyUsesTheSlowestRate`, `testFixedHighRateOnly`, `testNoRangesGivesNil`, `testInvalidDurationIsNeverSupported`; each result checked with `isSupported`. |
| AC-2 | ✅ pass | The only `CMTime(` in `CaptureCardService.swift` is `targetFrameDuration = CMTime(value: 1, timescale: 60)`; `activeVideoMin/MaxFrameDuration` get `frameDuration(for:)`'s result only after `isSupported` on the active format's ranges. |
| AC-3 | ✅ pass | `startVideoOnQueue`: `startRunning()` then `if locked { device.unlockForConfiguration() }`; `CaptureCardInfo.formatDescription`/`videoSize` built from `device.activeFormat` + `activeVideoMinFrameDuration` after start. |
| AC-4 | ✅ pass | See below. |
| AC-5 | ⏳ pending owner | Steps below. |

### Build & test
```
Executed 230 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                       | 1.16.0 → 1.16.1
 Sources/Services/CaptureCardService.swift  | CaptureFrameRateRange, frameDuration/isSupported, lock across start, read-back
 Tests/TVOutputTests.swift                  | 10 new frame-duration tests, description test updated (33 tests)
```

### Manual checks for the owner
Run `./build.sh`, then do T-0027 *Manual checks* AC-5, AC-6, AC-7 and AC-8 on this build. Extra for AC-5:
the format line in the menu (e.g. `1920×1080 @ 60 fps · MJPEG` or `@ 59.94 fps`) must equal the log line
`TV Output: capture running — <card>, active after start: …` in `~/Desktop/GameTranslator.log`. If the log
also has `⚠️ active format differs…`, send the log. Record both latency medians (OBS vs GameTranslator)
here.

### Proposed follow-ups
- F-3: say in the log when a start is cancelled because *some* video device (not known to be the card)
  disconnected (`TVOutputController.deviceDisconnected`).

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-26 | → READY | Cowork | corrective task for T-0027 (F-1, F-2) |
| 2026-09-26 | READY → IN_PROGRESS | Claude Code | started, stacked on uncommitted T-0027 (owner: "เริ่มทำทั้งหมด") |
| 2026-09-26 | IN_PROGRESS → REVIEW | Claude Code | test/code/build ACs pass; AC-5 manual pending owner |
