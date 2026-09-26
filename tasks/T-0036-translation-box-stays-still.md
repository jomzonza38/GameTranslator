# T-0036 — The translation box stays still while the dialogue doesn't change

| Field | Value |
|---|---|
| **Status** | READY |
| **Type** | fix |
| **Priority** | P1 (urgent) |
| **Version impact** | patch |
| **Milestone** | M7 — Capture card mode |
| **Depends on** | — (stacks on T-0035; owner commits T-0035 first) |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-26 by Cowork |

## Objective
Owner, 2026-09-26 (capture card mode, 1.19.0): "the dialogue doesn't move, but the translation box keeps
moving — translating back and forth, never still". A still line must show one still Thai box.

## Context
- Same screen gives different OCR results run to run: 7 ↔ 8 texts alternating (T-0034/T-0035 logs), i.e. a
  line sometimes merged/split, a text appearing/disappearing, letters misread.
- Likely effects (to confirm from `~/Desktop/GameTranslator.log` first — record what is seen):
  1. `OverlayContentView` keys layers by `originalText`: a slightly different OCR string = remove + fade-in
     of a new layer → flicker; possibly a new translation request → "translating back and forth".
  2. `RegionLayout.resolveOverlaps` pushes boxes down depending on how many boxes exist → when an 8th text
     appears/disappears, other boxes jump.
  3. Bounding boxes jitter a few pixels between runs → boxes slide.
- Before T-0034 the pipeline ran at ~5 OCR/s so this was hidden in general lag; now each flip is visible.
- Applies to Overlay and Panel mode; worst in full-picture mode (no regions).

## Requirements
1. While the text on screen doesn't change, the Thai box keeps its text, position and size (no fade, no jump).
   Small OCR differences (misread letter, merge/split of the same lines, bbox jitter of a few px) must not
   change what is shown.
2. No new translation request for a line already translated when OCR only differs by noise (log shows none).
3. A text that disappears for one OCR run and comes back must not blink (keep it for a short grace, e.g. 1–2
   reads, before removing).
4. Real changes still show within ~2 s (T-0035 AC-5) and a box leaves when its text really leaves.
5. Window translation of normal games (⌃⌥T) gets the same stability or stays unchanged — no regression.

## Out of scope
- OCR accuracy itself; Settings (T-0029).

## Constraints
- CLAUDE.md stability rules apply. Keep T-0034/T-0035 CPU gains (no extra OCR runs).

## Files / Modules
- `Sources/Services/PipelineCoordinator.swift`, `Sources/Services/RegionLayout.swift`, `Sources/Services/TextTracker.swift`,
  `Sources/Overlay/OverlayContentView.swift`, `Sources/Overlay/TranslationPanelController.swift`, `Tests/…`

## Acceptance Criteria
- **AC-1** [test] A sequence of OCR frames of one still screen with noise (7↔8 texts, one misread letter,
  merged/split lines, ±3 px boxes) → identical displayed regions (text + rect) every frame, no new translation request.
- **AC-2** [test] A text missing in one frame and back in the next → still displayed; missing for longer → removed.
- **AC-3** [test] A real new line → shown; others don't move.
- **AC-4** [build] Unit tests and Release build succeed.
- **AC-5** [manual] Owner: still dialogue for 30 s → Thai box doesn't move or change; next line → new Thai ≤ 2 s.
  Log shows no repeated translation of the same line.

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
| 2026-09-26 | → READY | Cowork | owner: translation box keeps moving on an unchanged line |
