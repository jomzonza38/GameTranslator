# T-0026 — Learning data stays correct: per-game language, ordered saves, clean clear

| Field | Value |
|---|---|
| **Status** | REVIEW |
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

1. **Language per game (Req 1):**
   - `GameLearningData.languageCode` (optional) is set by every `add` to the language the
     line was collected in (the latest wins).
   - `LearningStore.sourceLanguage(for:fallback:)` returns it, or the fallback when a game
     was saved before this change (Req 4).
   - `MeaningService.lookUp(wordIDs:game:force:)` and `explain(sentenceID:game:force:)` no
     longer take a language from the view; they use `language(for: game)` for both the LLM
     prompt ("learn Japanese …") and Google's `from:`. The current setting is injected only
     as the fallback.
   - `LearningView.chatContext` uses the game's language for the chat too (AC-4).
2. **Ordered saves (Req 2):**
   - All writes go through one **serial** `DispatchQueue`, so they run one at a time in the
     order they were queued. A debounced save snapshots the newest data when it fires.
   - Two counters replace the flag: `changeCount` (every change) and `savedCount` (newest
     change whose write *finished*). `hasUnsavedChanges` = `savedCount < changeCount`, so
     it stays true until a write has really completed.
   - `saveNow()` / quit's `saveIfNeeded()` use `writeQueue.sync`: it waits for a write still
     running, then writes the newest data last. That is the only main-actor I/O, as the
     spec allows.
   - The writer is injectable (tests make the first write slow).
3. **Clear race (Req 3):** background extraction now calls
   `applyExtractedWords`, which adds the words only if their line still exists in that
   game. A cleared game, or a deleted line, is therefore not brought back. The direct
   `addWords` (tests, seeding) is unchanged.
- The translation pipeline is untouched (its `LearningStore.add` call is unchanged).

## Result

**Outcome:** PARTIAL — `[test]`/`[code]`/`[build]` criteria pass; AC-5 pending owner
**Version:** 1.15.0 → 1.15.1
**Commit:** not committed (waiting for owner)

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `LearningDataCorrectnessTests`: `testGameKeepsItsLanguageAcrossSaveAndLoad` (ja survives), `testGoogleLookupUsesTheGamesLanguageNotTheSetting` (setting English → Google `from: "ja"`), `testLLMPromptNamesTheGamesLanguage` ("learn Japanese"), `testDataWithoutALanguageFallsBackToTheSetting`. |
| AC-2 | ✅ pass | `testASlowOlderWriteCannotOverwriteANewerOne` (first write 0.3 s slower → the file has both lines, nothing unsaved), `testQuitSaveDuringARunningWriteWritesTheNewestData`. |
| AC-3 | ✅ pass | `testClearedGameDoesNotComeBackWithWords` (real `add` + immediate `clear`), `testWordsOfADeletedLineAreDropped`. |
| AC-4 | ✅ pass | `LearningView.chatContext` → `store.sourceLanguage(for:fallback:)`; no new main-actor file I/O (only `saveNow`/quit via `writeQueue.sync`). |
| AC-5 | ⏳ pending owner | Steps below. |
| AC-6 | ✅ pass | `Executed 198 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 198 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                         | 1.15.1
 Sources/Services/LearningStore.swift         | languageCode, serial ordered saves, applyExtractedWords
 Sources/Services/MeaningService.swift        | language from the game (fallback = setting)
 Sources/Views/LearningView.swift             | calls without a language; chat uses the game's language
 Tests/MeaningServiceTests.swift              | updated calls
 Tests/LearningDataCorrectnessTests.swift     | (new, 8 tests)
```

### Manual checks for the owner
**AC-5** — after `./build.sh`: translate some lines from a Japanese game (setting
ภาษาในเกม = ญี่ปุ่น), switch the setting to English, open Learning → that game →
หาความหมาย → Thai meanings of the **Japanese** words. (Data collected before this version
has no language stored and uses the current setting — pick ญี่ปุ่น again for those, or use
"หาความหมายใหม่".)

### Proposed follow-ups
- none

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → READY | Cowork | created from M6 audit review |
| 2026-09-24 | READY → IN_PROGRESS | Claude Code | started |
| 2026-09-24 | IN_PROGRESS → REVIEW | Claude Code | test/code/build ACs pass; AC-5 manual pending owner |
