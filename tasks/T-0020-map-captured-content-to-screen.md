# T-0020 — Outlines and overlay text must sit exactly on the game text

| Field | Value |
|---|---|
| **Status** | IN_PROGRESS |
| **Type** | fix |
| **Priority** | P1 |
| **Version impact** | patch |
| **Milestone** | M5 — Know where each translation came from |
| **Depends on** | — |
| **Corrects** | T-0019 |
| **Follow-up** | — |
| **Created** | 2026-09-24 by Cowork (owner's screenshot) |

## Objective
T-0019's outline appears next to the text it belongs to, not around it. The same
image → screen mapping places the Overlay-mode translations, so they are likely off by
the same amount. The outline and overlay text must land on the game text.

## Context
- **Owner's test, 2026-09-24, v1.11.29, Graveyard Keeper full-screen (black bars top
  and bottom), Panel mode, no regions.** Hovering the panel entry "A piece of stone" drew
  the outline **below-left of the text and smaller**, over an empty spot between two rows.
  Measured on the owner's screenshot (2000×1294 px, whole screen):
  - text "A piece of stone": x ≈ 520–817, y ≈ 420–465
  - outline: x ≈ 432–704, y ≈ 498–545 (includes the 4 pt padding)
  - So: shifted ≈ −90 px in x and ≈ +80 px in y, and ≈ 0.88× the text width.
- **The OCR box is right.** T-0018's thumbnail for that entry, cut from the captured
  image at the same `boundingBox`, shows exactly "A piece of stone". So the error is in
  mapping *captured image → screen*, not in the OCR or the crop.
- Hints (unverified, Claude Code decides):
  - `ScreenCaptureService.startCapture` fixes `config.width/height` from `window.frame`
    **at start**, and passes that same start frame as `contentRect` with every frame.
    `SCStreamFrameInfo` (`contentRect`, `contentScale`, `scaleFactor` in the sample
    buffer attachments) is never read. If the window's size changed after start
    (e.g. the game went full-screen), or the window's content doesn't fill the output
    buffer, ScreenCaptureKit scales/positions the content inside the buffer and
    "box × current window frame" is wrong. The backlog item "Game window resize /
    FPS change while running" is related.
  - `RegionLayout.buildRegions` maps with `screenCapture.currentWindowFrame`
    (`CGWindowListCopyWindowInfo` bounds). Check it matches the area that was captured
    (full-screen Space, notch / menu bar area, title bar).
  - Log the values first (window frame at start, current bounds, buffer size, frame
    info contentRect/scale) in the owner's scene; record them in Implementation Notes.

## Requirements
1. In the owner's scene (full-screen game with black bars), the hover outline surrounds
   the hovered text: every edge within ~6 pt of the text's edge.
2. Overlay-mode translations are placed on their English text in the same scene.
3. Also correct in a normal (non-full-screen) game window, and after the window is
   resized or switched to/from full-screen **while translating**.
4. Regions (normalized to the window) and the region selector keep working; a region
   drawn before this change still covers the same part of the game.
5. Thumbnails (T-0018) stay correct.

## Out of scope
- The panel listing number-only texts ("15", "7/1" → "71") — backlog.
- Duplicate-text keys (backlog from T-0018/T-0019 review).

## Constraints
- CLAUDE.md stability rules apply — in particular, restarting or reconfiguring the
  stream must not bring back the Screen Recording prompt, and a failure must stop
  cleanly with a Thai message (rule 2).
- No new `SCShareableContent` call without preflight.

## Files / Modules
- `Sources/Services/ScreenCaptureService.swift`
- `Sources/Services/PipelineCoordinator.swift`, `Sources/Services/RegionLayout.swift`
- `Sources/Overlay/OverlayWindowController.swift` (if the mapping moves)
- `Tests/…`

