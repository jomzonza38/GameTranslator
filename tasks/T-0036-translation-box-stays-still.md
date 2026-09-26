# T-0036 — The translation box stays still while the dialogue doesn't change

| Field | Value |
|---|---|
| **Status** | REVIEW |
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
- **Log first:** reading `~/Desktop/GameTranslator.log` was not permitted in this session, so the cause was
  worked out from the code (the three effects in *Context* all follow from OCR differing run to run: the
  overlay keys by `originalText`, `resolveOverlaps` depends on which boxes exist, boxes are the raw OCR boxes).
  The owner's AC-5 run confirms it.
- **Fix: `StableTextBoard`** (new `Sources/Services/StableTextBoard.swift`, pure; one per
  `RegionPipelineState`), used in capture card mode between line merging and the diff in `prepareRegion`.
  It remembers the texts shown (first reading + box) and maps each OCR run onto them:
  - same text → same entry (anywhere: scrolled text keeps its entry, the box follows only if it moved a lot,
    IoU < 0.6 — so ±3 px jitter keeps the old box);
  - misread letters (similarity ≥ 0.85, boxes touch) → same entry, **first reading kept** → no new request;
  - split (≥ 2 pieces inside an entry's box that add up to it) and merge (one reading covering ≥ 2 entries that
    add up to it) → those entries; "add up" = equal letters/digits give or take ≤ 2 edits (3 % of long text),
    strict so typewriter text can't pass as a merge;
  - text that grows (typewriter: extends the old reading) or a different text at the same place → replaces
    the entry at once (no grace for replaced text);
  - an entry missing from a run stays for 1 more run (grace); missing twice → removed. While an entry is in
    grace the pipeline re-reads the last frame after 0.5 s, so a text that really left goes even on a static
    screen (`planRerun`, `graceRecheck`).
- Everything downstream (diff, stability gate, cache, pacer, overlay/panel keys, `resolveOverlaps`) now sees
  the same texts and boxes on a still screen → identical regions, no fade, no jump, no request.
- **Req 5:** only capture card mode uses the board; ⌃⌥T window translation is unchanged (it didn't show the
  problem at its old rate; turning it on there is a one-line change if wanted later).
- Files: `StableTextBoard.swift` is new (pure logic, testable); `RegionPipelineState` holds the board;
  `RegionLayout`, `TextTracker`, `OverlayContentView`, `TranslationPanelController` did not need changes.
- CPU (T-0034/35): no extra OCR on still screens; one extra re-read of the same frame only while a text is in
  grace.

## Result

**Outcome:** PARTIAL — `[test]`/`[build]` criteria pass; AC-5 pending owner
**Version:** 1.19.0 → 1.19.1
**Commit:** `e5d9101`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `StableTextBoardTests.testNoisyReadingsOfAStillScreenShowTheSameBoxes`: 9 runs of one screen (7↔8 texts, misread letter, merged lines, split line, ±3 px, a text missing once) → identical `buildRegions` + `resolveOverlaps` output (text + rect) every run, and no text without an existing translation (= no request). |
| AC-2 | ✅ pass | `testTextMissingOnceStaysAndMissingTwiceGoes`. |
| AC-3 | ✅ pass | `testNewLineIsShownAndOthersDoNotMove`, `testNextDialogueReplacesTheOldLineAtOnce`, `testTypewriterTextFollowsUntilComplete`, `testShortNewLineIsNotTakenForAPieceOfTheOldOne`, `testScrolledTextKeepsItsEntryAndMoves`. |
| AC-4 | ✅ pass | See below. |
| AC-5 | ⏳ pending owner | Steps below. |

### Build & test
```
Executed 273 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                        | 1.19.1
 Sources/Services/StableTextBoard.swift      | (new) maps noisy OCR runs onto the shown texts
 Sources/Services/RegionPipelineState.swift  | textBoard (+ reset)
 Sources/Services/PipelineCoordinator.swift  | board in prepareRegion (capture card mode), grace re-read
 Tests/StableTextBoardTests.swift            | (new, 8 tests)
```

### Manual checks for the owner
`./build.sh`, ⌃⌥V, full screen, no regions.

**AC-5** — leave a dialogue line still for 30 s: the Thai box doesn't move, fade or change. In
`~/Desktop/GameTranslator.log` no second `✓ "…" → "…"` line for the same English line. Next dialogue → new
Thai ≤ 2 s; the old box goes. Also try Panel mode (entries stay still) and a menu/scrolling screen (boxes
follow scrolled text, leave when it's gone).

### Proposed follow-ups
- Use the board for ⌃⌥T window translation too, if games show the same flicker.

---

## Review
**Cowork, 2026-09-26 — code passes; waiting for owner AC-5.** Evidence: `build.noindex/Logs/Test` 16:33 (273 tests).
`StableTextBoard` keeps the first reading + box per text (jitter, misread letter, split/merge, one-run gap) so
everything downstream sees identical input; typewriter/new text replaces at once; strict "add up" rule stops
typewriter text passing as a merge. Capture card mode only (⌃⌥T unchanged, one-line switch later).
Note: the log step was skipped (outside-folder read blocked) — cause inferred from code; AC-5 decides.
No blocking findings.

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-26 | → READY | Cowork | owner: translation box keeps moving on an unchanged line |
| 2026-09-26 | READY → IN_PROGRESS | Claude Code | started |
| 2026-09-26 | IN_PROGRESS → REVIEW | Claude Code | test/build ACs pass; AC-5 manual pending owner |
| 2026-09-26 | — | Cowork | code review passed; waiting for owner AC-5 |
