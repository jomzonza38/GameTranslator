<!--
Copy to tasks/T-NNNN-short-slug.md. Rules: WORKFLOW.md.
Cowork fills everything down to "Definition of Done" (and Review later).
Claude Code fills Questions (if BLOCKED), Implementation Notes and Result.
Delete these HTML comments and unused example lines when filling in.
-->

# T-NNNN — <Title: short, outcome-focused>

| Field | Value |
|---|---|
| **Status** | PLANNED |
| **Type** | fix / feature / refactor / test / docs / investigation |
| **Priority** | P1 (urgent) / P2 (normal) / P3 (nice to have) |
| **Version impact** | patch / minor / none <!-- per CLAUDE.md semver; Claude Code confirms --> |
| **Milestone** | <!-- from ROADMAP.md, or "—" --> |
| **Depends on** | — <!-- T-xxxx that must be DONE first --> |
| **Corrects** | — <!-- only for corrective tasks: T-xxxx whose review failed --> |
| **Follow-up** | — <!-- set by Cowork if this task ends REVIEW_FAILED --> |
| **Created** | YYYY-MM-DD by Cowork |

## Objective
<!-- WHAT should be true when this is done, and WHY it matters to the user. 2–4 sentences. -->

## Context
<!-- What the implementer needs to know without asking: current behaviour, how to
reproduce, relevant log lines, related tasks, user reports. Technical hints are
allowed but mark them as hints ("Hint: …") — the HOW is Claude Code's call. -->

## Requirements
<!-- Numbered, testable statements of required behaviour. -->
1. …

## Out of scope
<!-- What must NOT be changed or added in this task. -->
- …

## Constraints
<!-- Always applies: CLAUDE.md stability rules (no repeated Screen Recording prompt,
no crash/freeze after reopen/game restart, build never broken), Thai UI strings,
API keys only in Keychain. Add task-specific constraints below. -->
- CLAUDE.md stability rules apply.
- …

## Files / Modules
<!-- Expected area of change (from CLAUDE.md → Architecture). Claude Code may touch
other files only with a reason recorded in Implementation Notes. -->
- `Sources/…`
- `Tests/…`

## Acceptance Criteria
<!-- Each must be checkable. Tags: [test] unit test, [build] tests + Release build,
[code] visible in the diff, [manual] owner runs the real app (write exact steps). -->
- **AC-1** [test] …
- **AC-2** [code] …
- **AC-3** [manual] Steps: 1) … 2) … Expected: …
- **AC-4** [build] Unit tests and Release build succeed.

## Testing Requirements
<!-- Which unit tests must be added/updated; which manual checks are needed. -->
- …

## Definition of Done
- [ ] All acceptance criteria pass (`[manual]` ones confirmed by the owner)
- [ ] Unit tests added/updated as required; full suite passes
- [ ] Release build succeeds
- [ ] Version bumped per CLAUDE.md (or "none" justified)
- [ ] `git diff` contains only changes justified by this task
- [ ] Result section complete; Cowork review passed

---

## Questions
<!-- Claude Code: when BLOCKED, write each question with a concrete proposal.
Cowork: answer below each one, then amend the spec with a dated note. -->

## Implementation Notes
<!-- Claude Code: approach chosen and why, alternatives rejected, files touched
outside "Files / Modules" and why, risks, anything the reviewer should look at. -->

## Result
<!-- Claude Code fills this before setting REVIEW. -->

**Outcome:** PASS / PARTIAL (manual checks pending) / FAIL
**Version:** x.y.z → x.y.z
**Commit:** not committed (waiting for owner)

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass / ❌ fail / ⏳ pending owner | test name, command output, diff reference, or manual steps |

### Build & test
```
<paste the relevant lines: "Executed N tests, with 0 failures", "** TEST SUCCEEDED **", "** BUILD SUCCEEDED **">
```

### Changed files
```
<git diff --stat>
```

### Manual checks for the owner
<!-- Exact steps for every [manual] criterion, or "none". -->

### Proposed follow-ups
<!-- Out-of-scope problems found while working — not fixed here. -->

---

## Review
<!-- Cowork: per-AC verdict, decision (DONE / REVIEW_FAILED), and link to the
corrective task if any. -->

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| YYYY-MM-DD | → PLANNED | Cowork | created |
