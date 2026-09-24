# T-0022 — Learning window: every sentence and word the app has translated, kept per game

| Field | Value |
|---|---|
| **Status** | DONE |
| **Type** | feature |
| **Priority** | P2 |
| **Version impact** | minor |
| **Milestone** | M6 — Learn the language from the games you play |
| **Depends on** | — |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-24 by Cowork (owner request) |

## Objective
The owner wants to learn vocabulary from the games he plays. Every sentence the app
translates (original + Thai) and the words inside it should be collected **per game and
kept across launches**, and shown in a new "Learning" window with two lists:
ประโยค (sentences) and คำศัพท์ (words). This is the base that T-0023 (word meanings),
T-0024 (quiz) and T-0025 (AI chat) build on.

## Context
- Today only `TranslationHistory` exists: in memory, max 1,000, lost on quit
  (`Sources/Services/TranslationHistory.swift`). It is fed from
  `PipelineCoordinator` right after a real translation arrives (≈ line 825,
  `TranslationHistory.shared.add(original:translation:game:)`). The learning store should
  be fed from the same place (only real translations — not chatter fallbacks, not
  glossary exact-match shortcuts is fine either way; Claude Code decides and notes it).
- Owner decisions (2026-09-24): data is **saved permanently, separated by game**; words
  get meanings from AI if a key exists, otherwise Google Free (T-0023); the chat provider
  is chosen in Settings (T-0025).
- Games are identified by `settings.currentProfile.title` (per-game `GameProfile`).
- Source languages: EN (main use), JA, ZH, KO.
- Backlog note from the owner's test: number-only texts ("15", "7/1") are OCR'd. They
  must not become sentences or words here.
- Hint: `NaturalLanguage` (`NLTokenizer` / `NLTagger` with `.lemma` and `.lexicalClass`)
  is on-device, needs no network or permission, and handles JA/ZH word splitting.
- Hint: store as JSON under Application Support (`~/Library/Application Support/
  com.worawalan.GameTranslator/`), save debounced / off the main actor so the pipeline
  never waits on disk.

## Requirements
1. A new menu item **"📚 เรียนรู้คำศัพท์…"** (next to ประวัติคำแปล) opens a Learning window.
   Reopening brings the same window to front (no duplicates).
2. Each real translation adds a **sentence** (original, Thai, game, first-seen date, times
   seen). The same original text in the same game is stored once (times seen increases).
3. Words are extracted from each new sentence: lower-cased base form (e.g. "swords" →
   "sword", "running" → "run" for English), with the sentence(s) it appeared in as examples
   (keep a few, not all), times seen, and part of speech when known.
   Skipped: numbers / texts with no letters, single letters, very common function words
   (the, a, is, of, to, and… — a short built-in list for English is enough), and
   anything in the game's glossary is still kept (glossary terms are useful to learn).
4. The window has: a **game picker** (default = the game being translated, or the last one),
   tabs **ประโยค** and **คำศัพท์**, search, sort (newest / most seen / A–Z), and a count.
   A word row shows the word, part of speech, times seen and one example sentence;
   meaning shows "—" until T-0023.
5. Each sentence and word can be marked **"จำได้แล้ว"** (known) and hidden with a filter
   ("ซ่อนคำที่จำได้แล้ว", default on). Items can be deleted; a game's whole list can be
   cleared (with a confirmation).
