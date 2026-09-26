# T-0028 — Capture card mode (2/3): Thai translation over the Switch picture

| Field | Value |
|---|---|
| **Status** | REVIEW_FAILED |
| **Type** | feature |
| **Priority** | P2 (normal) |
| **Version impact** | minor |
| **Milestone** | M7 — Capture card mode |
| **Depends on** | T-0033 |
| **Corrects** | — |
| **Follow-up** | T-0034 |
| **Created** | 2026-09-25 by Cowork |

> Amended 2026-09-26: the owner now plays on the **Mac screen** (T-0032): the picture is in a normal
> window on the Mac (or, optionally, on an external display). Wherever it says "TV" below, read "the
> Switch picture window". Requirement 8 and the hint below were added.

## Objective
While TV Output runs, English dialogue in the game is read, translated and shown in Thai on the TV,
next to the original text, over the game picture — without making the picture stutter or lag.

## Context
- Builds on T-0027 (capture card session + TV window).
- The existing pipeline (`PipelineCoordinator`): exact frame fingerprint → `OCRService` → `TextTracker`
  diff + stability gate → `TranslationService.translateBatch` (cached) → `RegionLayout` → overlay/panel.
- Hint (minimal change): a second frame source for the same pipeline — a throttled
  `AVCaptureVideoDataOutput` (background queue, `alwaysDiscardsLateVideoFrames`, dropped before any
  work down to the capture-FPS setting). Use the picture's rect on the TV (CG coords) as the pipeline's
  "window frame": `RegionLayout` then places boxes on the TV unchanged. Draw with `OverlayContentView`
  inside the TV window, above the preview layer.
- **Measure first:** log how often the exact `FrameFingerprint` changes on a static Switch screen through
  the Kingma. If it changes on (nearly) every frame (MJPEG/HDMI noise), add a noise-tolerant change check
  (e.g. coarse luma grid, change = any cell differs by more than a small threshold); otherwise keep the
  exact fingerprint. Record the numbers in Implementation Notes.
- Capture regions (`captureRegions_v2`) are **one list for the whole app** — regions drawn for a Mac
  game would land in the wrong place on the Switch picture. Decision: TV Output ignores them and reads
  the whole picture. Separate TV regions → backlog.
- Glossary/profile: one game profile named after the capture card (the app can't tell which Switch
  game is running). Per-game profiles in TV mode → backlog.
- Display mode Panel/Overlay doesn't apply to TV Output: the translation is always drawn on the TV.

- Hint (2026-09-26, likely the least work): the Switch picture is now a normal window of our own app, so
  the **existing** pipeline could translate it like any game window — `ScreenCaptureService` on that
  window → OCR → Overlay **or** Panel, regions, history, learning all unchanged. The picture itself
  never waits for this (translation only reads a copy). Today `availableWindows()` excludes the app's
  own windows — the Switch window must be allowed. The alternative (a throttled
  `AVCaptureVideoDataOutput`) avoids the Screen Recording path; Claude Code picks and records why.

## Requirements
1. TV Output translates what's on the game picture and draws Thai boxes near the original text on the TV.
2. The picture stays full and unchanged underneath (not text only).
3. New dialogue replaces the old translation automatically; unchanged text is not re-OCR'd every frame
   and not re-translated (cache).
4. OCR and translation run off the main thread and never delay the picture.
5. Capture regions: if the existing pipeline is reused, regions work on the Switch window like on any game window; otherwise they are ignored (record which).
6. History and the Learning window receive TV Output translations like any other.
7. Existing window translation, overlay, panel and regions unchanged.
8. ⌃⌥V opens the Switch window **and** starts translating it; Overlay and Panel display modes both work
   on it, including in macOS full screen (the overlay/panel must show in the full-screen Space).

## Out of scope
- Settings (show original, opacity, delay, pickers) — T-0029. TV-specific regions. Per-game profiles.

## Constraints
- CLAUDE.md stability rules apply. Thai UI strings.

## Files / Modules
- `Sources/Services/PipelineCoordinator.swift`, `Sources/Services/CaptureCardService.swift`,
  `Sources/Overlay/TVOutputWindowController.swift`, `Sources/Overlay/OverlayContentView.swift`, `Tests/…`

## Acceptance Criteria
- **AC-1** [test] Frame-change logic unit-tested (whichever is chosen): same picture → no OCR; noise →
  no OCR (if the noise-tolerant check is added); a new line of text, and one added character
  (typewriter), → change.
- **AC-2** [code] OCR frames are dropped before any work down to the capture FPS; no OCR/translation on the main thread.
- **AC-3** [code] The picture path (preview layer) is unchanged; window translation path for other games unchanged.
- **AC-4** [build] Unit tests and Release build succeed.
- **AC-5** [manual] English dialogue → Thai box on the TV next to the text within a second or two after it stops typing.
- **AC-6** [manual] Next dialogue → old box replaced automatically; the log shows no repeated
  translation request for a line still on screen.
