# T-0016 — A static screen must cost almost no CPU while capturing

| Field | Value |
|---|---|
| **Status** | READY |
| **Type** | fix |
| **Priority** | P2 |
| **Version impact** | patch |
| **Milestone** | M4 — Performance & first use |
| **Depends on** | — |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-24 by Cowork (owner measurement during T-0015 review) |

## Objective
While capturing a game window that doesn't change (a dialog waiting for a click, or
while paused after a refused key), GameTranslator uses **~43 % CPU** on the owner's
MacBook Air. It should be close to idle. It was 0 % when not capturing.

## Context
- Measurements, 2026-09-24, v1.11.25: not started 0 %; static screen, everything
  translated ~43 %; paused ~43 %. Full `sample` output in the owner's
  `~/Desktop/gt-sample.txt` (10:17). Summary in the T-0015 Review.
- Hot path 1 — `StreamOutput.stream(...)` (`ScreenCaptureService.swift` ~l.300):
  `let context = CIContext()` **per frame**. The profile shows Metal context
  creation/destruction dominating the capture queue.
- Hot path 2 — Vision OCR runs on every delivered frame (static or not, paused or
  not), with `NSRegularExpression` built during OCR text cleaning.
- ScreenCaptureKit keeps delivering frames with image buffers for this window at the
  configured FPS (6), so "static screen → no frames" can't be relied on. T-0015's
  re-run must keep working either way.
- Audit v1.11.11 items 15 (`CIContext` per frame) and 16 (work on MainActor every
  frame) are related.
- Hints: one reused `CIContext`, or give Vision the `CVPixelBuffer` directly; skip
  OCR when the frame is unchanged (cheap pixel/downsampled hash) unless T-0015 work
  is waiting; while paused there is nothing to translate. The HOW is Claude Code's call.

## Requirements
1. Capturing a static window: GameTranslator CPU averages **≤ 10 %** (owner's
   `top` command below) with everything translated, and while paused.
2. A moving screen still gets translated as before (latency, typewriter text,
   T-0015 re-runs, stale grace, similar-text reuse).
3. No new crash or freeze paths (CLAUDE.md stability rules); no extra permission prompts.

## Out of scope
- The ~74 s first OCR after a new build (T-0017). FPS setting UI.

## Constraints
- CLAUDE.md stability rules apply.

## Files / Modules
- `Sources/Services/ScreenCaptureService.swift`, `Sources/Services/OCRService.swift`
- `Sources/Services/PipelineCoordinator.swift` if frame skipping lives there
- `Tests/…`

## Acceptance Criteria
- **AC-1** [code] No `CIContext` (or equivalent heavy object) is created per frame.
- **AC-2** [test] The "skip this frame" decision (if added) is unit-tested: unchanged frame → skip; changed frame, or T-0015 work waiting → process.
- **AC-3** [manual] Steps: TextEdit with a few English words, start, translate, don't touch it. Run `top -l 6 -s 5 -pid $(pgrep -x GameTranslator) -stats pid,cpu | grep -E '^[0-9]'` (ignore the first sample). Expected: average ≤ 10 %. Repeat while paused with key `sk-test`: ≤ 10 %.
- **AC-4** [manual] Steps: type new words into TextEdit while translating, then switch provider. Expected: new words translated as quickly as before; T-0015 AC-3 still passes.
- **AC-5** [build] Unit tests and Release build succeed.

## Testing Requirements
- AC-2 unit test; owner runs AC-3, AC-4.

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
| 2026-09-24 | → READY | Cowork | from T-0015 review (sample: CIContext per frame + OCR every frame) |
