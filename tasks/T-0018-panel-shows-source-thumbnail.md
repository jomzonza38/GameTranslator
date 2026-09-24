# T-0018 — In full-screen mode, each panel entry shows where its text came from

| Field | Value |
|---|---|
| **Status** | REVIEW |
| **Type** | feature |
| **Priority** | P2 |
| **Version impact** | minor |
| **Milestone** | M5 — Know where each translation came from |
| **Depends on** | — |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-24 by Cowork |

## Objective
When no region is defined (the whole game window is read), the panel lists every
translation in one column with nothing that says where on screen it came from. In
games that show text in many places at once (Graveyard Keeper: dialog box, NPC
speech bubbles, item tooltips, craft menus, HUD), the player can't tell which
translation belongs to which text. Each panel entry must show a small picture of
the original text as it looks in the game, so the player can match it at a glance.

## Context
- `TranslationPanelData.update(from:)` builds `Entry(original, translated, regionColor, regionName)`.
  In full-screen mode `regionColor`/`regionName` are nil, so the row shows only the
  Thai text and the English original (`translationRow`).
- Region mode already identifies the source with a colour bar + region name. That
  works and stays as it is.
- The pipeline already has what is needed: `runPipeline(image:contentRect:)` holds the
  captured `CGImage`; each `DetectedText.boundingBox` is normalized (0…1)
  relative to that image (check the origin convention in `OCRService`); lines are
  already merged into blocks by `RegionLayout.mergeAdjacentLines`.
- Hint: crop once when a text is translated (new/changed), not on every frame —
  T-0016 made a static screen almost free; keep it that way. Keep thumbnails small
  (e.g. ~24 pt tall, width capped) and drop them when the entry disappears.
- Hint: `Entry.id` is a new `UUID()` on every update. If the thumbnail should survive
  updates of an unchanged text, key it by something stable (e.g. the source text).

## Requirements
1. In full-screen mode, every panel entry shows a thumbnail of the game pixels inside
   that entry's source text box, next to or above the Thai translation.
2. The thumbnail matches the text it belongs to (not a neighbour, not shifted) on
   Retina and non-Retina displays and on a secondary display.
3. When the text on screen changes, the thumbnail updates with the translation.
4. Region mode rows look and behave exactly as before.
5. A setting in the Panel/Display settings turns thumbnails on/off (Thai label,
   default on). Off = rows look as they do today.
6. A static screen must not cost noticeably more CPU than before (T-0016's result).

## Out of scope
- Overlay mode. Hover highlight (T-0019). Changing the order of panel entries.
- Numbered badges on screen, classifying text as dialog/tooltip/HUD (backlog).

## Constraints
- CLAUDE.md stability rules apply.
- Thai UI strings.
- No new capture or permission API calls; use frames already captured.

## Files / Modules
- `Sources/Services/PipelineCoordinator.swift` (crop when a text is translated)
- `Sources/Models/TranslatedRegion.swift`
- `Sources/Overlay/TranslationPanelController.swift` (`TranslationPanelData`, `translationRow`)
- `Sources/Models/AppSettings.swift`, `Sources/Views/SettingsWindow.swift` (toggle)
- `Tests/…`

## Acceptance Criteria
- **AC-1** [test] The crop rectangle for a normalized box maps to the right pixels
  (top-left origin, image scale), and is clamped inside the image for boxes at the edge.
- **AC-2** [test] The setting defaults to on and persists.
- **AC-3** [code] No crop or image work happens for texts that are unchanged since the
  last frame; region mode rows are unchanged.
- **AC-4** [manual] Steps: 1) Remove all regions, choose Panel mode. 2) Start
  translating Graveyard Keeper (or any game) with a dialog and a tooltip on screen.
  Expected: each panel entry shows a picture of its own English text; moving the mouse
  to a new tooltip adds an entry with that tooltip's picture.
- **AC-5** [manual] Steps: turn the setting off. Expected: rows look like before (no picture).
- **AC-6** [manual] Steps: with regions defined, Panel mode. Expected: rows unchanged
  (colour bar + region name, no picture).