- **AC-7** [manual] While translating, the picture on the TV doesn't stutter; AC-8 of T-0027 re-run
  gives a median no worse than before (±1 frame).
- **AC-8** [manual] OBS closed throughout.

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
- **Approach chosen: the existing window pipeline on our own Switch window** (Cowork's 2026-09-26 hint),
  not a second frame source from `AVCaptureVideoDataOutput`. Why: the picture is now a normal window
  of the app (T-0032), so ScreenCaptureKit → OCR → TextTracker → cache → Overlay **or** Panel, regions,
  history and Learning all work unchanged, with no second pipeline to maintain. The preview layer is
  not touched; translation reads ScreenCaptureKit's copy of the window, so the picture never waits (AC-3).
  Trade-offs: needs the Screen Recording permission the app already has for window translation, and OCR
  sees the window at its on-screen size (full screen on the MacBook ≥ 1080p, fine).
- **Files outside *Files / Modules*** (all needed by this approach):
  `ScreenCaptureService.swift` — new `ownWindow(number:)` (looks up our own window; `availableWindows()`
  and the window picker unchanged). It calls `CGPreflightScreenCaptureAccess()` first and returns nil
  without access, so it can never show the system dialog. `StatusBarController.swift` — wiring.
  `CaptureCardWindowController.swift` / `TVOutputController.swift` — expose the window number.
  Not changed: `CaptureCardService`, `TVOutputWindowController`, `OverlayContentView`.
- **Flow (Req 8):** ⌃⌥V → picture window opens (T-0032) → `translateCaptureCardPicture()`: preflight →
  find the window in the shareable list (up to 5 tries, 0.2 s apart, in case the list lags) →
  `pipeline.start(window:profileID: <card name>)`. Display mode Overlay/Panel = the normal setting; both
  windows already have `.canJoinAllSpaces + .fullScreenAuxiliary`, so they show in the picture's
  full-screen Space.
- **Stopping:** ⌃⌥V, ⌃⌥T, "หยุดแปล", the menu stop item, picking a game window → `stopCaptureCard()`
  (closes the picture, then `await pipeline.stop()`). Red button / ⌘W / unplug / timeout → the
  `tvOutput.onChange` handler stops the pipeline. Stopping it before ScreenCaptureKit notices the window
  is gone keeps the "game window closed" message away.
- **Without Screen Recording access** (or window not found): the picture runs untranslated; the menu
  shows why under the capture card lines. Pipeline start errors (e.g. no API key) → alert
  "เริ่มแปลภาพ capture card ไม่ได้"; the picture keeps running.
- **Req 5 — regions:** the pipeline is reused, so capture regions work on the Switch window like on any
  game window. The region list is still app-wide (backlog item unchanged).
- **Profile:** `pipeline.start(window:profileID:)`; the capture card name is the game profile (default
  `nil` = app name, as before for game windows).
- **Frame change / "measure first":** exact `FrameFingerprint` + `FrameChangeFilter` kept (ScreenCaptureKit
  sends frames only when the window changes; a digital HDMI picture of a static screen should give
  identical pixels). New `FrameStats`: while translating the capture card, the log gets one line per
  10 s — `Capture card frames: N received, M with changed pixels, K sent to OCR in 10 s`. If M stays
  high on a static screen, a noise-tolerant check is the follow-up. **Numbers pending the owner's run.**
- **External display mode** (T-0027 path, not default): not translated — the borderless picture panel
  sits at `.screenSaver` level, above the overlay's `.floating`. For T-0029 when that mode becomes a
  setting (`translatableWindowNumber` returns nil there).
- AC-2: ScreenCaptureKit delivers at `captureFrameRate` (`minimumFrameInterval`), unchanged frames are
  skipped before OCR; OCR/translation run in the existing async pipeline, off the main thread.
- Verify note: in the first full run the test host sat idle and was killed; the next full run passed but
  `MeaningServiceTests.testChatterLeavesTheWordWithoutMeaningAndShowsAMessage` took 814 s (5 s when re-run
  alone). Unrelated to this change (MeaningService untouched) — see follow-ups.

## Result

**Outcome:** PARTIAL — `[test]`/`[code]`/`[build]` criteria pass; AC-5…AC-8 pending owner
**Version:** 1.17.1 → 1.18.0
**Commit:** `a1f83a3`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `CaptureCardFrameChangeTests`: `testSamePictureIsNotOCRdAgain`, `testNewLineOfTextIsAChange`, `testOneAddedCharacterIsAChange` (typewriter), `testResizedWindowIsProcessedEvenWithTheSamePicture`, `testFrameStatsReportsOncePerInterval`. Noise case: not applicable (exact fingerprint kept; measured by `FrameStats` in AC-5 run). |
| AC-2 | ✅ pass | Frames come from `ScreenCaptureService` at `settings.captureFrameRate`; `FrameChangeFilter` drops unchanged ones before `processFrame`; OCR/translation in the existing async pipeline. |
| AC-3 | ✅ pass | `CaptureCardService`, `TVPictureView`/preview layer unchanged; game-window path unchanged (`profileID` defaults to nil = old behaviour; `availableWindows()` unchanged). |
| AC-4 | ✅ pass | See below. |
| AC-5 | ⏳ pending owner | Steps below. |
| AC-6 | ⏳ pending owner | Steps below. |
| AC-7 | ⏳ pending owner | Steps below. |
| AC-8 | ⏳ pending owner | OBS closed throughout. |

### Build & test
```
Executed 249 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                              | 1.18.0
 Sources/App/StatusBarController.swift             | ⌃⌥V starts translating the picture; stopCaptureCard(); menu note
 Sources/Services/PipelineCoordinator.swift        | start(window:profileID:), FrameStats log
 Sources/Services/ScreenCaptureService.swift       | ownWindow(number:) (preflight first)
 Sources/Services/TVOutputController.swift         | translatableWindowNumber
 Sources/Overlay/CaptureCardWindowController.swift | windowNumber
 Tests/CaptureCardFrameChangeTests.swift           | (new, 5 tests)
```

### Manual checks for the owner
Install with `./build.sh`. Screen Recording must be allowed (as for window translation). OBS closed.

**AC-5** — ⌃⌥V → Switch window opens; menu shows "🎮 <card name>" and "สถานะ: กำลังทำงาน". Play to
English dialogue → Thai box next to the text within 1–2 s after the text stops typing. Try both
Overlay and Panel (Settings → display mode) and ⌃⌘F full screen — the boxes / panel stay visible.

**AC-6** — next dialogue → the old box is replaced. In `~/Desktop/GameTranslator.log` no repeated
translation request for a line that stays on screen. Also send the `Capture card frames:` lines taken on
a **static** screen (e.g. a paused dialogue) — they decide whether a noise-tolerant check is needed.

**AC-7** — while translating, the picture doesn't stutter; latency (T-0027 AC-8 method) no worse than
before (±1 frame).

Also: ⌃⌥V again (or the red button) → picture and translation stop together, no "หน้าต่างเกมถูกปิด"
message. The profile / glossary for the Switch is under the card's name in Settings → เกม.

### Proposed follow-ups
- If `Capture card frames` shows many changed frames on a static screen: noise-tolerant change check.
- Translation in external-display mode (T-0029): overlay level vs the `.screenSaver` picture panel.
- `MeaningServiceTests.testChatterLeavesTheWordWithoutMeaningAndShowsAMessage` can take very long
  (814 s once, 5 s alone, others 0.2 s) — check its `waitUntilIdle`.

---

## Review
**Cowork, 2026-09-26 — code passes; waiting for owner AC-5…AC-8.** Evidence: `build.noindex/Logs/Test` 14:10
(249 tests). Reuses the whole existing pipeline on our own Switch window (fewest new parts); picture path
untouched; `ownWindow` preflights before `SCShareableContent` (stability rule 1 kept); stop paths covered
(hotkeys, menu, red button, unplug). No blocking findings. Notes:
- External-display mode is not translated (panel at `.screenSaver` above the overlay) → added to T-0029.
- `FrameStats` log answers "measure first": send the `Capture card frames:` lines from a static screen.
- Slow `MeaningServiceTests` run (814 s once) → backlog, unrelated.

**2026-09-26 — REVIEW_FAILED (AC-7).** Translation works, but the game lags with it on: every frame counts
as changed (60/60 → OCR), 2× ScreenCaptureKit copy (WindowServer 43 %), kernel_task 22–28 % = throttling. → T-0034.

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-25 | → PLANNED | Cowork | split from T-0027; READY once T-0027 is DONE |
| 2026-09-26 | — | Cowork | amended: play on the Mac screen (T-0032), Overlay + Panel on the Switch window; depends on T-0032 |
| 2026-09-26 | PLANNED → READY | Cowork | T-0033 DONE |
| 2026-09-26 | READY → IN_PROGRESS | Claude Code | started |
| 2026-09-26 | IN_PROGRESS → REVIEW | Claude Code | test/code/build ACs pass; AC-5…AC-8 manual pending owner |
| 2026-09-26 | — | Cowork | code review passed; waiting for owner AC-5…AC-8 |
| 2026-09-26 | REVIEW → REVIEW_FAILED | Cowork | game lags with translation on (AC-7) → T-0034 |
