# T-0005 — OCR must never resume its continuation twice

| Field | Value |
|---|---|
| **Status** | REVIEW |
| **Type** | fix |
| **Priority** | P2 |
| **Version impact** | patch |
| **Milestone** | M1 — Stability |
| **Depends on** | — |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-23 by Cowork (code audit v1.11.11, finding 3) |

## Objective
Remove a possible crash in OCR: a Swift checked continuation resumed twice is a
fatal error, and the current code has two resume paths that can both run for a
single failed Vision request.

## Context
- `OCRService.recognizeText(in:imageSize:)` (`Sources/Services/OCRService.swift`)
  resumes the continuation inside the `VNRecognizeTextRequest` completion handler
  (success **and** error) and also in the `catch` of `handler.perform([request])`.
- If Vision reports the error through the completion handler *and* `perform` throws,
  the continuation is resumed twice → crash. Not reproduced; whether Vision does
  both is not confirmed. The fix is cheap, so do it regardless.
- Hint: one option is to drop the completion handler and read `request.results`
  after a synchronous `perform`; another is a resume-once guard. Claude Code decides.
- `cleanOCRText`, coordinate flipping and the crop mapping must behave the same.

## Requirements
1. For every request, the continuation is resumed exactly once (success, Vision
   error, or `perform` throwing).
2. OCR results (texts, bounding boxes, confidence filtering, cleaning) are unchanged.

## Out of scope
- OCR accuracy/performance tuning, `CIContext` reuse, thread-safety of settings
  properties (backlog).

## Constraints
- CLAUDE.md stability rules apply.

## Files / Modules
- `Sources/Services/OCRService.swift`
- `Tests/…` (OCR helpers)

## Acceptance Criteria
- **AC-1** [code] Only one code path can resume the continuation per request.
- **AC-2** [test] Existing OCR-related tests pass; add a test that runs OCR on a
  small generated image with known text (or on an empty image) and gets a result
  without crashing — if not feasible on CI, explain why.
- **AC-3** [manual] Steps: translate a game for 2 minutes in Fast and in Accurate
  OCR mode. Expected: translations appear as before, no crash.
- **AC-4** [build] Unit tests and Release build succeed.

## Testing Requirements
- See AC-2; owner runs AC-3.

## Definition of Done
- [ ] All acceptance criteria pass (`[manual]` ones confirmed by the owner)
- [ ] Unit tests added/updated as required; full suite passes
- [ ] Release build succeeds
- [ ] Version bumped per CLAUDE.md (patch)
- [ ] `git diff` contains only changes justified by this task
- [ ] Result section complete; Cowork review passed

---

## Questions

## Implementation Notes

- **Approach (first hint):** `VNRecognizeTextRequest` is now created **without a
  completion handler**. `VNImageRequestHandler.perform` is synchronous and reports
  failure by throwing, so the results are read from `request.results` after it
  returns. The continuation is resumed in exactly three mutually exclusive places:
  `self` gone (early return), `perform` succeeded (`do` branch), `perform` threw
  (`catch`). No path can reach two of them.
- **Results unchanged (Req 2):** the observation → `DetectedText` mapping was moved
  as-is into `private func detectedTexts(from:)`: same `topCandidates(1)`,
  confidence filter, trimming, minimum length (before and after `cleanOCRText`), and
  bottom-left → top-left flip. Request settings (level, languages, language
  correction, no auto-detect) unchanged. `recognizeText(cropTo:)` untouched.
  The old `request.results as? [...]` fallback to an empty list is now `?? []`.
- **Tests (AC-2):** `OCRServiceTests` runs real Vision OCR on images drawn in the test
  (no capture, no permission): "HELLO WORLD" is recognised with a top-left-origin box
  in the upper half; a blank image returns no text and no error; OCR cropped to the
  top half maps the box back to whole-image coordinates. Vision runs on-device, so
  this should work on the macos-15 CI runner too.
- **Test time:** the first run on a machine took ~74 s (Vision loads its model
  once); later runs: the 3 OCR tests take 0.25 s, the whole suite 0.43 s. CI starts
  clean each time, so expect roughly +1 min per CI run (timeout is 30 min).

## Result

**Outcome:** PARTIAL — all `[code]`/`[test]`/`[build]` criteria pass; AC-3 pending owner
**Version:** 1.11.14 → 1.11.15
**Commit:** not committed (waiting for owner)

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `OCRService.recognizeText(in:imageSize:)`: no completion handler; `continuation.resume` only at lines 39 (`self` nil → return), 61 (`do` after `perform`), 63 (`catch`) — mutually exclusive. |
| AC-2 | ✅ pass | Existing OCR tests (`RegionLayoutTests.testCleanOCRText`) pass; new `OCRServiceTests` (3 tests, real Vision on generated images) pass. |
| AC-3 | ⏳ pending owner | Steps below. |
| AC-4 | ✅ pass | `Executed 63 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 63 tests, with 0 failures (0 unexpected) in 0.428 (0.457) seconds
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                          |  2 +-
 Sources/Services/OCRService.swift             | 85 +++++++++++++--------------
 Tests/OCRServiceTests.swift                   | (new, 3 tests)
 tasks/BOARD.md, tasks/T-0005-…md              | (status + this report)
```

### Manual checks for the owner
**AC-3** — after `./build.sh`:
1. Settings → OCR accuracy **Fast**; translate a game for ~2 minutes.
2. Switch to **Accurate**; translate for another ~2 minutes.
Expected: translations appear as before in both modes (same text, positions), no crash.

### Proposed follow-ups
- none

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-23 | → READY | Cowork | created from code audit v1.11.11 |
| 2026-09-23 | READY → IN_PROGRESS | Claude Code | started |
| 2026-09-23 | IN_PROGRESS → REVIEW | Claude Code | code/test/build ACs pass; AC-3 manual pending owner |
