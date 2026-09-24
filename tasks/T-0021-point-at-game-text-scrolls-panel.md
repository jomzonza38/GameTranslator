# T-0021 — Pointing at a text in the game brings its translation into view in the panel

| Field | Value |
|---|---|
| **Status** | DONE |
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

- **Started while T-0020 is in REVIEW** on the owner's instruction. It relies on
  T-0020's source rects: until those are confirmed on the owner's screen, the hit test
  is only as right as the outline.
- **Mouse position without permission (Req 5, AC-4):** `TranslationPanelController`
  runs a 0.1 s `Timer` that reads `NSEvent.mouseLocation`, a plain position query.
  There is **no** event tap, no global event monitor, no `AXIsProcessTrusted`, and no
  IOHID/Input Monitoring (grep of `Sources/` for those APIs: none). The game keeps
  receiving every click, hover and key, because nothing is intercepted.
- **When it runs (Req 8):** the timer exists only while the panel is shown — the panel
  is shown only while translating in Panel mode, and `hide()` (stop, game closed,
  Overlay mode, panel closed) invalidates it. Each tick returns at once when the setting
  is off, the panel is collapsed or has no entries. The per-tick work is a point
  conversion and a hit test over the panel entries (≤ a few dozen rects), which is
  negligible next to T-0016's per-frame fingerprint.
- **Hit test (Req 4, AC-1):** `GamePointer.entryID(at:in:)` (pure). The mouse is
  converted to CG coordinates with the primary display (`ScreenCoordinates.cgPoint`,
  matching T-0009), then the entry whose `sourceRect` contains it is found. With
  overlapping rects, the **smallest** one wins; the same text in two places has two
  entries (`#0/#1`), and the one under the mouse wins.
- **Rest delay (Req 1, 2, AC-2):** `PointerRestTracker` (pure). A text is selected only
  after the mouse stays over it, **within 6 pt**, for 0.4 s; leaving clears the mark
  after the same delay. Moving (even along one long text) restarts the wait, so a sweep
  across the menu never selects anything and the panel doesn't jump.
- **Panel (Req 1, 3):** `TranslationPanelData.pointedID` (cleared when its text leaves the
  screen, and on `clear()`). The row gets the same brighter background as a T-0019 hover.
  A `ScrollViewReader` scrolls the entry to the centre (0.2 s animation) only when a new
  entry is selected, never on deselect, so the list doesn't jump back. When the mouse is
  over the panel window, samples are ignored and the panel's own hover (T-0019) wins.
- **Setting (Req 6, AC-3):** `AppSettings.panelFollowsGamePointer`, default on, key
  `panelFollowsGamePointer`, load rule testable. Toggle in Settings → ตัวเลือกเพิ่มเติม:
  "เลื่อนแผงคำแปลไปที่ข้อความที่ชี้ในเกม" with an explanation line.
- **Region mode (Req 7):** entries carry the same `sourceRect` in both modes; nothing
  mode-specific.
- New file `Sources/Overlay/GamePointer.swift` (pure helpers, outside *Files / Modules*,
  like the suggested "small new helper").

## Result

**Outcome:** PARTIAL — `[test]`/`[code]`/`[build]` criteria pass; AC-5 … AC-8 pending owner (after T-0020 is DONE)
**Version:** 1.11.31 → 1.11.32
**Commit:** `6dbbafa`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `GamePointerTests`: inside, outside, overlapping → smallest, duplicate text → the copy under the mouse; AppKit → CG point. |
| AC-2 | ✅ pass | `testMovingEveryTickNeverSelects` (20 pt steps along one text), `testSweepingAcrossTextsNeverSelects`, `testRestingForTheDelaySelects` (with jitter), `testLeavingClearsAfterTheDelayNotAtOnce`, `testMovingToAnotherTextSwitchesAfterTheDelay`; `PanelPointedEntryTests` (mark cleared when the text is gone / on stop). |
| AC-3 | ✅ pass | `testSettingDefaultsToOnAndPersists`. |
| AC-4 | ✅ pass | Only `NSEvent.mouseLocation` + a `Timer`; no AX / event tap / IOHID / global monitor in `Sources/`; timer invalidated in `hide()`; early return when collapsed / setting off. |
| AC-5…AC-8 | ⏳ pending owner | Steps below. |
| AC-9 | ✅ pass | `Executed 158 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 158 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files (this task only, on top of T-0020 round 2)
```
 Resources/Info.plist                              | 1.11.32
 Sources/Overlay/GamePointer.swift                 | (new) hit test + rest tracker
 Sources/Overlay/ScreenCoordinates.swift           | cgPoint(fromAppKit:)
 Sources/Overlay/TranslationPanelController.swift  | pointedID, ScrollViewReader, pointer timer
 Sources/Models/AppSettings.swift                  | panelFollowsGamePointer
 Sources/Views/SettingsWindow.swift                | Thai toggle
 Tests/GamePointerTests.swift                      | (new, 13 tests)
