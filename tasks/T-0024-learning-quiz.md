# T-0024 — Multiple-choice quiz on the words and sentences collected from the game

| Field | Value |
|---|---|
| **Status** | PLANNED |
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

## Result

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → PLANNED | Cowork | created; READY when T-0023 is DONE |