6. Data survives quit/relaunch and a rebuild. A corrupt or missing file never crashes the
   app: start empty, log it, and keep the broken file aside (don't overwrite it silently).
7. Collecting costs nothing noticeable: no disk write on the main actor per translation,
   no extra network request, no change to translation latency or to CPU on a static
   screen (T-0016).
8. A size limit keeps the file reasonable (e.g. per game ≤ 5,000 sentences; oldest
   unmarked, least-seen go first). Claude Code picks the numbers and notes them.

## Out of scope
- Word meanings (T-0023), quiz (T-0024), AI chat (T-0025).
- Changing or removing the existing History window (it stays as is).
- Sync / export / import of learning data.

## Constraints
- CLAUDE.md stability rules apply (no permission prompt, no crash when the game closes or
  the app is reopened, build never broken).
- Thai UI strings. The window follows the look of `HistoryView` / Settings.
- The pipeline's behaviour and timing must not change.

## Files / Modules
- `Sources/Services/LearningStore.swift` (new — model, persistence, word extraction)
- `Sources/Views/LearningView.swift` (new)
- `Sources/App/StatusBarController.swift` (menu item + window)
- `Sources/Services/PipelineCoordinator.swift` (one call where history is fed)
- `Tests/LearningStoreTests.swift` (new)

## Acceptance Criteria
- **AC-1** [test] Adding the same original twice in one game → one sentence, times seen = 2;
  same text in two games → two sentences.
- **AC-2** [test] Word extraction for English: "The knights drew their swords." →
  contains "knight", "draw" (or "drew" if no lemma), "sword"; does not contain "the",
  "their" or punctuation. "15", "7/1", "x" → no sentence and no words.
- **AC-3** [test] Save → load round-trip keeps sentences, words, known flags and dates;
  a corrupt file loads as empty without crashing and is not overwritten until moved aside.
- **AC-4** [test] The size limit drops the oldest unmarked items first; known items and
  their words are kept.
- **AC-5** [code] The pipeline hands the text to the store and returns; file I/O is not on
  the main actor and is debounced. No new network call, no new permission API.
- **AC-6** [manual] Steps: translate a game for a minute, open 📚 เรียนรู้คำศัพท์…
  Expected: sentences and words of that game are listed; search, sort, "จำได้แล้ว" and the
  hide filter work. Quit and reopen the app → the lists are still there.
- **AC-7** [manual] Steps: switch to another game, translate, open the window, switch the
  game picker. Expected: each game shows only its own items.
- **AC-8** [build] Unit tests and Release build succeed.

## Testing Requirements
- `LearningStoreTests` for AC-1 … AC-4 (use a temp directory, not the real Application
  Support folder, and don't touch the owner's data from tests).

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

- **Store** — `Sources/Services/LearningStore.swift` (new), `@MainActor ObservableObject`:
  - Model: `LearningFile { version, games: [title: GameLearningData], lastGame }`;
    `GameLearningData { sentences, words }`.
  - `LearningSentence`: original, Thai, first/last seen, times seen, known.
  - `LearningWord`: base form, part of speech, ≤ 3 example lines, first/last seen,
    times seen, known.
  - JSON at `~/Library/Application Support/com.worawalan.GameTranslator/learning.json`.
- **Fed from the pipeline** — same place as `TranslationHistory`, in `translatePending`,
  only for real translations. Glossary exact matches and cached / stale reuse never reach
  that code, and neither do chatter fallbacks (T-0011 leaves them out of the results).
  So only lines a provider actually translated are collected. Decision: glossary
  shortcuts are **not** collected; their terms still show up as words whenever they
  appear inside a translated line.
- **Cost (Req 7, AC-5):** `add()` on the main actor is an in-memory upsert (linear
  search of that game's list, ≤ 5,000 items, on new translations only — never per
  frame). Word extraction (`NLTagger`) runs in `Task.detached(priority: .utility)` and is
  applied back. Saving is debounced by 1 s; encoding and the atomic write happen in a
  detached task. No network and no permission API. On quit, pending changes are written
  synchronously in `applicationWillTerminate` (`saveIfNeeded`), so the last second isn't
  lost (small addition to `AppDelegate`, outside *Files / Modules*).
- **Words (Req 3):** `WordExtractor` uses `NLTagger` (`.lemma` + `.lexicalClass`) on
  device, with the game's source language set.
  - Base form, lower-cased: "knights" → "knight", "drew" → "draw", "swords" → "sword".
  - Skipped: texts with < 2 letters ("15", "7/1", "x" → no sentence, no words),
    numbers, Latin single letters, punctuation, and an English stop-word list
    (~110 function words, incl. "the", "their").
  - JA/ZH/KO are split into words by the tagger; single characters are kept for those
    scripts.
  - Glossary terms are not filtered (useful to learn).
  - Part of speech is stored as the NL tag and shown in Thai (คำนาม, คำกริยา, …).
- **Limits (Req 8):** per game 5,000 sentences and 10,000 words. When over, unmarked
  items with the fewest sightings and the oldest `lastSeen` go first. Known items, and
  words whose example lines are known sentences, are never dropped.
- **Broken file (Req 6):** unreadable JSON → start empty, log it, and move the file to
  `learning.corrupt-<date>.json` (never overwritten). A missing file → empty. Dates are
  stored as `Date`'s own reference-date number (exact round-trip).
- **Window (Req 1, 4, 5)** — `Sources/Views/LearningView.swift` (new):
  - Menu item **"📚 เรียนรู้คำศัพท์..."** below ประวัติคำแปล; one window, reopening brings it
    to the front.
  - Game picker: default = the game being translated, else the last game with data,
    else the first.
  - Tabs ประโยค / คำศัพท์, search, sort ล่าสุด / เห็นบ่อย / A–Z, "ซ่อนที่จำได้แล้ว"
    (default on, remembered), count "แสดง X จาก Y".
  - Known toggle per row, delete via right-click, "ล้างรายการของเกมนี้" with a confirmation.
  - Word rows show word, part of speech, times seen, "ความหมาย: —" (T-0023), last example.
- The History window is unchanged.

## Result

**Outcome:** PARTIAL — `[test]`/`[code]`/`[build]` criteria pass; AC-6 and AC-7 pending owner
**Version:** 1.11.32 → 1.12.0 (minor: new feature)
**Commit:** `156a639`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `LearningStoreTests.testSameOriginalInOneGameIsStoredOnce` (times seen 2), `testSameTextInTwoGamesIsTwoSentences`. |
| AC-2 | ✅ pass | `testEnglishWordsAreBaseFormsWithoutFunctionWords` (knight, draw/drew, sword; no the/their/punctuation), `testNumbersAndSingleLettersGiveNothing` ("15", "7/1", "x"), `testWordsCollectExamplesAndCounts`, `testJapaneseIsSplitIntoWords`. |
| AC-3 | ✅ pass | `testSaveAndLoadKeepEverything` (file equal after reload, incl. known flags, part of speech, dates), `testCorruptFileLoadsEmptyAndIsMovedAside` (broken content kept in `learning.corrupt-…`), `testMissingFileLoadsEmpty`. |
| AC-4 | ✅ pass | `testSizeLimitDropsOldestUnmarkedFirstAndKeepsKnown` (known sentence + its word + known word kept). |
| AC-5 | ✅ pass | `PipelineCoordinator`: one `LearningStore.shared.add(...)` next to the history call; extraction and file I/O off the main actor, save debounced; no URLSession / permission API in `LearningStore`. |
| AC-6, AC-7 | ⏳ pending owner | Steps below. |
| AC-8 | ✅ pass | `Executed 168 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 168 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                        | 1.12.0
 Sources/Services/LearningStore.swift        | (new) model, extraction, persistence, limits
 Sources/Views/LearningView.swift            | (new) Learning window
 Sources/App/StatusBarController.swift       | menu item + window
 Sources/Services/PipelineCoordinator.swift  | one add() next to the history call
 Sources/App/AppDelegate.swift               | save pending learning data at quit
 Tests/LearningStoreTests.swift              | (new, 10 tests; temp folder)
```

### Manual checks for the owner
After `./build.sh`:
- **AC-6:** translate a game for a minute → menu "📚 เรียนรู้คำศัพท์..." → the game's
  sentences and words are listed; try search, the three sorts, the ✓ "จำได้แล้ว" toggle
  and "ซ่อนที่จำได้แล้ว". Quit the app and reopen → the lists are still there.
- **AC-7:** translate a second game, open the window, switch the game picker → each game
  shows only its own items.

### Proposed follow-ups
- none

---

## Review

**2026-09-24 — Cowork audit review: DONE**

- AC-1…AC-5, AC-8 ✅ (tests + diff read: one `add()` in the pipeline, NLTagger + file I/O off the main actor, debounced save, no network/permission API). AC-6, AC-7 ✅ owner confirmed 2026-09-24.
- Findings (not blocking, → T-0026): overlapping background writes can finish out of order and `hasUnsavedChanges` is cleared before the write finishes; a word extraction still running after "ล้างรายการ" re-creates the game with words only; the game's source language is not stored (used by T-0023/T-0025). Backlog: first load is a synchronous JSON decode on the main actor at the first translation; the open window re-filters/sorts the whole list on every new translation.
- Changed files match *Files / Modules* (AppDelegate quit-save in T-0022 justified in notes). Stability rules: no new permission/capture API, pipeline change limited to one call.

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → PLANNED | Cowork | created from owner request (learning menu) |
| 2026-09-24 | PLANNED → READY | Cowork | owner answered storage/meaning/chat questions |
| 2026-09-24 | READY → IN_PROGRESS | Claude Code | started (owner: do all of M6, review after) |
| 2026-09-24 | IN_PROGRESS → REVIEW | Claude Code | test/code/build ACs pass; AC-6, AC-7 manual pending owner |
| 2026-09-24 | REVIEW → DONE | Cowork | audit review; owner confirmed manual checks; follow-ups → T-0026 + backlog |
