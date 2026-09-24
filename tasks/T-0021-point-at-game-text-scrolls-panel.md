# T-0021 — Pointing at a text in the game brings its translation into view in the panel

| Field | Value |
|---|---|
| **Status** | READY |
| **Type** | feature |
| **Priority** | P2 |
| **Version impact** | minor |
| **Milestone** | M5 — Know where each translation came from |
| **Depends on** | T-0020 |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-24 by Cowork (owner request) |

## Objective
T-0019 goes panel → game: point at an entry, see its text outlined in the game. The
owner also wants the other direction: when the mouse rests on a text **in the game**,
the panel scrolls to that text's translation and marks it, so the player doesn't have
to scroll through a long panel (e.g. a craft menu with ~20 entries) to find it.

## Context
- Panel mode only (in Overlay mode the translation is already on the text).
- Each panel entry has a stable id and its `sourceRect` in CG screen coordinates
  (T-0019); T-0020 makes those rects line up with the game text. This task relies on it.
- The panel list is a SwiftUI `ScrollView` in `TranslationPanelContent` (no
  `ScrollViewReader` yet).
- The overlay/outline windows ignore mouse events and the game must keep receiving
  every click and hover (the game shows its own tooltips on hover).
- Hint: reading the mouse position (`NSEvent.mouseLocation`, polled a few times per
  second while translating in Panel mode) needs **no permission**. Don't use anything
  that triggers an Accessibility or Input Monitoring prompt. Global event monitors for
  mouse events may be fine, but check they don't prompt.
- Hint: while the player moves the mouse across the game, the panel must not jump
  around — react only after the mouse **rests** on a text for a moment.

## Requirements
1. In Panel mode, when the mouse rests on a translated text in the game for about
   0.4 s, the panel scrolls so that text's entry is visible and marks it (same look as
   the hovered row in T-0019).
2. The mark goes away when the mouse moves off the text (after the same short delay),
   and the panel does not scroll back or jump while the mouse is moving.
3. If the mouse is over the panel itself, game-pointing is ignored (T-0019 hover wins).
4. The same text shown twice: the entry for the copy under the mouse is chosen.
5. Clicks, hovers and keys still go to the game exactly as before; no new permission
   prompt of any kind.
6. A setting (Thai label, default on) turns this off.
7. Works in full-screen mode and in region mode.
8. Nothing runs when not translating, in Overlay mode, or with the panel collapsed/hidden;
   CPU on a static screen stays about the same (T-0016).

## Out of scope
- Clicking a game text to do something. Drawing a new kind of marker on the game.
- Changing the panel's sort order (backlog).

## Constraints
- CLAUDE.md stability rules apply (no new permission prompts; stop / game closed must
  clear the state without crash).
- Thai UI strings.

## Files / Modules
- `Sources/Overlay/TranslationPanelController.swift` (scroll to / mark entry)
- `Sources/Services/PipelineCoordinator.swift` or a small new helper for the mouse
  tracking (only while translating in Panel mode)
- `Sources/Models/AppSettings.swift`, `Sources/Views/SettingsWindow.swift` (toggle)
- `Tests/…`

## Acceptance Criteria
- **AC-1** [test] Given entries with source rects and a mouse point, the entry under the
  point is found (inside, outside, overlapping/duplicate texts → the one under the mouse).
- **AC-2** [test] The rest-delay logic: a point that moves every tick never selects;
  a point that stays on one text for ≥ 0.4 s selects it; leaving clears it after the delay.
- **AC-3** [test] The setting defaults to on and persists.
- **AC-4** [code] No new API that can show a permission dialog (no AXIsProcessTrusted
  prompt, no CGEventTap / IOHID input monitoring); the tracking stops when not
  translating, in Overlay mode or when the panel is hidden.
- **AC-5** [manual] Steps: full-screen Graveyard Keeper, stone cutter menu, Panel mode,
  make the panel short enough that it scrolls. Rest the mouse on "A carved piece of
  stone" in the game. Expected: within ~0.5 s the panel scrolls to its entry and marks it;
  the game's own hover/tooltip still works.
- **AC-6** [manual] Steps: sweep the mouse quickly across the menu. Expected: the panel
  doesn't jump while moving; only the text where the mouse stops gets marked.
- **AC-7** [manual] Steps: turn the setting off. Expected: pointing at the game does nothing
  to the panel.
- **AC-8** [manual] Steps: while a text is marked, press ⌃⌥T to stop, and separately quit
  the game. Expected: mark cleared, no crash/freeze.
- **AC-9** [build] Unit tests and Release build succeed.

## Testing Requirements
- Unit tests for AC-1 … AC-3. Owner runs AC-5 … AC-8 after T-0020 is DONE.

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
| 2026-09-24 | → READY | Cowork | owner: pointing at the game should bring its message into view |
