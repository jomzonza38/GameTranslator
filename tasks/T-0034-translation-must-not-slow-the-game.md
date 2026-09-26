# T-0034 — Translating the Switch picture must not slow the game down

| Field | Value |
|---|---|
| **Status** | READY |
| **Type** | fix |
| **Priority** | P1 (urgent) |
| **Version impact** | patch |
| **Milestone** | M7 — Capture card mode |
| **Depends on** | — (stacks on T-0028; owner commits T-0028 first) |
| **Corrects** | T-0028 |
| **Follow-up** | — |
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

## Result

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-26 | → READY | Cowork | owner: game lags with translation on; OCR every frame + 2× capture → throttling |
