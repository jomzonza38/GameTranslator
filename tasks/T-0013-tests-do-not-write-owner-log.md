# T-0013 — Unit tests must not write to the owner's GameTranslator.log

| Field | Value |
|---|---|
| **Status** | REVIEW |
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

- `GameLog` gets `isRunningUnitTests`, the **same check `AppDelegate` already uses** to
  skip setup under tests: an `XCTest*` environment variable or `XCTestCase` loaded.
  When true:
  - the default `logFileURL` is `nil`, so `log()` writes no file;
  - `setup()` returns early (it isn't called under tests anyway, but it would also
    clear the owner's log).
  `NSLog` console output is unchanged, so lines still show in the Xcode/xcodebuild
  output (Req 1).
- In the normal app, `XCTestCase` isn't loaded and no `XCTest*` variable is set, so
  logging is exactly as before (Req 2).
- **Version:** patch, because app code (`GameLog.swift`) changed — as the task's
  version note says.

## Result

**Outcome:** PASS — AC-1 and AC-3 pass; AC-2 checked by Claude Code (owner may re-check)
**Version:** 1.11.22 → 1.11.23
**Commit:** not committed (owner asked for T-0010…T-0013 first, review after)

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `GameLog.logFileURL` is `nil` and `setup()` returns early when `isRunningUnitTests`; `log()` only writes when `logFileURL` is set. |
| AC-2 | ✅ pass (checked by Claude Code) | `~/Desktop/GameTranslator.log` before the test run: 163697 bytes, sha `7959b08c6e24`. After the full suite (92 tests): same size, same sha, same last line. Before this fix, today's test runs had added lines such as `Batch request failed (แปลไม่สำเร็จ: HTTP 500), using parallel` (09:14). |
| AC-3 | ✅ pass | `Executed 92 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 92 tests, with 0 failures (0 unexpected) in 0.528 (0.574) seconds
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
log file: size 163697 → 163697, sha 7959b08c6e24 → 7959b08c6e24
```

### Changed files (this task only, on top of T-0012)
```
 Resources/Info.plist            | 1.11.23
 Sources/Services/GameLog.swift  | no file writes under XCTest
```

### Manual checks for the owner
Optional re-check of AC-2: note the last line of `~/Desktop/GameTranslator.log`, run
the unit tests, and confirm the file is unchanged.

### Proposed follow-ups
- The log still contains today's test lines from 09:14 and earlier (the log is cleared
  at the next app launch).

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → READY | Cowork | created for M3 |
| 2026-09-24 | READY → IN_PROGRESS | Claude Code | started (stacked on T-0010…T-0012, uncommitted) |
| 2026-09-24 | IN_PROGRESS → REVIEW | Claude Code | all ACs pass (AC-2 checked by Claude Code) |
