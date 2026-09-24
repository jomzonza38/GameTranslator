# T-0019 — Pointing at a panel entry highlights its text in the game

| Field | Value |
|---|---|
| **Status** | REVIEW |
| **Type** | feature |
| **Priority** | P2 |
| **Version impact** | minor |
| **Milestone** | M5 — Know where each translation came from |
| **Depends on** | T-0018 |
| **Corrects** | — |
| **Follow-up** | T-0020 |
| **Created** | 2026-09-24 by Cowork |

## Objective
A thumbnail (T-0018) shows *what* the source text looks like; when similar texts
appear in several places the player still needs to see *where* it is. Moving the mouse
over a panel entry should outline that entry's source text on the game screen.

## Context
- Each `TranslatedRegion` already has `screenRect` (screen coordinates, multi-monitor
  correct since T-0009). `TranslationPanelData.Entry` does not keep it today.
- The overlay window is click-through and exists in both modes (see
  `OverlayWindowController`); in Panel mode it currently shows nothing.
- `Entry.id` changes on every update — a hover state keyed by it would be lost each frame.
  Hint: key by something stable.

## Requirements
1. Hovering a panel entry draws a clearly visible outline (rounded,
   not filled) around the entry's source text on the game screen.
2. The outline goes away within ~1 s after the mouse leaves the entry, and immediately
   when translation stops, the game window closes or the panel hides.
