# T-0024 — Multiple-choice quiz on the words and sentences collected from the game

| Field | Value |
|---|---|
| **Status** | DONE |
| **Type** | feature |
| **Priority** | P2 |
| **Version impact** | minor |
| **Milestone** | M6 — Learn the language from the games you play |
| **Depends on** | T-0023 |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-24 by Cowork (owner request) |

## Objective
The owner wants a test "ว่าที่เรียนรู้มานั้นแปลถูกไหม" as multiple choice. A quiz tab in the
Learning window asks about the current game's words and sentences, gives 4 choices, shows
right/wrong with the answer, and remembers how well each item is known so weak items come
back more often.

## Context
- Items and meanings come from T-0022 / T-0023. Only words **with a meaning** and sentences
  (which always have a Thai translation) can be asked.
- The quiz must work fully offline (no request while answering).

## Requirements
1. New tab **แบบทดสอบ** in the Learning window, for the game chosen in the game picker.
   Options: number of questions (10 / 20 / 30), question type (คำศัพท์ / ประโยค / ผสม),
   include items marked "จำได้แล้ว" (default off).
2. Question types:
   a. word → pick the Thai meaning (4 choices)
   b. sentence (original) → pick the Thai translation (4 choices)
   c. Thai meaning → pick the English/source word (4 choices)
3. Wrong choices come from other items of the same game (same kind, and for words the same
   part of speech when possible); never a duplicate or the right answer twice. If a game has
   fewer than 4 usable items of a kind, that kind is not offered and the UI says why
   (e.g. "ต้องมีคำที่มีความหมายอย่างน้อย 4 คำ").
4. After each answer: green/red, the right answer, the example sentence for words; "ถัดไป".
   Keyboard: 1–4 to answer, Return for next.
5. End screen: score, list of missed items, "ทบทวนข้อที่ผิด" (quiz only the missed ones).
6. Each item stores correct/wrong counts and last asked date (saved with T-0022 data).
   Selection favours items answered wrong or never asked; an item answered right 3 times in
   a row is suggested as "จำได้แล้ว" (one tap to mark).
7. No network, no crash with 0 items; the quiz doesn't touch the translation pipeline.

## Out of scope
- Typing answers, spaced-repetition scheduling across days, audio, cross-game quiz.

## Constraints
- CLAUDE.md stability rules apply. Thai UI strings.

## Files / Modules
- `Sources/Services/` new quiz generator (pure); `LearningStore` (stats)
- `Sources/Views/LearningView.swift` (+ quiz view)
- `Tests/…`

## Acceptance Criteria
- **AC-1** [test] Generated questions have exactly 4 distinct choices, exactly one right,
  right answer position varies; distractors come from the same game and kind.
- **AC-2** [test] With < 4 usable items of a kind the generator returns no question of that
  kind and a reason; with 0 items it returns an empty quiz without crashing.
- **AC-3** [test] Selection weighting: items with more wrong answers / never asked are picked
  before items answered right repeatedly (use a seeded random source).
- **AC-4** [test] Answer stats and "3 right in a row" suggestion are stored and survive
  save/load.
- **AC-5** [manual] Steps: after T-0023 meanings exist for a game, open แบบทดสอบ, run 10 mixed
  questions using keys 1–4 and Return. Expected: feedback per question, score at the end,
  "ทบทวนข้อที่ผิด" asks only the missed ones.
- **AC-6** [build] Unit tests and Release build succeed.

## Testing Requirements
- Unit tests for AC-1 … AC-4 with a seeded random generator.

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

- **Started while PLANNED** on the owner's instruction; stacked on T-0022/T-0023/T-0025
  (in REVIEW, uncommitted).
- **`Sources/Services/QuizGenerator.swift`** (new, pure, no network — Req 7):
  - Usable items: words **with a meaning** and sentences with a translation. Known items
    are left out unless "รวมรายการที่จำได้แล้ว" is on.
  - Kinds (Req 2): word → meaning, sentence → translation, meaning → word. For a word
    question the direction is random.
  - Distractors (Req 3): other items of the same game and kind; for words, the same part
    of speech first, then any. Choices are de-duplicated and never contain the right
    answer twice; it sits at a random position. If a kind has fewer than 4 distinct
    answers it isn't used, and the reason is returned ("ต้องมีคำที่มีความหมายอย่างน้อย 4 คำ
    (กด หาความหมาย ในแท็บคำศัพท์)" / "ต้องมีประโยคอย่างน้อย 4 ประโยค"). With 0 items the
    quiz is empty.
  - Selection (Req 6): weighted sampling without replacement. Weight = 4 if never asked,
    else `max(0.2, 1 + 2 × wrong − 1.5 × streak)`, so wrong / never-asked items come first
    and right streaks push items back.
  - `SeededRandom` (SplitMix64) for deterministic tests; the app uses the system generator.
