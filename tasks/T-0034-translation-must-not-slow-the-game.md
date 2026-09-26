# T-0034 — Translating the Switch picture must not slow the game down

| Field | Value |
|---|---|
| **Status** | REVIEW_FAILED |
| **Type** | fix |
| **Priority** | P1 (urgent) |
| **Version impact** | patch |
| **Milestone** | M7 — Capture card mode |
| **Depends on** | — (stacks on T-0028; owner commits T-0028 first) |
| **Corrects** | T-0028 |
| **Follow-up** | T-0035 |
| **Created** | 2026-09-26 by Cowork |

## Objective
With translation on, the Switch picture lags (owner, 2026-09-26); without it (T-0032) it didn't. Translation
must cost so little that the MacBook Air (fanless) doesn't heat up and throttle.

## Context
Owner's measurements (MacBook Air M2, capture card window, translation on, Kingma on USB 2.0):
```
Capture card frames: 60 received, 60 with changed pixels, 60 sent to OCR in 10 s   (also with regions)
OCR [full-screen]: 7↔8 texts in ~105 ms, 5–6 runs/s     OCR [Region 1]: ~75 ms
top: GameTranslator 46–56 %, WindowServer 43 %, kernel_task 22–28 %, coreaudiod 12 %, UVCAssistant 8 %
```
- **Every** frame counts as changed (exact `FrameFingerprint`: capture noise / animation) → OCR never rests,
  even with regions; 7↔8 texts alternating = same screen read again and again.
- **WindowServer ~43 %**: ScreenCaptureKit copies our own video window at 2× (`CaptureGeometry.captureScale`),
  up to ~2940×1912 px in full screen, while the source is only 1920×1080.
- **kernel_task 22→28 %** = thermal throttling: the whole Mac slows, the picture with it.
- Hints (Claude Code decides, measure before/after):
  1. In capture card mode, capture at the picture's own resolution (≤ 1920×1080, 1×), not 2× the window.
  2. Noise-tolerant change check, per region when regions are set (e.g. coarse luma grid, change = a cell
     differs by more than a small threshold); unchanged → no OCR. Back off (e.g. to ~1 FPS) while OCR
     results stay the same.
  3. If 1–2 aren't enough: feed OCR from the capture card directly (throttled `AVCaptureVideoDataOutput`,
     late frames dropped) instead of ScreenCaptureKit — no WindowServer copy at all. The window's content
     rect is the picture (T-0032 keeps the aspect ratio), so overlay mapping stays simple.

## Requirements
1. On a static game screen with translation on: OCR runs only when the text area changes (log proves it).
2. Translation still appears for new dialogue within ~1–2 s after it stops typing (T-0028 AC-5/6 still pass).
3. CPU with translation on, full screen, static dialogue screen, after 2 min: GameTranslator ≤ 20 %, no rise of
   WindowServer of more than ~10 points over picture-only, kernel_task ~0 (no throttling).
4. Window translation of other games (⌃⌥T) unchanged.

## Out of scope
- USB 2.0 smoothness (hardware, owner buying a USB 3 adapter). Settings tab (T-0029).

## Constraints
- CLAUDE.md stability rules apply. Picture path (preview layer) unchanged.

## Files / Modules
- `Sources/Services/PipelineCoordinator.swift`, `Sources/Services/ScreenCaptureService.swift`,
  `Sources/Services/CaptureCardService.swift` (only if hint 3), `Tests/…`

## Acceptance Criteria
- **AC-1** [test] Change check: identical and noisy frames → no OCR; a new line / one added character in the
  text area → OCR; change outside a region doesn't trigger that region.
- **AC-2** [code] Capture card mode never captures above the picture's resolution; OCR frames dropped before any work when unchanged.
- **AC-3** [build] Unit tests and Release build succeed.
- **AC-4** [manual] Owner, 2 min on a static dialogue screen, full screen, translation on: `top` shows
  GameTranslator ≤ 20 %, kernel_task ~0; `Capture card frames:` shows few `sent to OCR`.
- **AC-5** [manual] New dialogue → Thai within ~1–2 s; the picture feels like with translation off.

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
Hints 1 + 2 done; hint 3 (feeding OCR from `AVCaptureVideoDataOutput`) not needed unless the owner's
measurement says so.

- **1. Capture size (AC-2).** `CaptureGeometry.captureSize(forWindow:limit:)`: in capture card mode the
  stream is at most the picture's resolution (`maxOutputSize` = the card's `videoSize`, e.g. 1920×1080),
  aspect kept; small windows still get 2×. The resize path uses the same limit. Full screen on the
  MacBook Air: 2940×1912 → ~1660×1080 (≈ 3× fewer pixels for WindowServer to copy). Mapping is
  unchanged: ScreenCaptureKit reports the scaled content via `contentRect/contentScale`, already handled
  since T-0020 (`testOwnersFullScreenSceneMapsOntoTheText` covers scaled content).
  Game windows (⌃⌥T) are untouched: no limit, no grid (Req 4).
