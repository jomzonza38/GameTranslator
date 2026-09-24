# T-0017 — Find out why the first OCR after a new build takes ~74 s

| Field | Value |
|---|---|
| **Status** | READY |
| **Type** | investigation |
| **Priority** | P2 |
| **Version impact** | none (patch if code changes) |
| **Milestone** | M4 — Performance & first use |
| **Depends on** | — |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-24 by Cowork (owner's logs) |

## Objective
After installing a new build, the first translation session shows nothing for
**over a minute**. Find the cause and either fix it or make the wait visible to the user.

## Context
- Owner's log 2026-09-24, both times the first capture after launching a freshly built app:
  - v1.11.24: start 09:32:42 → `09:33:56 OCR [Region 1]: 0 texts in 74039ms`
  - v1.11.25: start 09:59:30 → `10:00:44 OCR [Region 1]: 1 texts in 73652ms`
  Later OCR runs take 25–150 ms. A second start in the same launch was fast.
- The `sample` from T-0015's review shows `ANEServicesThread` threads. Hint (unverified):
  Vision's text recognizer may compile its Neural Engine model on first use, and the
  compiled cache may be tied to the app build/signature. That would explain why it
  happens after every rebuild but may not affect a normally installed app.
- Unknown: does it also happen on the first launch after a reboot without rebuilding?
  Does it depend on OCR Fast vs Accurate or on the recognition languages?

## Requirements
1. Report the cause, with evidence (timings, conditions under which it does and doesn't happen).
2. If it can be avoided or shortened (e.g. warming Vision up at launch in the
   background), do it. Otherwise show a Thai status in the menu/panel
   (e.g. "กำลังเตรียม OCR ครั้งแรก…") while the first OCR is running.
3. No new crash or freeze paths; launch stays responsive.

## Out of scope
- General OCR speed after warm-up. CPU while idle (T-0016).

## Constraints
- CLAUDE.md stability rules apply.

## Files / Modules
- `Sources/Services/OCRService.swift`, `Sources/App/AppDelegate.swift` (warm-up), menu/panel status if needed

## Acceptance Criteria
- **AC-1** [code] Implementation Notes record the cause, with measurements, and which conditions reproduce it.
- **AC-2** [manual] Steps: `./build.sh`, start translating a window with text right away. Expected: text translated within ~5 s of start, **or** the Thai "preparing OCR" status is visible until it is.
- **AC-3** [build] Unit tests and Release build succeed.

## Testing Requirements
- Owner runs AC-2 after a fresh build.

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
| 2026-09-24 | → READY | Cowork | from owner's logs 09:33 / 10:00 |
