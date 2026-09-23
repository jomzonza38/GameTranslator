# T-0007 — Cancelling region selection must bring the overlay back

| Field | Value |
|---|---|
| **Status** | REVIEW |
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

- **RegionSelectorWindow:** `show(over:color:onCancel:completion:)` gets an optional
  `onCancel` closure (default `nil`, so the call shape stays compatible). Esc still
  dismisses the selector first (cursor popped, window ordered out), then calls
  `onCancel`. The completion path is untouched.
- **PipelineCoordinator.addCaptureRegion:** passes `onCancel`, which calls the new
  `showOverlayAfterRegionSelection(over:)`. The success path now calls the same helper;
  the helper holds the exact condition and call that were inline before
  (`displayMode == .overlay && isRunning` → `overlayController.show(over: windowFrame)`),
  so success behaviour is unchanged (Req 2).
- **Why the translations come back immediately:** `hideTemporarily()` only orders the
  overlay window out and keeps its text boxes; `show(over:)` orders it front again,
  and the next frame's `updateRegions` continues as normal (Req 1).
- **Panel mode (Req 3):** the helper does nothing; the panel was never hidden.
- **Stopped while the selector was open (Req 4):** `isRunning` is false → no overlay.
  (If a *new* session was started meanwhile, its `start()` has already shown the
  overlay, so showing it again is harmless.)
- No region is added on cancel: only the completion handler calls `settings.addRegion`.

## Result

**Outcome:** PARTIAL — all `[code]`/`[build]` criteria pass; AC-2 and AC-3 pending owner
**Version:** 1.11.16 → 1.11.17
**Commit:** not committed (waiting for owner)

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `RegionSelectorView.onCancel` → `dismiss()` + `onCancel?()`; coordinator's `onCancel` → `showOverlayAfterRegionSelection`, which shows the overlay only if `settings.displayMode == .overlay && isRunning`. |
| AC-2 | ⏳ pending owner | Steps below. |
| AC-3 | ⏳ pending owner | Steps below. |
| AC-4 | ✅ pass | `Executed 63 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 63 tests, with 0 failures (0 unexpected) in 0.347 (0.384) seconds
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                        |  2 +-
 Sources/Overlay/RegionSelectorWindow.swift  |  9 ++++++++-
 Sources/Services/PipelineCoordinator.swift  | 18 +++++++++++++-----
 tasks/BOARD.md, tasks/T-0007-…md            | (status + this report)
```

### Manual checks for the owner
After `./build.sh`:

**AC-2 (Overlay):** translate a game in Overlay mode → menu → "➕ เพิ่มพื้นที่แปล..." →
press Esc. Expected: the translations reappear at once (or within a second); the
region count in the menu is unchanged. Then add a region normally (drag) → overlay
comes back and the region is added, as before.

**AC-3 (Panel):** same steps in Panel mode. Expected: the panel stays as it was; no
overlay appears.

**Optional (Req 4):** open the region selector, press ⌃⌥T to stop, then Esc.
Expected: no overlay appears.

### Proposed follow-ups
- none

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-23 | → READY | Cowork | created from code audit v1.11.11 |
| 2026-09-23 | READY → IN_PROGRESS | Claude Code | started |
| 2026-09-23 | IN_PROGRESS → REVIEW | Claude Code | code/build ACs pass; AC-2, AC-3 manual pending owner |
