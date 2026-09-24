# T-0022 — Learning window: every sentence and word the app has translated, kept per game

| Field | Value |
|---|---|
| **Status** | READY |
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

## Result

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → PLANNED | Cowork | created from owner request (learning menu) |
| 2026-09-24 | PLANNED → READY | Cowork | owner answered storage/meaning/chat questions |
