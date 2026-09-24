# WORKFLOW.md — Cowork × Claude Code

How work is planned, built and reviewed in GameTranslator. **Both Cowork and
Claude Code read this file before working on a task.** Claude Code's own
rules (build, git, stability, architecture) are in `CLAUDE.md`.

> **สรุปภาษาไทย** — Cowork (PM/Architect) กำหนด *อะไร* และ *ทำไม* โดยเขียน Task
> ใน `tasks/` แล้วอนุมัติเป็น READY → Claude Code (Developer) หยิบ Task ที่ READY
> มาทำ (*อย่างไร*) build + test + ตรวจ `git diff` แล้วเขียนผลลงในไฟล์ Task และตั้งเป็น
> REVIEW → Cowork ตรวจเทียบ Acceptance Criteria แล้วตั้ง DONE หรือสร้าง Corrective
> Task ใหม่ (ไม่แก้ Task เดิม) → เจ้าของโปรเจกต์เป็นคนสั่ง commit / push เท่านั้น
> ทุกงานทำและ commit บน branch **`develop`** ส่วน **`main`** เก็บเฉพาะงานที่รีวิวแล้ว
> และจะอัปเดตเมื่อเจ้าของสั่ง merge `develop` → `main` เท่านั้น (ปกติคือจบ milestone)

## 1. Roles

| | Cowork | Claude Code | Owner (Jom) |
|---|---|---|---|
| Decides | **WHAT** and **WHY**: goals, scope, priority, acceptance criteria | **HOW**: design inside the task's scope, code, tests | Final say on everything; approves commits/pushes |
| Writes | `ROADMAP.md`, task specs in `tasks/`, `tasks/BOARD.md`, Review sections | Source code, tests, `Resources/Info.plist` version, Implementation Notes + Result sections, `CLAUDE.md` technical facts | Anything |
| Never | Edits `Sources/`, `Tests/`, `project.yml`, `build.sh`, `.github/` in the normal flow | Changes a task's requirements, scope or acceptance criteria; marks a task DONE; commits/pushes unasked | — |

## 2. Files

```
WORKFLOW.md            this file — shared rules (both)
CLAUDE.md              Claude Code's rules + project facts (auto-loaded by Claude Code)
ROADMAP.md             goals, milestones, unplanned backlog (Cowork)
tasks/
  BOARD.md             one row per task: status, owner of next step, next free ID
  TASK_TEMPLATE.md     copy this to create a task
  T-0001-<slug>.md     one file per task — spec + implementation notes + result + review
```

- A task file is the **single record** of that task: spec, work log, result and
  review all live in it. Nothing is deleted from it; history is appended.
- `tasks/BOARD.md` is the index. The **Status line in the task file is the source
  of truth**; whoever changes a status updates the BOARD row in the same step.

## 3. Task lifecycle

```
PLANNED ──► READY ──► IN_PROGRESS ──► REVIEW ──► DONE
   │          │  ▲         │   ▲         │
   │          ▼  │         ▼   │         └──► REVIEW_FAILED ──► (new corrective task)
   │        BLOCKED ◄──────┘   │
   └──────────┴──── CANCELLED (any state before DONE)
```

| Status | Meaning | Set by | Allowed next |
|---|---|---|---|
| `PLANNED` | Draft; spec may be incomplete. Claude Code must not start it. | Cowork | READY, CANCELLED |
| `READY` | Spec complete, dependencies DONE, can be picked up. | Cowork | IN_PROGRESS, BLOCKED, CANCELLED |
| `IN_PROGRESS` | Claude Code is working on it. Acts as a lock. | Claude Code | REVIEW, BLOCKED |
| `BLOCKED` | Requirement is unclear, contradictory, or impossible. Questions are written in the task. | Claude Code | READY (Cowork, after answering), CANCELLED |
| `REVIEW` | Implemented; build + tests pass; every non-manual acceptance criterion passes; Result filled in. | Claude Code | DONE, REVIEW_FAILED |
| `DONE` | Cowork accepted it (and the owner confirmed any `[manual]` criteria). Terminal. | Cowork | — |
| `REVIEW_FAILED` | Not accepted. Terminal — the fix goes in a new corrective task. | Cowork | — |
| `CANCELLED` | No longer wanted. Terminal. | Cowork (or owner) | — |

Every status change appends one row to the task's **Status history** table
(`date | from → to | who | note`).

## 4. Rules for both sides

1. **One task, one owner at a time.** Cowork does not edit a task that is
   `IN_PROGRESS` (except to cancel it, with a note in the history). Claude Code
   does not edit a task that is not assigned to it by status.
2. **Section ownership in a task file.**
   - Cowork writes: header fields, Objective → Definition of Done, Review.
   - Claude Code writes: Status (its own transitions), Questions, Implementation
     Notes, Result.
   - Neither rewrites the other's sections. Clarifications from Cowork during
     BLOCKED go into the Questions section as answers, then the spec is amended
     with a dated `> Amended YYYY-MM-DD: …` note — never silently.
