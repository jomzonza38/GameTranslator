# T-0009 — Overlay, panel and region selector must be placed correctly on multi-monitor setups

| Field | Value |
|---|---|
| **Status** | READY |
| **Type** | fix |
| **Priority** | P3 |
| **Version impact** | patch |
| **Milestone** | M2 — Reliability & UX |
| **Depends on** | — |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-23 by Cowork (code audit v1.11.11, finding 7) |

## Objective
With more than one display, the translated overlay, the floating panel and the
region selector must line up with the game window, whichever screen the game is on
and whichever screen has focus.

## Context
- Window frames from ScreenCaptureKit / `CGWindowListCopyWindowInfo` use global
  coordinates with the origin at the top-left of the **primary** display.
- The code converts them to AppKit coordinates using `NSScreen.main` — the screen
  with the key window, not the primary display:
  `OverlayWindowController.convertToScreenCoordinates`,
  `RegionSelectorWindow.show(over:)`, `TranslationPanelController.positionPanel`.
- When displays have different heights, boxes are shifted vertically (or off-screen).
- Single-display behaviour must not change.

## Requirements
1. All CG→AppKit conversions use the primary display's height (one shared helper
   preferred, so the three places cannot drift apart).
2. The overlay covers the game window and the region selector covers exactly the
   game window on any display.
3. The panel opens next to the game window on the display the game is on.

## Out of scope
- Game window resize handling; Retina scale assumptions in capture (backlog).

## Constraints
- CLAUDE.md stability rules apply.

## Files / Modules
- `Sources/Overlay/OverlayWindowController.swift`
- `Sources/Overlay/RegionSelectorWindow.swift`
- `Sources/Overlay/TranslationPanelController.swift`
- `Tests/…` for the conversion helper

## Acceptance Criteria
- **AC-1** [test] Unit test for the conversion helper with a primary display and a
  second display of a different height (rects on both).
- **AC-2** [code] No `NSScreen.main` left in CG→AppKit coordinate conversion.
- **AC-3** [manual] Steps (needs two displays of different height): put the game on
  the secondary display, click on the primary display, start translating in
  Overlay mode, then add a region. Expected: overlay boxes sit on the game text;
  the selector covers exactly the game window.
- **AC-4** [manual] Steps: single display — translate in Overlay and Panel mode.
  Expected: unchanged from before.
- **AC-5** [build] Unit tests and Release build succeed.

## Testing Requirements
- AC-1 unit test; owner runs AC-3 (if a second display is available) and AC-4.

## Definition of Done
- [ ] All acceptance criteria pass (`[manual]` ones confirmed by the owner)
- [ ] Unit tests added; full suite passes
- [ ] Release build succeeds
- [ ] Version bumped per CLAUDE.md (patch)
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
| 2026-09-23 | → READY | Cowork | created from code audit v1.11.11 |
