# T-0015 — Resuming, switching provider and retrying must work on a static screen

| Field | Value |
|---|---|
| **Status** | REVIEW |
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

- **Approach (first hint): keep the latest frame and re-run the pipeline on it when
  work is waiting.** `PipelineCoordinator.lastFrame` is set in `processFrame`. A
  re-run calls the same `processFrame(lastFrame)`, so it gets exactly the same
  guards as a real frame:
  - `isRunning`
  - `isProcessing` — queued as `pendingFrame` behind a run in progress
  - the pipeline task that `stop()` cancels
- **Scheduling:** `scheduleRerun(after:)` keeps **one** `rerunTask` and cancels the
  previous one. The task remembers `sessions.current` (the T-0003 generation) and
  only runs if that session is still current and running. `tearDown()` cancels it and
  drops `lastFrame`, so nothing runs after a stop or game close (Req 4).
- **When to re-run** — pure `StaticScreenRerun.delay(...)`, called once at the end of
  every successful pipeline run (`planRerun`):
  - an on-screen text **waiting to become stable** (after a reset: resume, provider,
    language or glossary change) → **0.5 s**. On an unchanged frame one more run makes
    it stable, and that run translates it.
  - a text **in retry back-off** → when `failedAt + 3 s` is reached, never earlier
    (Req 2).
  - a **glossary edit settling** → when it will be applied
    (`TranslationContextBuilder.pendingGlossaryAppliesAt`, a new read-only accessor —
    small change in a helper outside *Files / Modules*).
  - **paused, or nothing waiting → no re-run** (idle).
  - Floor: 0.1 s.
- **Events that start a re-run (0.2 s):**
  - `updateProvider()` — resume after a refused key, key saved, provider picked
  - `settings.$sourceLanguage` changes
  - `settings.$gameProfiles` changes (glossary edits)

  The re-run then applies the change (T-0011 scope reset, glossary settle) and the
  plan above takes over.
- **Timing on a static screen:**
  - resume after a refused key: 0.2 s → translated in that run (the texts were
    already stable).
  - provider or language switch: 0.2 s reset run + 0.5 s stability run → **≈ 0.7 s +
    request time**.
  - glossary edit: 1.5 s settle (existing design) + 0.5 s → ≈ 2.2 s.
- **AC-2 — why there is no busy loop:** a re-run is scheduled only while a text can
  still make progress: waiting for stability (settles after one run on the same
  frame), a back-off that ends, or a glossary about to apply. When everything visible
  is translated, when paused, or when no text is on screen, the plan returns `nil` and
  nothing runs until the next real frame or event. While frames keep arriving, every
  run cancels and replaces the scheduled re-run, so it adds no extra OCR on a moving
  screen.
- **Unchanged:** T-0014's generation check, the T-0012 pause logic, capture settings
  and FPS.

## Result

**Outcome:** PARTIAL — `[code]`/`[build]` criteria pass; AC-3 and AC-4 pending owner
**Version:** 1.11.24 → 1.11.25
**Commit:** not committed (waiting for owner)

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | Resume/key/provider → `updateProvider()` → `scheduleRerun`; language/glossary → Combine sinks → `scheduleRerun`; due retries, stability and glossary settle → `planRerun` → `StaticScreenRerun.delay`. Re-runs go through `processFrame(lastFrame)` (isRunning, isProcessing/pendingFrame) and check `sessions.isCurrent(session)`. |
| AC-2 | ✅ pass | `StaticScreenRerun.delay` returns nil when paused or nothing is waiting (`StaticScreenRerunTests.testPausedWithUntranslatedTextStaysIdle`, `testNothingWaitingStaysIdle`); one `rerunTask` at a time, floor 0.1 s. See notes. |
| AC-3 | ⏳ pending owner | Steps below. |
| AC-4 | ⏳ pending owner | Steps below. |
| AC-5 | ✅ pass | `Executed 103 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

Also `StaticScreenRerunTests` (7 tests): unstable → 0.5 s, retry at back-off end
(not earlier), soonest wins, glossary settle even while paused, minimum delay.

### Build & test
```
Executed 103 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                              | 1.11.25
 Sources/Services/PipelineCoordinator.swift        | lastFrame, rerunTask, scheduleRerun, planRerun, StaticScreenRerun, event sinks
 Sources/Services/TranslationContextBuilder.swift  | pendingGlossaryAppliesAt (read-only)
 Tests/StaticScreenRerunTests.swift                | (new, 7 tests)
 tasks/BOARD.md, tasks/T-0015-…md                  | (status + this report)
```

### Manual checks for the owner
After `./build.sh`, with a static window (e.g. TextEdit with a few English words) that
you don't touch during the test:

**AC-3**
1. Claude Haiku, key `sk-test` → start → wait 30 s. Expected: one `HTTP 401` +
   `⏸ Translation paused…` in the log; menu shows `⚠️ หยุดแปลชั่วคราว: Claude Haiku ไม่รับ API Key — …`.
2. Enter the real key, close Settings. Expected: `▶︎ Translation resumed` then within
   ~1 s a `Translating…` line and the words translated — **without pressing start**.
3. Switch to Google Free. Expected: `Translation provider/language changed …` then
   Google's translation within ~1–2 s.

**AC-4** — Activity Monitor → GameTranslator CPU, with the static window: (a) all text
translated, (b) paused with `sk-test`. Expected: about the same as before this task
(no steady extra load).

### Proposed follow-ups
- none

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → READY | Cowork | corrective for T-0012 AC-3 step 2 (owner test 09:41) |
| 2026-09-24 | READY → IN_PROGRESS | Claude Code | started |
| 2026-09-24 | IN_PROGRESS → REVIEW | Claude Code | code/build ACs pass; AC-3, AC-4 manual pending owner |
