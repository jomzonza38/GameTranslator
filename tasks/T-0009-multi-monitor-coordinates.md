# T-0009 — Overlay, panel and region selector must be placed correctly on multi-monitor setups

| Field | Value |
|---|---|
| **Status** | REVIEW |
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

- **Shared helper (Req 1):** new `Sources/Overlay/ScreenCoordinates.swift` (new file,
  outside the listed ones — the spec prefers one shared helper, and it belongs to
  none of the three controllers):
  - `appKitRect(fromCG:primaryDisplayHeight:)`: pure conversion,
    `y = primaryHeight − rect.maxY`.
  - `appKitRect(fromCG:)` (`@MainActor`): same, with the height of
    `NSScreen.screens.first` — the **primary** display (menu bar, global origin),
    not `NSScreen.main` (the screen with the key window).
  - `indexOfScreen(showingMostOf:screenFrames:)`: pure; picks the screen with the
    largest overlap. `screen(showingMostOf:)` wraps it for `NSScreen` and falls back
    to the primary display.
- **Callers:**
  - `OverlayWindowController.convertToScreenCoordinates` → the helper (Req 2, overlay).
  - `RegionSelectorWindow.show(over:)` → the helper (Req 2, selector). The selector's
    normalized-rect math uses its own view bounds and is unchanged.
  - `TranslationPanelController.positionPanel(near:)` converts with the helper and
    takes `visibleFrame` from the screen showing most of the game window, instead of
    `NSScreen.main` (Req 3). The placement rules (right side, else left, else screen
    edge; bottom aligned with the game) are unchanged.
- **Single display (AC-4):** primary display == `NSScreen.main`, so every result is
  identical to before. Only difference: if AppKit reported no screens at all, the
  selector used to silently not open; now it opens with the unconverted rect (not a
  real-world case).
- **Other `NSScreen.main` uses left alone** (not CG→AppKit conversions):
  `TranslationPanelController` line ~499 (collapse anchoring, AppKit↔AppKit),
  `StatusBarController` (welcome window placement), `OverlayContentView`
  (`contentsScale` = Retina factor; can be wrong on mixed-DPI setups → follow-up).

## Result

**Outcome:** PARTIAL — all `[test]`/`[code]`/`[build]` criteria pass; AC-3 and AC-4 pending owner
**Version:** 1.11.18 → 1.11.19
**Commit:** `7574368`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `ScreenCoordinatesTests` (4 tests): primary 1440×900 + taller secondary 2560×1440 — rects on the primary, on the secondary (incl. below the primary's bottom → negative y), a check that using the secondary's height would be wrong, and screen selection (primary, secondary, spanning, off-screen). |
| AC-2 | ✅ pass | `grep NSScreen.main` in the three files → only `TranslationPanelController` ~499, which is AppKit-only collapse anchoring, not a CG→AppKit conversion. |
| AC-3 | ⏳ pending owner | Needs two displays of different height; steps below. |
| AC-4 | ⏳ pending owner | Steps below. |
| AC-5 | ✅ pass | `Executed 78 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 78 tests, with 0 failures (0 unexpected) in 0.421 (0.459) seconds
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                              |  2 +-
 Sources/Overlay/OverlayWindowController.swift     | 10 +---------
 Sources/Overlay/RegionSelectorWindow.swift        | 11 ++---------
 Sources/Overlay/TranslationPanelController.swift  | 10 +++++-----
 Sources/Overlay/ScreenCoordinates.swift           | (new)
 Tests/ScreenCoordinatesTests.swift                | (new, 4 tests)
 tasks/BOARD.md, tasks/T-0009-…md                  | (status + this report)
```

### Manual checks for the owner
After `./build.sh`:

**AC-3 (two displays of different height, if available):** put the game on the
secondary display, click something on the primary display, start translating in
Overlay mode → boxes sit on the game text. Menu → "➕ เพิ่มพื้นที่แปล..." → the dark
selector covers exactly the game window. Switch to Panel mode → the panel opens next
to the game on the secondary display.

**AC-4 (single display):** translate in Overlay and in Panel mode, and add a region.
Expected: everything is placed exactly as before.

### Proposed follow-ups
- `OverlayContentView` uses `NSScreen.main?.backingScaleFactor` for text sharpness;
  with a Retina + non-Retina pair the overlay text may be blurry on one display.
  Could use the overlay window's own screen. Minor.

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-23 | → READY | Cowork | created from code audit v1.11.11 |
| 2026-09-23 | READY → IN_PROGRESS | Claude Code | started |
| 2026-09-23 | IN_PROGRESS → REVIEW | Claude Code | test/code/build ACs pass; AC-3, AC-4 manual pending owner |