3. **No duplicate work.**
   - Before creating a task, Cowork searches `tasks/BOARD.md` and `ROADMAP.md` for
     overlap and links related tasks instead of duplicating them.
   - Claude Code works on **one task at a time** and only on tasks in `READY`.
   - Problems found outside the task's scope are **not fixed** — Claude Code lists
     them under *Result → Proposed follow-ups*; Cowork decides whether they become tasks.
4. **Acceptance criteria must be checkable.** Each criterion has an ID (`AC-1`…) and
   a verification tag:
   - `[test]` — a unit test proves it (name the test or behaviour)
   - `[build]` — tests + Release build succeed
   - `[code]` — verifiable by reading the diff (e.g. "no new `SCShareableContent` call")
   - `[manual]` — needs the real app / a game / macOS permissions; the owner runs
     the steps written in the task. Claude Code cannot mark these as passed.
5. **Never report DONE on unmet criteria.** Claude Code may only set `REVIEW` when
   every `[test]`, `[build]` and `[code]` criterion passes. `[manual]` criteria are
   reported as "pending owner" with exact steps. Cowork sets `DONE` only when all
   criteria, including `[manual]`, are confirmed.
6. **Requirement problems are reported, not guessed.** If a spec is ambiguous,
   conflicts with the code, `CLAUDE.md` stability rules, or another task, Claude
   Code writes the question plus a concrete proposal in the task, sets `BLOCKED`
   and stops.
7. **Corrective tasks, not rewrites.** When a review fails, Cowork:
   1. fills the Review section of the original task (which criteria failed, why),
   2. sets it to `REVIEW_FAILED` and adds `Follow-up: T-xxxx`,
   3. creates a new task with `Corrects: T-yyyy` whose context quotes the failed
      criteria. The original task's spec and Result are never edited.
8. **Git.** Nobody commits or pushes unless the **owner explicitly asks**. Work stays
   in the working tree until then. Claude Code does not start a new task while
   source changes from another task are still uncommitted (docs under `tasks/`,
   `ROADMAP.md`, `WORKFLOW.md` don't count) — it asks the owner to commit or to
   allow stacking first. When asked to commit, one task = one commit, with the task
   ID in the message; whoever commits records the short hash in the task's Result
   (*Commit* line) and in the BOARD row.
   **Branches:**
   - `develop` is the working branch: task commits, Cowork's docs commits and hash
     records all go there.
   - `main` holds reviewed work only. Nobody commits on `main` directly.
   - `main` is updated only when the **owner** asks to merge `develop` into it — normally
     when a milestone is done (all its tasks DONE, manual checks passed). Default:
     fast-forward merge, or a GitHub PR `develop → main` if the owner prefers.
   - CI runs on pushes to `main` and on PRs, not on pushes to `develop`.
9. **Stability rules in `CLAUDE.md` apply to every task** (no repeated Screen
   Recording prompt after a rebuild, no crash/freeze after reopen or game restart,
   build never broken). Cowork does not write tasks that require breaking them
   without saying so explicitly and explaining why.

## 5. Cowork playbook

**Plan** — keep `ROADMAP.md` current: goals, the active milestone, and a triaged
backlog. Read `CLAUDE.md` → *Architecture*, *Stability rules* and *macOS permission
gotchas* before specifying anything touching capture, permissions or build.

**Create a task**
1. Take the next ID from `tasks/BOARD.md` (`Next ID`), then increment it there.
2. Copy `tasks/TASK_TEMPLATE.md` to `tasks/T-NNNN-short-slug.md`.
3. Fill every Cowork section. Size: one task ≈ one reviewable commit. Split bigger
   work and chain it with `Depends on`.
4. Write acceptance criteria as observable outcomes with a verification tag, not as
   implementation instructions. Put known technical hints in *Context*, clearly
   marked as hints — the HOW belongs to Claude Code.
5. Add the row to BOARD. Leave it `PLANNED` until it is complete, then set `READY`.

**Hand off** — tell the owner which task is READY; the owner tells Claude Code
"ทำ T-NNNN" (or "ทำ task ถัดไป" = lowest-numbered READY task whose dependencies are DONE).

**Review a task in `REVIEW`**
1. Read *Result*: the AC table, build/test evidence, changed files, follow-ups.
2. Check each criterion against its evidence; look at `git diff` for `[code]` items
   (Cowork may read code, not edit it).
3. Make sure changed files match *Files / Modules* or are justified in the notes.
4. Ask the owner to run `[manual]` steps if any; record the outcome.
5. Fill *Review* → set `DONE` or `REVIEW_FAILED` (+ corrective task). Update BOARD.
6. Turn accepted *Proposed follow-ups* into backlog items or new tasks.
7. Remind the owner the task is ready to commit (on `develop`). When a milestone is
   complete, suggest merging `develop` into `main`.

## 6. Claude Code procedure (summary — details in `CLAUDE.md`)

Pick READY task → check branch is `develop` and working tree → read spec + code → `BLOCKED` if unclear →
`IN_PROGRESS` → implement within scope → bump version → tests + Release build →
review `git status` / `git diff` → check every AC with evidence → fill Result →
`REVIEW` (or stay/`BLOCKED` with reason) → report to owner in Thai → no commit unless asked.
