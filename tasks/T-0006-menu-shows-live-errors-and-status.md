# T-0006 — The menu must show the current error, status and stats

| Field | Value |
|---|---|
| **Status** | REVIEW |
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

- **Approach (first hint): `NSMenuDelegate.menuNeedsUpdate(_:)`.** AppKit calls it
  right before the menu opens; it calls `rebuildMenu()`, so status, `lastError`,
  stats and DeepL remaining characters are read at that moment (Req 1).
- To refill a menu while it is opening, the same `NSMenu` object must be used —
  a menu can't be replaced at that point. `rebuildMenu()` therefore no longer
  creates a new `NSMenu` each time: `makeMenu()` creates one on first use (delegate
  = self, assigned to the status item), and every rebuild does `removeAllItems()`
  and adds the items with the **unchanged** code (same items, order, shortcuts,
  Thai text — Req 2).
- Existing `rebuildMenu()` calls (start, stop, region changes, unexpected stop) are
  kept; they still update the menu immediately when it is already built.
- **Cost (Req 3 / AC-2):** nothing observes the per-frame `@Published` properties;
  the menu is rebuilt only when opened or on the existing events. No change to the
  pipeline.
- **Why not observe `lastError`/`status`/`stats`:** `stats` changes every frame, so
  observing it would rebuild the closed menu per frame (the thing Req 3 forbids)
  or need throttling. Rebuilding on open is simpler and always current.
- The error line disappears once a translation succeeds because
  `PipelineCoordinator.translatePending` already sets `lastError = nil` on success;
  the API key fields in Settings already call `pipeline.updateProvider()`, so fixing
  the key while running takes effect (AC-3 step 4), after the 3 s failure back-off.
- The build shows no concurrency warnings for the `NSMenuDelegate` conformance
  (`StatusBarController` is `@MainActor`).

## Result

**Outcome:** PARTIAL — all `[code]`/`[build]` criteria pass; AC-3 pending owner
**Version:** 1.11.15 → 1.11.16
**Commit:** `0c8273a`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `extension StatusBarController: NSMenuDelegate { func menuNeedsUpdate(_:) { rebuildMenu() } }`; `makeMenu()` sets `menu.delegate = self`; `rebuildMenu()` reads `pipeline.status`, `pipeline.lastError`, `pipeline.stats`, `AppSettings.shared.remainingCharacters` each time. |
| AC-2 | ✅ pass | `rebuildMenu()` is called only from init, start/stop, region callbacks, unexpected stop and `menuNeedsUpdate`; no subscription to per-frame state; no pipeline change. |
| AC-3 | ⏳ pending owner | Steps below. |
| AC-4 | ✅ pass | `Executed 63 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 63 tests, with 0 failures (0 unexpected) in 0.437 (0.465) seconds
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```
(The test log also shows two `mdb_txn_commit error: MDB_MAP_FULL` lines from a
system framework's cache during the Vision OCR tests — log noise, tests pass.)

### Changed files
```
 Resources/Info.plist                              |  2 +-
 Sources/App/StatusBarController.swift             | 21 +++++++++++++++++++--
 tasks/BOARD.md, tasks/T-0006-…md                  | (status + this report)
```

### Manual checks for the owner
**AC-3** — after `./build.sh`:
1. Settings → provider OpenAI, API key `sk-test`.
2. Start translating a game with visible text; wait a few seconds.
3. Open the menu bar menu. Expected: `สถานะ: …` plus a line `⚠️ แปลไม่สำเร็จ: HTTP 401: …`.
4. Put the real key back (while still running), wait for a translation to appear,
   reopen the menu. Expected: no ⚠️ line; `⚡ OCR: …ms | แปล: …ms` is shown.
Also check: with DeepL Free selected, `📊 เหลือ: …` goes down after translations.

### Proposed follow-ups
- none

---

## Review

**Cowork, 2026-09-23 — code review passed; waiting for owner's AC-3.**

| AC | Verdict | Note |
|---|---|---|
| AC-1 | ✅ | One `NSMenu` for the app lifetime, refilled in `menuNeedsUpdate(_:)`. |
| AC-2 | ✅ | Nothing observes per-frame stats; rebuild only on open and existing events. |
| AC-3 | ⏳ owner | |
| AC-4 | ✅ | |

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-23 | → READY | Cowork | created from code audit v1.11.11 |
| 2026-09-23 | READY → IN_PROGRESS | Claude Code | started |
| 2026-09-23 | IN_PROGRESS → REVIEW | Claude Code | code/build ACs pass; AC-3 manual pending owner |