- **AC-7** [manual] Steps: leave a static game screen with text for 1 minute while
  translating in full-screen Panel mode; check Activity Monitor. Expected: CPU about
  the same as v1.11.27 in the same situation.
- **AC-8** [build] Unit tests and Release build succeed.

## Testing Requirements
- Unit test for the crop rectangle maths (AC-1) and the setting (AC-2).
- Owner runs AC-4 … AC-7.

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

- **Where the picture comes from (Req 1, 2):** the same `CGImage` that the OCR read in
  this pipeline run, cut at the text's `DetectedText.boundingBox`. After line merging,
  that box is the merged block. `OCRService` produces normalized boxes with a
  **top-left** origin relative to the whole captured image (region crops are mapped
  back), and `CGImage.cropping(to:)` also uses top-left pixel coordinates. So the
  mapping is `box × image size`, with no flip. The captured image is always 2× the
  window size, independent of which display the game is on or its scale, so Retina,
  non-Retina and secondary displays all use the same maths.
- **New `SourceThumbnail`** (pure, in a new file `Sources/Services/SourceThumbnail.swift`,
  outside *Files / Modules*, because it serves the pipeline and is unit-tested):
  - `pixelRect(for:imageWidth:imageHeight:padding:)`: 4 px padding, `.integral`,
    clamped inside the image, nil when empty.
  - `scaledSize`: at most 560×48 px (≈ 280×24 pt shown at scale 2), never enlarged.
  - `make(from:box:)`: crops **and copies into a small bitmap**. `cropping(to:)` alone
    would keep the whole ~20 MB frame alive per thumbnail.
- **When pictures are cut (AC-3, Req 6):** `PipelineCoordinator.attachSourceThumbnails`
  runs after `resolveOverlaps`, **only** in Panel mode + full-screen (no regions) +
  setting on. It cuts a picture only for an on-screen text that is translated and
  **has no picture yet**. Unchanged texts reuse theirs; a changed text is a new key →
  new picture (Req 3). Pictures of texts that left the screen are dropped every run,
  and all are dropped on stop, in region/overlay mode or with the setting off. A static
  screen still skips whole pipeline runs (T-0016), so it costs nothing extra.
- **Carried to the panel:** `TranslatedRegion.sourceThumbnail` (+ `withSourceThumbnail`;
  the existing copy helpers keep it) → `TranslationPanelData.Entry.thumbnail` → shown
  above the Thai text in `translationRow`, max 24 pt tall, rounded, thin border. It is
  shown only for entries without a region colour and while the setting is on.
- **Region mode (Req 4):** no pictures are made (`captureRegions` not empty), and the
  row view shows a picture only when `regionColor == nil`, so region rows are exactly
  as before.
- **Setting (Req 5):** `AppSettings.showSourceThumbnails`, default **on**, persisted
  under `showSourceThumbnails`. The load rule is `AppSettings.loadShowSourceThumbnails(_:)`
  so it can be tested with a separate `UserDefaults` suite. The toggle sits in Settings →
  Display → *ตัวเลือกเพิ่มเติม*: "แสดงภาพข้อความต้นฉบับในแผงคำแปล", with an explanation line.
- **Static screen niceties:** switching Overlay → Panel, or toggling the setting,
  schedules one re-run (T-0015 mechanism), so pictures appear without waiting for the
  screen to change.

## Result

