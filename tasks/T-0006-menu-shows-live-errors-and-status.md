# T-0006 — The menu must show the current error, status and stats

| Field | Value |
|---|---|
| **Status** | READY |
| **Type** | fix |
| **Priority** | P2 |
| **Version impact** | patch |
| **Milestone** | M2 — Reliability & UX |
| **Depends on** | — |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-23 by Cowork (code audit v1.11.11, finding 5) |

## Objective
When translation fails (wrong API key, rate limit, DeepL quota, network) the user
must be able to see why by opening the menu bar menu. Today errors are recorded but
the menu is never refreshed, so the user just sees nothing being translated.

## Context
- `StatusBarController.rebuildMenu()` builds a static `NSMenu`; it is rebuilt only on
  start, stop, and region changes. Nothing observes `pipeline.lastError`,
  `pipeline.status` or `pipeline.stats`.
- So "⚠️ <error>", "สถานะ: …", "⚡ OCR … | แปล …" and the DeepL "📊 เหลือ" line are
  stale or missing while running.
- Hint: rebuilding when the menu opens (`NSMenuDelegate.menuNeedsUpdate(_:)`) is one
  option; observing the published properties is another.

## Requirements
1. Each time the user opens the menu it shows the current status, the latest error
   (or none, once translation succeeds again), current stats and DeepL remaining chars.
2. Existing items, order, shortcuts and Thai wording are unchanged.
3. No noticeable cost per captured frame (the menu must not be rebuilt every frame
   while closed).

## Out of scope
- New UI for errors (notifications, badges on the icon) — possible follow-up.
- Changing error texts (DeepL 403 wording is in the backlog).

## Constraints
- CLAUDE.md stability rules apply. `StatusBarController` is `@MainActor`.

## Files / Modules
- `Sources/App/StatusBarController.swift`

## Acceptance Criteria
- **AC-1** [code] Menu content reflects `lastError`, `status`, `stats` and remaining
  DeepL characters at the moment it is opened.
- **AC-2** [code] The menu is not rebuilt per captured frame.
- **AC-3** [manual] Steps: 1) select OpenAI with an invalid key (e.g. `sk-test`),
  2) start translating a game with visible text, 3) open the menu. Expected: a
  "⚠️ …" line with the HTTP 401 error. 4) Fix the key, wait for a translation,
  reopen the menu. Expected: the error line is gone and the ⚡ stats line is present.
- **AC-4** [build] Unit tests and Release build succeed.

## Testing Requirements
- Owner runs AC-3.

## Definition of Done
- [ ] All acceptance criteria pass (`[manual]` ones confirmed by the owner)
- [ ] Full test suite passes; Release build succeeds
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