```

### Manual checks for the owner
After `./build.sh` (and once T-0020's outline is confirmed on the text):
- **AC-5:** full-screen Graveyard Keeper, stone cutter menu, Panel mode, panel short
  enough to scroll → rest the mouse on "A carved piece of stone" → within ~0.5 s the
  panel scrolls to its entry and marks it; the game's own tooltip still appears.
- **AC-6:** sweep the mouse quickly across the menu → the panel doesn't jump; only
  where the mouse stops gets marked.
- **AC-7:** turn off "เลื่อนแผงคำแปลไปที่ข้อความที่ชี้ในเกม" → pointing does nothing.
- **AC-8:** with a text marked, press ⌃⌥T; separately quit the game → mark cleared, no
  crash or freeze.

### Proposed follow-ups
- none

---

## Review

**Cowork, 2026-09-24 — DONE.** Owner confirmed AC-6 (no jumping on a fast sweep), AC-7 (setting off)
and AC-8 (stop / quit while marked). Fix the `ScreenCoordinates.swift` doc-comment nit in the commit.
Commit: pending.

**Cowork, 2026-09-24 — code review passed; owner's quick test OK.**

| AC | Verdict | Note |
|---|---|---|
| AC-1 | ✅ | `GamePointer.entryID`: containment, smallest rect wins, duplicate text → the copy under the mouse. Tested. |
| AC-2 | ✅ | `PointerRestTracker`: moving / sweeping never selects, resting 0.4 s selects, leaving clears after the delay, switching waits too. Tested. |
| AC-3 | ✅ | Default on, persisted; tested. |
| AC-4 | ✅ | Only `NSEvent.mouseLocation` polled by a 0.1 s main-run-loop timer; no event tap, no AX / Input Monitoring API. The timer starts in `show()` and stops in `hide()` (stop, game closed, Overlay mode); samples are ignored when the setting is off, the panel is collapsed or empty, or the mouse is over the panel (T-0019 wins). |
| AC-5 | ✅ owner | Owner, 2026-09-24: works as requested in a quick test. |
| AC-6…AC-8 | ⏳ owner | Fast sweep doesn't make the panel jump; setting off; stop / quit the game while an entry is marked. |
| AC-9 | ✅ | — |

- `pointedID` is validated against the current entries and cleared when its text leaves; `scrollTo`
  fires only when the pointed entry changes, so the per-frame refresh doesn't fight the user's own
  scrolling.
- **Nit (fix before commit):** in `ScreenCoordinates.swift` the new `cgPoint(fromAppKit:)` was
  inserted between `appKitRect(fromCG:primaryDisplayHeight:)` and its doc comment, so the comment
  "CG rect → AppKit rect…" now sits on top of `cgPoint`, followed by `cgPoint`'s own comment.

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → READY | Cowork | owner: pointing at the game should bring its message into view |
| 2026-09-24 | READY → IN_PROGRESS | Claude Code | started on the owner's instruction ("do all") while T-0020 is in REVIEW; stacked, uncommitted |
| 2026-09-24 | IN_PROGRESS → REVIEW | Claude Code | test/code/build ACs pass; AC-5…AC-8 manual pending owner (after T-0020) |
| 2026-09-24 | — | Cowork | code review passed; owner quick test OK; remaining manual ACs pending |
| 2026-09-24 | REVIEW → DONE | Cowork | owner confirmed AC-6…AC-8 |
