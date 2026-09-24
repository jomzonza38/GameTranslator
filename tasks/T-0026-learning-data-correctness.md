# T-0026 — Learning data stays correct: per-game language, ordered saves, clean clear

| Field | Value |
|---|---|
| **Status** | READY |
| **Type** | fix |
| **Priority** | P2 |
| **Version impact** | patch |
| **Milestone** | M6 — Learn the language from the games you play |
| **Depends on** | — |
| **Corrects** | — (follow-up of the T-0022/T-0023/T-0025 audit review, which passed) |
| **Follow-up** | — |
| **Created** | 2026-09-24 by Cowork (audit review of M6) |

## Objective
M6 works, but the audit found three ways the saved learning data can become wrong:
meanings looked up in the wrong language, an older save overwriting a newer one, and a
cleared game coming back. Learning data is kept permanently, so wrong data stays — fix
them before the owner collects a lot of it.

## Context
1. **Language per game.** `LearningStore.add(... languageCode:)` receives the source
   language but doesn't store it. `MeaningService.lookUp/explain` and the chat context
   (`LearningView.chatContext`) use `AppSettings.sourceLanguage` *now*. Looking up a Japanese
   game's words while the setting is English → Google `from: "en"` / prompt "learn English";
   the wrong meaning is saved and never re-requested.
2. **Save order.** `scheduleSave` sets `hasUnsavedChanges = false` and starts a detached
   write; a newer save can start before it ends (cancelling the Task doesn't stop the
   detached write), so the older snapshot can be renamed into place last. At quit,
   `saveIfNeeded` skips when a write is still running, and a quit during that write can lose
   the last changes.
3. **Clear race.** Word extraction runs in a detached task and then `addWords` re-creates
   `file.games[game]` — after "ล้างรายการของเกมนี้" (or a deleted sentence) a late extraction
   brings the game back with words only.

## Requirements
1. Each game's data remembers its source language (the language it was collected in; if it
   changes, the latest one). Meaning lookups, sentence explanations and the chat use the
   game's language; the current setting is only the fallback for data saved before this
   change (no language stored).
2. Saves happen one at a time and in order; the file on disk always ends up with the newest
   data. "Unsaved" stays true until a write has actually finished; quit writes the newest
   data even if a background write is running.
3. After a game is cleared, words from extractions that were still running are dropped
   (the game does not reappear). Words from a deleted sentence that is still being
   extracted are dropped too.
4. Old `learning.json` files load unchanged.

## Out of scope
- The low findings kept in the ROADMAP backlog (first load on main actor, list re-sorting,
  quiz game switch, chat key edit calling `updateProvider`, cancel/relookup overlap).
- Re-looking-up meanings that were already saved in the wrong language (owner can use
  "หาความหมายใหม่").

## Constraints
- CLAUDE.md stability rules apply. No change to the translation pipeline beyond the existing
  `LearningStore.add` call. No file I/O on the main actor except the quit save.

## Files / Modules
- `Sources/Services/LearningStore.swift`, `Sources/Services/MeaningService.swift`,
  `Sources/Views/LearningView.swift`
- `Tests/LearningStoreTests.swift`, `Tests/MeaningServiceTests.swift`

## Acceptance Criteria
- **AC-1** [test] A game added with `ja` keeps `ja` after save/load; a lookup for that game with
  the setting on English sends `from: "ja"` to Google and the Japanese language name in the LLM
  prompt (fake providers). A file without the field loads and falls back to the setting.
- **AC-2** [test] Two saves where the first write is slower (injected writer/delay) → the file
  holds the second snapshot; `saveIfNeeded` during a running write still writes the newest data.
- **AC-3** [test] `add` then `clear(game:)` before extraction finishes → after it finishes the
  game is not in `games`.
- **AC-4** [code] Chat context uses the game's language; no new main-actor file I/O.
- **AC-5** [manual] Steps: collect some lines from a Japanese game (source ญี่ปุ่น), switch the
  setting to English, open Learning → that game → หาความหมาย. Expected: Thai meanings of the
  Japanese words.
- **AC-6** [build] Unit tests and Release build succeed.

## Testing Requirements
- Unit tests for AC-1 … AC-3 (temp directory; fake providers; no real Keychain).

## Definition of Done
- [ ] All acceptance criteria pass (`[manual]` ones confirmed by the owner)
- [ ] Unit tests added/updated as required; full suite passes
- [ ] Release build succeeds
- [ ] Version bumped per CLAUDE.md (or "none" justified)
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
| 2026-09-24 | → READY | Cowork | created from M6 audit review |
