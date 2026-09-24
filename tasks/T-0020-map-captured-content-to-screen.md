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

**Round 1 commit:** `6730abe` (v1.11.30).

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

**Cowork, 2026-09-24 — owner test of round 1 (v1.11.30): still off, but the log pins the cause.**

Result: the outline is now the right **width and x** (hovered "A polished brick of stone":
text x≈520–965 px, outline x≈514–973 px incl. padding), but it sits **one row too low**
(text y≈578–620 px, outline y≈637–687 px; screenshot 2000×1294 px of a 1920 pt-wide screen,
≈1.042 px/pt). Thumbnails are still right.

Owner's log:
```
[12:01:21.477] Capture geometry at start: SCWindow.frame=(0,38 1920x1115) live bounds=(0,38 1920x1115) output=3840x2230
[12:01:21.669] Capture frame geometry: buffer=3840x2230 contentRect=(0,0 1920x1115) contentScale=1.000 scaleFactor=2.0 → window content in buffer=(0,0 3840x2230)
[12:01:21.670] Window frame (CGWindowList): (0,38 1920x1115)
[12:01:24.020] Capture frame geometry: buffer=3840x2230 contentRect=(0,0 1777x1115) contentScale=0.925 scaleFactor=2.0 → window content in buffer=(0,0 3554x2230)
[12:01:24.043] Window frame (CGWindowList): (0,38 1920x1205)
[12:01:24.099] Capture resized to follow the window: 3840x2230 → 3840x2410
[12:01:24.157] Capture frame geometry: buffer=3840x2410 contentRect=(0,0 1920x1205) contentScale=1.000 scaleFactor=2.0 → window content in buffer=(0,0 3840x2410)
[12:01:24.633] Capture frame geometry: buffer=3840x2410 contentRect=(0,0 1743x1205) contentScale=0.908 scaleFactor=2.0 → window content in buffer=(0,0 3487x2410)
```

**Reading (Cowork):**
- `contentRect` is in points of the output, `× scaleFactor` = buffer pixels (1920×1205 → 3840×2410). ✔
- In steady state `contentScale = 0.908` with `contentRect = 1743×1205`: ScreenCaptureKit is
  scaling a source of **1743/0.908 × 1205/0.908 ≈ 1920 × 1327 pt** into the buffer. So SCK's
  window is **~122 pt taller than CGWindowList's 1920×1205** (the game is full-screen; the
  extra part is most likely the hidden title-bar area above the visible screen).
- Model: SCK window = same left/bottom as the CG bounds, 122 pt taller, i.e. top at y ≈ −84.
  Mapping `box × (0,38 1920×1205)` instead of `box × (0,−84 1920×1327)` predicts the outline
  for "A polished brick of stone" at y ≈ 644–682 px — **observed 641–683 px**. x is unchanged
  (width 1920 in both), which is also what was observed. This explains round 1's result exactly.
- The round-1 resize targets the CG size (2410 px tall), so SCK keeps shrinking the 1327 pt
  window by 0.908 — also ~9 % less OCR resolution than intended.

**Round 2 (Claude Code decides the HOW; these are the observed facts to satisfy):**
1. Map boxes with the **captured window's** rect, not the CG bounds: size = `contentRect.size /
   contentScale` (points), placed on screen so its left/bottom match the CG bounds (confirm
   with the next log; if SCK exposes the window's real frame, prefer that).
2. Size the stream from that captured size (×2), so `contentScale` returns to 1.0 — and make
   sure this can't loop between two sizes.
3. Keep the sanity check from the interim review for the crop.
4. Log the captured-window rect used for mapping, next to the CG bounds.
5. Watch out: part of the captured window may be **off-screen** (y < 0). Outlines/overlay boxes
   there should be skipped or clamped to the visible screen.

**Cowork, 2026-09-24 — interim review of round 1 (`6730abe`, v1.11.30). Task stays IN_PROGRESS.**

Approach accepted: measure first, and the two likely causes (stream size frozen at start;
`SCStreamFrameInfo` ignored) are fixed behind one tested mapping. The resize path uses
`updateConfiguration` only, so no permission risk (rule 1), and a failed resize is logged, not fatal.

To address in round 2 (with the owner's log):
1. **The crop heuristic can make things worse silently.** `contentPixelRect` takes the
   *largest candidate that fits*. If `scaleFactor` is missing (→ 1) while `contentRect` is in
   points, the as-is candidate (e.g. 1470×956 in a 2940×1912 buffer) fits and wins, and every
   frame is cropped to the top-left quarter — OCR would lose ¾ of the screen. Only crop when the
   chosen rect is consistent with the window (aspect ratio within ~2 %, and size ≈ window × 2 or
   a plausible scaled-down fit); otherwise use the whole buffer and log it. Add a test for
   "contentRect in points, scaleFactor nil".
2. Once the log shows which units `contentRect` uses on this Mac, replace the candidate search
   with that one rule (keep the sanity check).
3. The round-1 arithmetic (≈ 0.878× in both axes + offset) points at a size mismatch between the
   buffer and the frame used for mapping; the start/resize lines in the log should confirm it.
   Record the confirmed cause under AC-1.

Owner: after `./build.sh`, open the stone cutter menu in full-screen Graveyard Keeper, start
translating (Panel mode, no regions), hover "A piece of stone", then run
`grep -E "Capture geometry|Capture frame geometry|Window frame|Capture resized" ~/Desktop/GameTranslator.log`
and send the output + a screenshot.

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → READY | Cowork | corrects T-0019 (AC-4 failed on owner's screenshot) |
| 2026-09-24 | READY → IN_PROGRESS | Claude Code | started |
| 2026-09-24 | (IN_PROGRESS) | Claude Code | round 1 done (capture follows window size, crop to content rect, diagnostics, AC-2 tests pass); waiting for the owner's geometry log for AC-1 |
| 2026-09-24 | — | Cowork | interim review of round 1; waiting for owner's geometry log |
| 2026-09-24 | — | Cowork | round 1 tested by owner: y still off; cause identified from log (SCK window 122 pt taller than CG bounds) |