- **Stats (Req 6):** `QuizStats { correct, wrong, streak, lastAsked }` as an optional
  `quiz` field on sentences and words (older files still load — tested).
  `LearningStore.recordQuizAnswer` saves one answer; `suggestsKnown` = 3 right in a row.
- **แบบทดสอบ tab** (Learning window; the search/sort row and list footer are hidden there):
  - Setup (Req 1): จำนวนข้อ 10/20/30, แบบ คำศัพท์/ประโยค/ผสม, รวมรายการที่จำได้แล้ว (default
    off), how many usable items, the reason if a kind isn't available; start is disabled
    when nothing can be asked.
  - Question (Req 4): "ข้อ N/M", score, prompt, 4 choices numbered 1–4, answered with the
    mouse or **keys 1–4**. Then green/red, "คำตอบคือ …", the example line for words, and
    **ถัดไป** (**Return**).
  - A one-tap "ทำเครื่องหมาย จำได้แล้ว" appears once an item reaches 3 right in a row.
  - End (Req 5): score, missed items with their answers, **ทบทวนข้อที่ผิด** (a quiz of only the
    missed items), the "จำได้แล้ว?" suggestions, ทำแบบทดสอบใหม่.
- It doesn't touch the translation pipeline, and nothing is requested while answering.

## Result

**Outcome:** PARTIAL — `[test]`/`[build]` criteria pass; AC-5 pending owner
**Version:** 1.14.0 → 1.15.0
**Commit:** `2717f05`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `QuizGeneratorTests.testQuestionsHaveFourDistinctChoicesAndOneRightAnswer` (12 questions: 4 distinct choices, exactly one right, all choices from the same game and kind, right position varies). |
| AC-2 | ✅ pass | `testTooFewItemsGiveNoQuestionAndAReason` (reasons for words and sentences), `testNoItemsIsAnEmptyQuiz`, `testSentencesOnlyWhenWordsHaveNoMeanings`. |
| AC-3 | ✅ pass | `testWeakItemsArePickedBeforeWellKnownOnes` (seeded: ≥ 4 of 5 picks are weak/new; weights ordered), `testReviewOnlyAsksTheMissedItems`. |
| AC-4 | ✅ pass | `QuizStatsPersistenceTests.testAnswerStatsAndKnownSuggestionSurviveSaveAndLoad` (1 wrong + 3 right → streak 3, suggestion, lastAsked; after reload), `testOlderFilesWithoutNewFieldsStillLoad`. |
| AC-5 | ⏳ pending owner | Steps below. |
| AC-6 | ✅ pass | `Executed 190 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 190 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files (this task only, on top of T-0025)
```
 Resources/Info.plist                    | 1.15.0
 Sources/Services/QuizGenerator.swift    | (new) generator, weighting, SeededRandom
 Sources/Services/LearningStore.swift    | QuizStats, recordQuizAnswer
 Sources/Views/LearningView.swift        | แบบทดสอบ tab (QuizView)
 Tests/QuizGeneratorTests.swift          | (new, 8 tests)
```

### Manual checks for the owner
After `./build.sh`, once a game has meanings (T-0023):
- **AC-5:** Learning → **แบบทดสอบ** → 10 ข้อ, ผสม → เริ่ม → answer with keys 1–4 and Return →
  green/red feedback with the answer each time, the score at the end; **ทบทวนข้อที่ผิด** asks
  only the missed ones.

### Proposed follow-ups
- none

---

## Review

**2026-09-24 — Cowork audit review: DONE**

- AC-1…AC-4, AC-6 ✅ (QuizGeneratorTests incl. old-file compatibility; distractor guarantee follows from the ≥ 4 distinct meanings/translations check). AC-5 ✅ owner confirmed 2026-09-24.
- Low (backlog): changing the game picker during a quiz keeps the old game's questions and records answers into the new game (no-op).
- Changed files match *Files / Modules* (AppDelegate quit-save in T-0022 justified in notes). Stability rules: no new permission/capture API, pipeline change limited to one call.

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → PLANNED | Cowork | created; READY when T-0023 is DONE |
| 2026-09-24 | PLANNED → IN_PROGRESS | Claude Code | started on the owner's instruction ("do all of M6") while T-0023 is in REVIEW; stacked, uncommitted |
| 2026-09-24 | IN_PROGRESS → REVIEW | Claude Code | test/build ACs pass; AC-5 manual pending owner |
| 2026-09-24 | REVIEW → DONE | Cowork | audit review; owner confirmed manual checks; follow-ups → T-0026 + backlog |
