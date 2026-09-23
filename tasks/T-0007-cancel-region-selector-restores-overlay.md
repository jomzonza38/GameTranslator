# T-0007 — Cancelling region selection must bring the overlay back

| Field | Value |
|---|---|
| **Status** | READY |
| **Type** | fix |
| **Priority** | P2 |
| **Version impact** | patch |
| **Milestone** | M2 — Reliability & UX |
| **Depends on** | — |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-23 by Cowork (code audit v1.11.11, finding 6) |

## Objective
In Overlay mode, pressing Esc while adding a translation region must return to
normal translation with the overlay visible. Today the overlay stays hidden until
the user stops and restarts.

## Context
- `PipelineCoordinator.addCaptureRegion` calls `overlayController.hideTemporarily()`
  and re-shows the overlay only in the selection completion handler.
- `RegionSelectorWindow`'s `onCancel` (Esc) only dismisses the selector; the
  completion is not called, so the overlay is never re-shown.
- `OverlayWindowController.updateRegions` only sets the frame; it does not order the
  window front, so later frames don't bring it back either.

## Requirements
1. After Esc in the region selector (Overlay mode, running), the overlay is visible
   again and keeps updating; no region is added.
2. After a successful selection, behaviour is unchanged.
3. In Panel mode, cancel changes nothing visible (panel stays).
4. If translation was stopped while the selector was open, cancel must not show the overlay.

## Out of scope
- Region selector look, minimum size, multi-monitor coordinates (T-0009).

## Constraints
- CLAUDE.md stability rules apply.

## Files / Modules
- `Sources/Services/PipelineCoordinator.swift`
- `Sources/Overlay/RegionSelectorWindow.swift`

## Acceptance Criteria
- **AC-1** [code] The cancel path restores the overlay when running in Overlay mode,
  and does nothing when stopped or in Panel mode.
- **AC-2** [manual] Steps: 1) translate a game in Overlay mode, 2) menu →
  "➕ เพิ่มพื้นที่แปล...", 3) press Esc. Expected: overlay translations reappear on
  the next text change / within a second; region count unchanged.
- **AC-3** [manual] Steps: repeat in Panel mode. Expected: panel unaffected.
- **AC-4** [build] Unit tests and Release build succeed.

## Testing Requirements
- Owner runs AC-2 and AC-3.

## Definition of Done
- [ ] All acceptance criteria pass (`[manual]` ones confirmed by the owner)
- [ ] Full test suite passes; Release build succeeds
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
