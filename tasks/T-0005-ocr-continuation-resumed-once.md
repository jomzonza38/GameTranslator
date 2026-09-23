# T-0005 — OCR must never resume its continuation twice

| Field | Value |
|---|---|
| **Status** | READY |
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

## Result

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-23 | → READY | Cowork | created from code audit v1.11.11 |
