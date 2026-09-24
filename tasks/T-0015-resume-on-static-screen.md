# T-0015 — Resuming, switching provider and retrying must work on a static screen

| Field | Value |
|---|---|
| **Status** | READY |
| **Type** | fix |
| **Priority** | P2 |
| **Version impact** | patch |
| **Milestone** | M3 — Providers & settings hygiene |
| **Depends on** | — |
| **Corrects** | T-0012 |
| **Follow-up** | — |
| **Created** | 2026-09-24 by Cowork (owner test of T-0012) |

## Objective
When translation resumes after a fixed key, a provider switch, or a retry back-off, the
text already on screen must be translated **even if the screen isn't moving**. A dialog
box that waits for a click is the main use case, and today it stays untranslated until
something on screen changes.

## Context
- Failed criterion (T-0012 **AC-3** step 2): *"Enter the real key. Expected:
  translation resumes without restarting."* Owner's log 2026-09-24: `09:41:07 ▶︎
  Translation resumed (Claude Haiku)` → no `Translating…` line until the owner
  pressed start again at `09:41:20`.
- The pipeline runs only in `processFrame`, called from `StreamOutput` when
  ScreenCaptureKit delivers a frame with an image buffer. SCStream sends no new
  frames while the window's content is unchanged, so a static screen means no
  pipeline run.
- Same gap:
  - the 3 s `retryDelay` after a failed request (the retry needs a later frame);
  - T-0011's re-translation after a provider or language change (it happens at the
    start of the next frame);
  - glossary changes (`applyGlossaryChangesIfNeeded`), probably.
- T-0014's generation check must stay as it is.
- Hint (the HOW is Claude Code's call): keep the latest frame and re-run the pipeline
  on it when something makes on-screen text translatable again — resume, scope
  change, glossary change, a retry becoming due. A low-rate idle tick is another
  option. It must respect `isProcessing` and stop/start generations (T-0003), and
  must not create a timer storm or extra OCR work every frame.

## Requirements
1. After `updateProvider()` clears a pause, or after a provider/language/glossary
   change while running, text already on screen is translated within about 2 s,
   without any change on screen.
2. A text whose request failed with a non-pausing error is retried after the normal
   back-off even if the screen doesn't change (and not more often than that).
3. While paused (T-0012) and the screen is static, no requests are made and CPU stays
   near idle — no busy loop re-running OCR on an unchanged frame.
4. Stop / start / game closed (T-0002, T-0003) behave as before; no pipeline run after stop.

## Out of scope
- Changing FPS or the capture configuration; OCR performance.

## Constraints
- CLAUDE.md stability rules apply (especially: no crash/freeze after reopen or a game restart).

## Files / Modules
- `Sources/Services/PipelineCoordinator.swift`, maybe `Sources/Services/ScreenCaptureService.swift`
- `Tests/…`

## Acceptance Criteria
- **AC-1** [code] Resume (`updateProvider()` clearing a pause), scope change, glossary change and a due retry each lead to one pipeline run on the latest frame when no new frame arrives. The runs are guarded by `isProcessing` and by the session/start generation.
- **AC-2** [code] Nothing re-runs the pipeline repeatedly on an unchanged frame while paused or when there's nothing to translate. Say how in the notes.
- **AC-3** [manual] Steps (static window, e.g. TextEdit with a few English words, not touched during the test):
  1) Claude Haiku, key `sk-test` → start → wait 30 s. Expected: one 401 in the log, and the menu shows `⚠️ หยุดแปลชั่วคราว: Claude Haiku ไม่รับ API Key — …`.
  2) Without touching the window, enter the real key and close Settings. Expected: within about 2 s the words are translated, **without pressing start again**.
  3) Still without touching the window, switch to Google Free. Expected: Google's translation appears within about 2 s.
- **AC-4** [manual] Activity Monitor: with a static window and no text to translate (or while paused), GameTranslator CPU is about the same as before this task.
- **AC-5** [build] Unit tests and Release build succeed.

## Testing Requirements
- Unit test the "should re-run on last frame" decision if it can be extracted. Owner runs AC-3 and AC-4.

## Definition of Done
- [ ] All acceptance criteria pass (`[manual]` ones confirmed by the owner)
- [ ] Unit tests added/updated as required; full suite passes
- [ ] Release build succeeds
- [ ] Version bumped per CLAUDE.md
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
| 2026-09-24 | → READY | Cowork | corrective for T-0012 AC-3 step 2 (owner test 09:41) |
