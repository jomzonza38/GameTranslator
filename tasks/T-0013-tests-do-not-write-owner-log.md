# T-0013 — Unit tests must not write to the owner's GameTranslator.log

| Field | Value |
|---|---|
| **Status** | READY |
| **Type** | test |
| **Priority** | P3 |
| **Version impact** | none (test/logging only — patch if app code changes) |
| **Milestone** | M3 — Providers & settings hygiene |
| **Depends on** | — |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-24 by Cowork (code audit v1.11.11 backlog + owner testing) |

## Objective
Running the unit tests must not add lines to `~/Desktop/GameTranslator.log`, which the
owner and Cowork use to check real app behaviour.

## Context
- The test bundle runs inside the app (`TEST_HOST`). `AppDelegate` skips setup under
  XCTest, but `GameLog.log` has a default file URL, so any code under test that logs
  (providers, OCR, pipeline helpers) appends to the Desktop log.
- Seen 2026-09-23 23:49–23:52: "Batch request failed (HTTP 500)…" lines from
  `BatchFallbackTests` in the owner's log, which looked like a real app error.

## Requirements
1. While running under XCTest, `GameLog` does not write to `~/Desktop/GameTranslator.log`
   (console output is fine).
2. The app's normal logging is unchanged.

## Out of scope
- Moving the log out of the Desktop, log rotation, thread-safety of `GameLog`.

## Constraints
- CLAUDE.md stability rules apply.

## Files / Modules
- `Sources/Services/GameLog.swift`, `Sources/App/AppDelegate.swift` if needed

## Acceptance Criteria
- **AC-1** [code] Under XCTest `GameLog` writes no file (or writes to a temp location).
- **AC-2** [manual] Steps: note the last line of `~/Desktop/GameTranslator.log`, run the unit tests. Expected: the file is unchanged.
- **AC-3** [build] Unit tests and Release build succeed.

## Testing Requirements
- Owner (or Claude Code, if it can read the file) checks AC-2.

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
| 2026-09-24 | → READY | Cowork | created for M3 |
