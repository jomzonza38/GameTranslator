# T-0028 — TV Output (2/3): Thai translation over the game picture on the TV

| Field | Value |
|---|---|
| **Status** | PLANNED |
| **Type** | feature |
| **Priority** | P2 (normal) |
| **Version impact** | minor |
| **Milestone** | M7 — TV Output |
| **Depends on** | T-0030 (T-0027 corrected) |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-25 by Cowork |

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

## Requirements
1. TV Output translates what's on the game picture and draws Thai boxes near the original text on the TV.
2. The picture stays full and unchanged underneath (not text only).
3. New dialogue replaces the old translation automatically; unchanged text is not re-OCR'd every frame
   and not re-translated (cache).
4. OCR and translation run off the main thread and never delay the picture.
5. Capture regions are ignored in TV Output; window translation keeps using them as before.
6. History and the Learning window receive TV Output translations like any other.
7. Existing window translation, overlay, panel and regions unchanged.

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
- **AC-3** [code] TV Output does not read `captureRegions`; window translation path unchanged.
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

## Result

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-25 | → PLANNED | Cowork | split from T-0027; READY once T-0027 is DONE |
