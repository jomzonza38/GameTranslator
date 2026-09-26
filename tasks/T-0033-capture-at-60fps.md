# T-0033 — Capture card runs at 60 fps when the card offers it

| Field | Value |
|---|---|
| **Status** | DONE |
| **Type** | fix |
| **Priority** | P1 (urgent) |
| **Version impact** | patch |
| **Milestone** | M7 — Capture card mode |
| **Depends on** | — (stacks on T-0032; owner commits T-0032 first) |
| **Corrects** | T-0030 |
| **Follow-up** | — |
| **Created** | 2026-09-26 by Cowork |

## Objective
The Switch picture on the Mac is not smooth. The owner's Kingma offers 1080p at 60 fps, but the app runs
it at **30 fps**. It must run at 60 fps (or the closest the card really offers).

## Context
Owner's log, 2026-09-26 (every start the same):
```
TV Output: USB3. 0 capture offers 22 formats: … 1280x720@60/420v, … 1920x1080@60/420v, 1920x1080@5/yuvs
TV Output: capture running — USB3. 0 capture, active after start: 1920×1080 @ 30 fps · NV12 (ไม่บีบอัด)
```
- The right format was chosen (1080p, NV12 uncompressed, max 60) but the frame rate became 30, and **no**
  `⚠️ active format differs` line — so the app itself *chose* 30 (intended = active).
- Likely cause (Cowork, to confirm): UVC devices give frame intervals in 100 ns units. "60 fps" is then
  166666 × 100 ns → a discrete range with `minFrameDuration = maxFrameDuration = 166666/10000000 s`
  (`maxFrameRate ≈ 60.0002`). `CaptureCardSelection.frameDuration(for:)`:
  1. exact `1/60 s` is **not** inside that range (0.0166667 > 0.0166666) → skipped;
  2. "fastest range **below** 60" excludes 60.0002 → picks the 30 fps range.
  The T-0030 tests only use exact `CMTime(1, 60)` ranges, so they miss this.
- Other possible cause to rule out: `lockForConfiguration` failing (log line `cannot set format`).
- The format list also logs `@60` for these ranges because it prints `Int(maxFrameRate)`.

## Requirements
1. When a range's rate is within a small tolerance of 60 (e.g. 59.9…60.1 fps, covering 60.0002 and 59.94),
   that range is used, at **its own** duration (never a rebuilt one — T-0030 F-1 still holds).
2. Otherwise the fastest range at or below ~60 fps; only-faster formats as in T-0030.
3. The log shows, for the chosen format, each frame-rate range with its exact durations (value/timescale)
   and the one picked, so a future mismatch can be read from the log.
4. The menu/log keep reporting the rate actually active after start (T-0030).

## Out of scope
- Format choice rules (`bestFormatIndex`), display timing, T-0028/T-0029 work.

## Constraints
- CLAUDE.md stability rules apply. Never set a duration outside the active format's ranges.

## Files / Modules
- `Sources/Services/CaptureCardService.swift`, `Tests/TVOutputTests.swift`

## Acceptance Criteria
- **AC-1** [test] Discrete ranges with UVC durations: 166666/10000000 (≈60.0002) → that range, not 30;
  166833/10000000 (≈59.94) → that range; also 1001/60000, exact 1/60, 333333/10000000 (30) only, 50 fps
  only, continuous 5…60.0002. Every result passes `isSupported`.
- **AC-2** [code] Only a range's own duration or exact `1/60` inside a range is ever set (T-0030 AC-2 still holds).
- **AC-3** [build] Unit tests and Release build succeed.
- **AC-4** [manual] Owner: ⌃⌥V → menu and log show `1920×1080 @ 60 fps · NV12`; the log lists the ranges;
  the picture looks as smooth as OBS's preview of the same card.

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
- **Cause confirmed in code:** `frameDuration(for:)` (T-0030) only accepted an exact `1/60 s` or a range
  *below* 60. A UVC "60 fps" range is `166666/10000000 s` (≈ 60.0002): 1/60 is not inside it and it is
  not below 60 → the 30 fps range was picked. That matches the owner's log (intended = active = 30, no
  "differs" warning). Not the `lockForConfiguration` path (that would have logged `cannot set format`).