**Outcome:** PARTIAL — `[test]`/`[code]`/`[build]` criteria pass; AC-4 … AC-7 pending owner
**Version:** 1.11.27 → 1.11.28
**Commit:** `c47e4ce`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `SourceThumbnailTests`: box → pixels with top-left origin on a 2000×1000 (2×) image, padding, clamping at the edge, box outside → nil, size cap, and a real crop that lands on the black block (not the white background). |
| AC-2 | ✅ pass | `testThumbnailSettingDefaultsToOnAndPersists` (fresh `UserDefaults` suite: default on, off remembered). |
| AC-3 | ✅ pass | `attachSourceThumbnails`: `where sourceThumbnails[detected.text] == nil` — no crop for texts that already have a picture; guard returns early in region/overlay mode; row view unchanged when `regionColor != nil`. |
| AC-4…AC-7 | ⏳ pending owner | Steps below. |
| AC-8 | ✅ pass | `Executed 124 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 124 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                              | 1.11.28
 Sources/Services/SourceThumbnail.swift            | (new) crop maths + small copy
 Sources/Models/TranslatedRegion.swift             | sourceThumbnail
 Sources/Services/PipelineCoordinator.swift        | attachSourceThumbnails, cache, re-run on mode/setting change
 Sources/Overlay/TranslationPanelController.swift  | Entry.thumbnail, picture in translationRow
 Sources/Models/AppSettings.swift                  | showSourceThumbnails (default on)
 Sources/Views/SettingsWindow.swift                | Thai toggle
 Tests/SourceThumbnailTests.swift                  | (new, 7 tests)
```

### Manual checks for the owner
After `./build.sh`:
- **AC-4:** remove all regions, Panel mode, translate Graveyard Keeper (or any game)
  with a dialog and a tooltip visible → each entry shows a picture of its own English
  text; hovering a new tooltip in the game adds an entry with that tooltip's picture.
- **AC-5:** Settings → ตัวเลือกเพิ่มเติม → turn off "แสดงภาพข้อความต้นฉบับในแผงคำแปล" →
  rows look as before (no picture). Turn it back on → pictures return.
- **AC-6:** with regions defined, Panel mode → rows unchanged (colour bar + region
  name, no picture).
- **AC-7:** static game screen with text, full-screen Panel mode, 1 minute → CPU about
  the same as v1.11.27 (use the `top` command from T-0016).

### Proposed follow-ups
- none

---

## Review

**Cowork, 2026-09-24 — owner test on v1.11.29:** AC-4 ✅ from the owner's screenshot (stone
cutter menu: each entry's picture shows its own English text). AC-5…AC-7 still pending.

**Cowork, 2026-09-24 — code review passed; waiting for owner's AC-4…AC-7.**

| AC | Verdict | Note |
|---|---|---|
| AC-1 | ✅ | `SourceThumbnail.pixelRect`: box × image size, top-left origin (matches `OCRService` and `CGImage.cropping`), padding, `.integral`, clamped, nil when empty. Tests cover the edge and a real crop. |
| AC-2 | ✅ | `loadShowSourceThumbnails` → default on, persisted; tested with its own suite. |
| AC-3 | ✅ | Crop only `where sourceThumbnails[text] == nil` and the text is translated; stale keys dropped each run; guard clears everything in Overlay / region mode / setting off. Row view shows a picture only when `regionColor == nil`. |
| AC-4…AC-7 | ⏳ owner | — |
| AC-8 | ✅ | 124 tests (Claude Code's evidence; Cowork can't run Xcode here). |

- Good call copying the crop into a small bitmap: `cropping(to:)` alone would pin the ~20 MB frame per entry.
- `SourceThumbnail.swift` is outside *Files / Modules*; the reason is recorded. OK.
- Re-run on mode switch / toggle uses the T-0015 mechanism, so a static screen gets pictures without waiting. OK.
- **Note (not blocking):** pictures are keyed by source text only. If the same text is on screen twice
  (two "Buy" buttons, two "x2" labels), both entries show the picture of whichever was cut first. Both
  pictures look the same anyway, so the player loses little; T-0019's outline shows which one is where.
  → backlog, not a corrective task.

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → READY | Cowork | owner: can't tell where each full-screen translation came from (Graveyard Keeper) |
| 2026-09-24 | READY → IN_PROGRESS | Claude Code | started (owner: do T-0018 and T-0019, review after) |
| 2026-09-24 | IN_PROGRESS → REVIEW | Claude Code | test/code/build ACs pass; AC-4…AC-7 manual pending owner |
| 2026-09-24 | — | Cowork | code review passed; waiting for owner manual ACs |