## Acceptance Criteria
- **AC-1** [code] Implementation Notes record the measured cause (logged values from
  the owner's scene or a reproduction) and why the fix addresses it.
- **AC-2** [test] The image → screen mapping is a pure function with tests for: buffer
  equal to the window; content letterboxed / scaled inside the buffer; window size
  changed since start. Each maps a known box to the expected screen rect.
- **AC-3** [manual] Steps: full-screen Graveyard Keeper, the stone cutter menu, Panel
  mode, no regions; hover each entry. Expected: the outline surrounds that text.
- **AC-4** [manual] Steps: same scene, Overlay mode. Expected: each Thai box sits on
  its English text.
- **AC-5** [manual] Steps: windowed game, start translating, then resize the window
  (or toggle full-screen) and wait for the next change on screen. Expected: outline /
  overlay still on the text; no crash, no permission prompt.
- **AC-6** [manual] Steps: with an existing region, translate. Expected: the region
  still covers the same area; its translations sit on the text.
- **AC-7** [build] Unit tests and Release build succeed.

## Testing Requirements
- Unit tests for the mapping (AC-2). Owner runs AC-3 … AC-6.

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

### Round 1 (2026-09-24) — fix the likely cause, measure the rest

**What the owner's numbers say** (screenshot 2000×1294 px ≈ a 1470×956 pt screen, so
×0.735): text x 382–600, y 309–342 pt; outline without its 4 pt padding x ≈ 322–513,
y ≈ 370–397 pt. So outline ≈ **(−14, +99) + 0.878 × true position** — scaled by 0.878 in
**both** axes and shifted.
- A pure letterbox (window scaled to fit a buffer of another aspect ratio) can't do
  that: one axis would keep scale 1.0.
- A window-frame / buffer mismatch with the content scaled or padded inside the buffer
  can. So can a window frame used for mapping that doesn't match what was captured.
- The arithmetic can't pick between these → the values are now logged (below) and
  must be read in the owner's scene (AC-1).

**Changes in this round**
1. **Capture follows the window size.** The stream used to be sized once from
   `SCWindow.frame` (a snapshot from the window list) and never changed. Now:
   - At start it is sized from the window's **live** CGWindowList bounds.
   - On every frame the coordinator compares the window's current size with the
     stream size (`CaptureGeometry.needsResize`, > 2 px) and calls
     `ScreenCaptureService.resizeCapture(toWindowSize:)` → `SCStream.updateConfiguration`.
     One resize at a time; a failure is logged and capture continues.
   - No permission or `SCShareableContent` call is involved.
2. **Frames are cropped to the window's content.** `StreamOutput` reads
   `SCStreamFrameInfo` (`contentRect`, `contentScale`, `scaleFactor`) from each frame.
   `CaptureGeometry.contentPixelRect` turns it into the window-content rect in buffer
   pixels. The units aren't documented precisely, so it tries × contentScale ×
   scaleFactor, × scaleFactor and as-is, and takes the largest that fits the buffer.
   If the content doesn't fill the buffer, the `CGImage` is cropped to it before OCR.
   From then on, every normalized coordinate (OCR boxes, regions, thumbnails) is
   relative to the **window**, which is what `buildRegions` and the region selector
   assume — so regions drawn earlier keep covering the same part (Req 4), and
   thumbnails stay right (Req 5).
3. **One tested mapping.** `RegionLayout.buildRegions` now uses
   `CaptureGeometry.screenRect(forContentBox:windowFrame:)`, the same function the
   tests cover.
4. **Diagnostics in `GameTranslator.log`** (one line per change):
   - `Capture geometry at start: SCWindow.frame=… live bounds=… output=WxH`
   - `Capture frame geometry: buffer=… contentRect=… contentScale=… scaleFactor=… → window content in buffer=…`
   - `Window frame (CGWindowList): …`
   - `Capture resized to follow the window: A → B`

**Still open — AC-1 needs the owner's log.** I can't run the capture here: a build
other than the installed one would ask for Screen Recording (stability rule 1). Needed
from the owner's scene (full-screen Graveyard Keeper, stone cutter menu), after
`./build.sh`: the lines above from `~/Desktop/GameTranslator.log`, and whether the
outline now surrounds the text.
- If they show `SCWindow.frame` ≠ live bounds at start, or a `Capture resized…` line
  when the game went full-screen, then (1) was the cause.
- If `window content in buffer` is inset, then (2) is what corrects it.
- If neither, and the outline is still off, the values say where the remaining offset
  comes from (e.g. the window frame vs the captured area), and round 2 fixes that.

## Result

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → READY | Cowork | corrects T-0019 (AC-4 failed on owner's screenshot) |
| 2026-09-24 | READY → IN_PROGRESS | Claude Code | started |
| 2026-09-24 | (IN_PROGRESS) | Claude Code | round 1 done (capture follows window size, crop to content rect, diagnostics, AC-2 tests pass); waiting for the owner's geometry log for AC-1 |