- **Fix:** step 2 is now "fastest range with max rate **≤ 60.1**" (`maxNearTargetFrameRate`), at that
  range's **own** `minFrameDuration`. So 60.0002 and 59.94 count as 60; with both, 60.0002 wins. Step 1
  (exact integer `1/60` if a range contains it) and step 3 (only faster formats → slowest range) are
  unchanged; `isSupported` against the active format's ranges still runs before anything is set (AC-2).
  The menu rounds 60.0002 to "60 fps".
- **Log (Req 3):** new line after the format is chosen, e.g.
  `TV Output: chosen format 1920x1080/420v ranges: 60.0002 fps (166666/10000000 … 166666/10000000 s),
  30 fps (…) → picked 166666/10000000 s` (`CaptureCardSelection.describeRanges`). The "active after
  start" line from T-0030 stays.

## Result

**Outcome:** PARTIAL — `[test]`/`[code]`/`[build]` criteria pass; AC-4 pending owner
**Version:** 1.17.0 → 1.17.1
**Commit:** `52b0c56`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `TVOutputTests`: `testUVCSixtyIsPickedNotThirty` (166666/10000000 + 30 → 60.0002; also asserts 1/60 is outside that range), `testUVCSixtyInAnyOrder`, `testUVC5994` (166833/10000000), `testUVCSixtyBeatsNTSC5994` (vs 1001/60000), `testDiscreteSixty` (exact 1/60), `testUVCThirtyOnly` (333333/10000000), `testFiftyOnly`, `testContinuousUpToUVCSixty` (5…60.0002 → 1/60 inside). Each checked with `isSupported`. Also `testMenuShowsSixtyForUVCSixty`, `testRangesLogLineHasExactDurations`. |
| AC-2 | ✅ pass | `frameDuration(for:)` returns only `targetFrameDuration` (integer 1/60, when inside a range) or a range's own `minFrameDuration`/`maxFrameDuration`; the device gets it only after `isSupported` on `device.activeFormat`'s ranges (unchanged). |
| AC-3 | ✅ pass | See below. |
| AC-4 | ⏳ pending owner | Steps below. |

### Build & test
```
Executed 244 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                      | 1.17.1
 Sources/Services/CaptureCardService.swift | ≤ 60.1 fps counts as 60; describeRanges + log line
 Tests/TVOutputTests.swift                 | 9 new tests (UVC durations)
```

### Manual checks for the owner
**AC-4** — `./build.sh`, then ⌃⌥V with the Switch on. Open the menu → `1920×1080 @ 60 fps · NV12 (ไม่บีบอัด)`.
In `~/Desktop/GameTranslator.log`: a line `chosen format 1920x1080/420v ranges: … → picked 166666/10000000 s`
(or another ~60 fps duration) and `active after start: 1920×1080 @ 60 fps`. The picture should look as
smooth as OBS's preview of the same card. If it still says 30, send the log lines starting with `TV Output:`.

### Proposed follow-ups
- none

---

## Review
**Cowork, 2026-09-26 — code passes; waiting for owner AC-4.** Evidence: `build.noindex/Logs/Test` 12:55.
Fix is minimal: exact 1/60 if inside a range, else the fastest range ≤ 60.1 fps at its own duration →
the card's 166666/10000000 range is picked; tests use real UVC durations; ranges logged. No findings.
DONE once the menu shows `@ 60 fps` and the picture is smooth.
**2026-09-26 — owner's log: `active after start: 1920×1080 @ 60 fps · NV12`. DONE.**

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-26 | → READY | Cowork | owner: picture not smooth; log shows 1080p60 format running at 30 fps |
| 2026-09-26 | READY → IN_PROGRESS | Claude Code | started |
| 2026-09-26 | IN_PROGRESS → REVIEW | Claude Code | test/code/build ACs pass; AC-4 manual pending owner |
| 2026-09-26 | — | Cowork | code review passed; waiting for owner AC-4 |
| 2026-09-26 | REVIEW → DONE | Cowork | owner log shows 60 fps |