- **2. Noise-tolerant change check.** New `Sources/Services/CaptureCardChangeDetection.swift` (pure):
  `LumaGrid` — 48×27 average-brightness cells of the window content (every 2nd pixel; ~40×40 px cells at
  1080p); `LumaChangeDetector` — baseline grid per area (whole picture, or each enabled region), change =
  any cell in the area moves > 3 levels; `OCRPacer` — after 3 runs in a row with the same OCR text, at most
  one OCR per second until the text changes.
  - `StreamOutput` (capture card mode only) computes the grid for every frame; a frame whose grid didn't
    move beyond noise is passed on as "unchanged" (no fingerprint, no CGImage conversion — also saves CPU).
  - `PipelineCoordinator.handleCaptureCardFrame`: OCR only if an area changed; with regions, only the
    changed regions are OCR'd and the others reuse their last OCR result (`CapturedFrame.onlyRegions`,
    `lastRegionOCR`) — so a change outside a region never OCRs it. A window move/resize or text still
    waiting to become stable reads everything, as before (typewriter text keeps being followed).
  - Pacer: a change held back is scheduled as a re-run on the last frame, so it is read even if no new
    frame arrives; a finishing run doesn't cancel it (`hasPacedRerun`).
  - Log: `Capture card: same text read again — OCR at most once a second` / `… text changed — OCR at full
    rate`; the `Capture card frames:` line now counts frames whose grid changed as "changed pixels".
- `StatusBarController`: passes `maxCaptureSize: info.videoSize` (only change there).
- New file outside *Files / Modules*: `CaptureCardChangeDetection.swift` (pure logic, kept out of the
  1100-line pipeline file so it can be unit-tested on its own).
- Verify: 261 tests pass. `MeaningServiceTests.testChatterLeaves…` again slow in full runs (146 s, 814 s
  before) — pre-existing, already in the backlog.

## Result

**Outcome:** PARTIAL — `[test]`/`[code]`/`[build]` criteria pass; AC-4, AC-5 pending owner
**Version:** 1.18.0 → 1.18.1
**Commit:** `fe63cd6`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `CaptureCardChangeDetectionTests`: `testIdenticalPictureIsNotAChange`, `testCaptureNoiseIsNotAChange` (±6 per channel), `testNewLineOfTextIsAChange`, `testOneAddedCharacterIsAChangeEvenWithNoise`, `testChangeOutsideARegionDoesNotTriggerIt` (animation outside → nothing; text in the dialogue region → only that region), `testAreaNeverReadCountsAsChanged`, grid/content tests, `testPacerSlowsDownAfterTheSameTextAndSpeedsUpOnNewText`. |
| AC-2 | ✅ pass | `testCaptureCardModeNeverCapturesAboveThePicture` (1470×956 pt → ≤ 1920×1080), `testSmallWindowIsStillCapturedAtTwice`, `testGameWindowsKeepTwice`; `startCapture`/`requestResize` both use `maxOutputSize`. Unchanged grids are dropped in `StreamOutput` before fingerprint/image conversion; unchanged areas never reach `processFrame`. |
| AC-3 | ✅ pass | See below. |
| AC-4 | ⏳ pending owner | Steps below. |
| AC-5 | ⏳ pending owner | Steps below. |

### Build & test
```
Executed 261 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                             | 1.18.1
 Sources/Services/CaptureCardChangeDetection.swift| (new) LumaGrid, LumaChangeDetector, OCRPacer
 Sources/Services/ScreenCaptureService.swift      | captureSize limit, luma grid per frame, delegate carries the grid
 Sources/Services/PipelineCoordinator.swift       | capture card mode: change check per area, region OCR reuse, pacer
 Sources/App/StatusBarController.swift            | passes the picture size
 Tests/CaptureCardChangeDetectionTests.swift      | (new, 14 tests)
```

### Manual checks for the owner
`./build.sh`, OBS closed, ⌃⌥V, full screen (⌃⌘F).

**AC-4** — stay 2 min on a static dialogue screen with translation on. In Terminal:
`top -o cpu -n 8 -l 2` (read the second sample) → GameTranslator ≤ 20 %, kernel_task ~0, and WindowServer
well below the 43 % measured in T-0028 (target: at most ~10 points above the picture alone — ⌃⌥V now
always translates, so compare with the T-0032 build if you still have its numbers). In
`~/Desktop/GameTranslator.log` the `Capture card frames:` lines should show few `sent to OCR`
(0–2 per 10 s on a static screen).

**AC-5** — new dialogue → Thai within ~1–2 s after it stops typing; the picture feels like with
translation off. If a new line is missed or late, send the `Capture card` log lines.

### Proposed follow-ups
- If AC-4 still shows high WindowServer: hint 3 (OCR frames straight from the capture card).

---

## Review
**Cowork, 2026-09-26 — code passes; waiting for owner AC-4/AC-5.** Evidence: `build.noindex/Logs/Test` 15:42 (261 tests).
Capture ≤ picture resolution in capture card mode only; noise-tolerant grid per area drops unchanged frames
before fingerprint/CGImage; changed regions only; pacer caps a repeating screen at 1 OCR/s with a scheduled
re-run so nothing is missed; game windows (⌃⌥T) untouched. No blocking findings.
Note: on a full-screen area with constant animation the grid still changes every frame — the pacer is what
limits it there; if AC-4 CPU is still high without regions, hint 3 or "regions recommended" is the next step.

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-26 | → READY | Cowork | owner: game lags with translation on; OCR every frame + 2× capture → throttling |
| 2026-09-26 | READY → IN_PROGRESS | Claude Code | started |
| 2026-09-26 | IN_PROGRESS → REVIEW | Claude Code | test/code/build ACs pass; AC-4, AC-5 manual pending owner |
| 2026-09-26 | — | Cowork | code review passed; waiting for owner AC-4/AC-5 |
| 2026-09-26 | REVIEW → REVIEW_FAILED | Cowork | AC-4: GameTranslator 43 %, WindowServer 42 %, kernel_task 22 % — unchanged; pacer reset by 7↔8 flicker → T-0035 |