3. The outline never blocks clicks to the game (click-through).
4. Works in full-screen mode and in region mode (in region mode the outline may use
   the region's colour).
5. If the text moves or disappears while hovered, the outline follows or disappears —
   it never stays on an empty spot.

## Out of scope
- Overlay mode (the translation is already on the text). Numbered badges (backlog).
- Clicking an entry to do something.

## Constraints
- CLAUDE.md stability rules apply (stop / game closed / reopen must clear it — rule 2).
- No new capture or permission API calls.

## Files / Modules
- `Sources/Overlay/TranslationPanelController.swift`
- `Sources/Overlay/OverlayWindowController.swift`, `Sources/Overlay/OverlayContentView.swift`
- `Sources/Models/TranslatedRegion.swift` (if the entry needs the rect)
- `Tests/…`

## Acceptance Criteria
- **AC-1** [test] The hovered entry maps to the right screen rect after the panel
  data is updated with an unchanged text (hover survives updates).
- **AC-2** [test] The highlight is cleared when the hovered text is no longer in the
  latest update, and when the pipeline stops.
- **AC-3** [code] The highlight window/layer ignores mouse events.
- **AC-4** [manual] Steps: full-screen Panel mode with 2+ texts on screen; move the mouse
  over each panel entry. Expected: an outline appears around that text in the game,
  and disappears shortly after the mouse leaves.
- **AC-5** [manual] Steps: hover an entry, then press ⌃⌥T to stop (and separately:
  quit the game while hovering). Expected: outline disappears, no crash or freeze.
- **AC-6** [manual] Steps: regions defined, Panel mode, hover an entry. Expected:
  outline around the right text inside the region; clicks still reach the game.
- **AC-7** [build] Unit tests and Release build succeed.

## Testing Requirements
- Unit tests for AC-1, AC-2. Owner runs AC-4 … AC-6 (a second display if available).

## Definition of Done
- [ ] All acceptance criteria pass (`[manual]` ones confirmed by the owner)
- [ ] Unit tests added/updated as required; full suite passes
- [ ] Release build succeeds
- [ ] Version bumped per CLAUDE.md (or "none" justified)
- [ ] `git diff` contains only changes justified by this task
- [ ] Result section complete; Cowork review passed

---

## Questions

## Implementation Notes

- **Where the text is:** new `TranslatedRegion.sourceRect` — the text's on-screen box
  when the region is built (CG screen coordinates, from the live window frame). The
  copy helpers keep it, so it is **not** moved when `resolveOverlaps` pushes
  overlapping boxes down (`withScreenRect`). The outline therefore surrounds the real
  text, not the shifted translation box.
- **Stable entries (hint):** `TranslationPanelData.Entry.id` is now
  `"<region id or full>|<source text>#<occurrence>"` instead of a new `UUID` per
  update. The same text in two places gets `#0` / `#1`, so SwiftUI ids stay unique.
- **Hover state (pure, unit-tested) in `TranslationPanelData`:**
  - `setHovered(id, isInside:)` is called from each row's `.onHover`.
  - `hoveredID` plus a published `highlight` (`rect` = entry's `sourceRect`,
    `regionColor`).
  - On every `update(from:)`, the highlight follows the hovered text's new rect
    (Req 5: moves with it). If the text is no longer on screen, the hover is dropped
    and the highlight becomes nil (Req 5: never an empty spot). `clear()` drops both.
  - The hovered row also gets a slightly brighter background.
- **Drawing (Req 1, 3):** new `SourceHighlightWindow` (in `OverlayWindowController.swift`),
  a separate small borderless window. The existing overlay window is hidden in Panel
  mode, so it can't host the outline.
  - `ignoresMouseEvents = true`, so clicks go to the game (AC-3).
  - Level just above `.floating`, so it's above the game and the overlay.
  - A rounded 3 pt stroke, not filled, with a dark halo so it shows on bright and dark
    screens. Colour: the region's colour in region mode (Req 4), yellow in full-screen
    mode.
  - Positioned with `ScreenCoordinates.appKitRect(fromCG:)` (T-0009), so it is correct
    on any display. 4 pt padding.
- **Wiring:** `TranslationPanelController` subscribes once to `panelData.$highlight`
  and shows, moves or hides the window. Its subscription is separate from the one
  `hide()` clears.
- **Going away (Req 2):**
  - Mouse leaves the row → cleared immediately (well within ~1 s).
  - Stop, game closed (T-0002 teardown), switch to Overlay mode, panel closed →
    `panelController.hide()` → `panelData.clear()` plus an explicit
    `sourceHighlight.hide()`.

## Result

**Outcome:** PARTIAL — `[test]`/`[code]`/`[build]` criteria pass; AC-4 … AC-6 pending owner
**Version:** 1.11.28 → 1.11.29
**Commit:** `0acb92a`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `PanelHoverTests`: `testHoveredEntryMapsToItsSourceRect`, `testHoverSurvivesAnUpdateWithUnchangedText` (new region objects, moved text → outline follows), `testOutlineUsesSourceRectNotThePushedDisplayRect`, `testRegionModeOutlineUsesTheRegionColour`, `testSameTextTwiceGetsDistinctEntries`. |
| AC-2 | ✅ pass | `testOutlineClearedWhenTheTextIsGone`, `testOutlineClearedWhenThePipelineStops` (`clear()`, called by `hide()` on stop / game closed), `testOutlineClearedWhenTheMouseLeaves`. |
| AC-3 | ✅ pass | `SourceHighlightWindow.makeWindow`: `window.ignoresMouseEvents = true`. |
| AC-4…AC-6 | ⏳ pending owner | Steps below. |
| AC-7 | ✅ pass | `Executed 132 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 132 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files (this task only, on top of T-0018)
```
 Resources/Info.plist                              | 1.11.29
 Sources/Models/TranslatedRegion.swift             | sourceRect
 Sources/Overlay/TranslationPanelController.swift  | stable Entry.id, hover/highlight state, onHover, wiring
 Sources/Overlay/OverlayWindowController.swift     | SourceHighlightWindow
 Tests/PanelHoverTests.swift                       | (new, 8 tests)
```

### Manual checks for the owner
After `./build.sh`:
- **AC-4:** full-screen Panel mode, 2+ texts on screen → move the mouse over each
  panel entry → a yellow rounded outline appears around that text in the game and
  goes away when the mouse leaves the entry.
- **AC-5:** hover an entry, press ⌃⌥T → outline disappears, no crash or freeze.
  Separately: hover an entry and quit the game → outline disappears (with the
  "game window closed" message).
- **AC-6:** regions defined, Panel mode → hover an entry → outline (region colour)
  around the right text inside the region; click in the game where the outline is →
  the click reaches the game.
- Optional: a second display — the outline sits on the text there too.

### Proposed follow-ups
- none

---

## Review

**Cowork, 2026-09-24 — owner test on v1.11.29: REVIEW_FAILED (AC-4).**
- AC-4 ❌: full-screen Graveyard Keeper, stone cutter menu, hovering "A piece of stone" drew the
  outline below-left of the text and ~0.88× its width (screenshot: text x≈520–817 y≈420–465,
  outline x≈432–704 y≈498–545, 2000×1294 px).
- The hover logic itself works (right entry, outline appears/disappears). T-0018's thumbnail
  for the same entry is correct, so the OCR box is right and the fault is the image → screen
  mapping that `sourceRect` inherits from `buildRegions` (shared with Overlay mode).
- Fix goes in corrective task **T-0020**. AC-5/AC-6 to be re-checked there.

**Cowork, 2026-09-24 — code review passed; waiting for owner's AC-4…AC-6.**

| AC | Verdict | Note |
|---|---|---|
| AC-1 | ✅ | Stable `Entry.id` (region + text + occurrence); `update(from:)` re-reads the hovered entry's `sourceRect`. `sourceRect` is set in the initializer from the unpushed box and kept by `withScreenRect`, so the outline surrounds the real text. |
| AC-2 | ✅ | Hover dropped when the id is gone; `clear()` on `hide()` (stop, game closed, Overlay mode, panel closed) plus an explicit `sourceHighlight.hide()`. |
| AC-3 | ✅ | `ignoresMouseEvents = true` on the outline window. |
| AC-4…AC-6 | ⏳ owner | — |
| AC-7 | ✅ | 132 tests (Claude Code's evidence). |

- Separate small window instead of reusing the overlay (hidden in Panel mode): right choice.
- Row-to-row moves are safe in either event order (`setHovered(_, false)` only clears its own id).
- Collapse is by button only (no auto-collapse), so the mouse always leaves the row first — no stuck outline.
- **Note (not blocking):** for the same text twice, `#0`/`#1` follow the top-to-bottom sort. If the two
  boxes swap vertical order between frames, the hover jumps to the other copy. Rare; → backlog with
  T-0018's note (key by text + position).
- Owner, please also check during AC-4: move the game window while hovering → the outline follows
  on the next change on screen (a static screen skips runs by design, T-0016).

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → READY | Cowork | follows T-0018 |
| 2026-09-24 | READY → IN_PROGRESS | Claude Code | started (stacked on T-0018, uncommitted) |
| 2026-09-24 | IN_PROGRESS → REVIEW | Claude Code | test/code/build ACs pass; AC-4…AC-6 manual pending owner |
| 2026-09-24 | — | Cowork | code review passed; waiting for owner manual ACs |
| 2026-09-24 | REVIEW → REVIEW_FAILED | Cowork | outline misplaced in owner's test; → T-0020 |
