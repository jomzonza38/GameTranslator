# T-0019 — Pointing at a panel entry highlights its text in the game

| Field | Value |
|---|---|
| **Status** | READY |
| **Type** | feature |
| **Priority** | P2 |
| **Version impact** | minor |
| **Milestone** | M5 — Know where each translation came from |
| **Depends on** | T-0018 |
| **Corrects** | — |
| **Follow-up** | — |
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

## Result

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → READY | Cowork | follows T-0018 |
