# T-0018 — In full-screen mode, each panel entry shows where its text came from

| Field | Value |
|---|---|
| **Status** | READY |
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

## Result

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → READY | Cowork | owner: can't tell where each full-screen translation came from (Graveyard Keeper) |
