# T-0023 — Each word and sentence in the Learning window explains what it means

| Field | Value |
|---|---|
| **Status** | DONE |
| **Type** | feature |
| **Priority** | P2 |
| **Version impact** | minor |
| **Milestone** | M6 — Learn the language from the games you play |
| **Depends on** | T-0022 |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-24 by Cowork (owner request) |

## Objective
The owner wants to see "คำนี้แปลว่าอะไร" and "ประโยคนี้หมายถึงอะไร". After T-0022 the
Learning window lists words and sentences; this task fills in a Thai meaning for each word
(in the sense used in the game) and a short explanation for a sentence on request.

## Context
- Owner decision (2026-09-24): meanings come from **AI when an LLM key exists** (OpenAI or
  Claude — the one in the chat-provider setting from T-0025 if present, else the selected
  translation provider if it is an LLM, else any LLM with a key in the Keychain),
  **otherwise Google Free** (single-word translation, no context).
- A sentence already has its Thai translation from the game; "meaning" for a sentence =
  that translation, plus an optional AI explanation (grammar / idiom / slang) on demand.
- `LLMChatProvider.complete(system:user:maxTokens:)` exists for OpenAI/Claude; keys live in
  the Keychain (`TranslationProviderType.keychainAccount`). Reading a second provider's key
  **only when the user asks for meanings** is fine; don't read it at launch.
- Hint: ask the LLM for several words in one request with a structured reply (word, part of
  speech, Thai meaning in this game's context, one short note), using an example sentence
  and the game title as context. Parse defensively (like `LLMPrompt.parseNumbered`).

## Requirements
1. Word rows show a Thai meaning and the source of it (AI / Google) once looked up.
2. Meanings are looked up **only from the Learning window** — a "หาความหมาย" button for the
   words currently shown without a meaning (in batches), and automatically for a word when
   its detail is opened. Never during translation of the game.
3. With an LLM key: meaning fits the game context (uses an example sentence + game title),
   includes part of speech. Without one: Google Free translation of the word; the UI says
   the meaning is without context and that adding an AI key gives better meanings.
4. A sentence detail shows original, the game's Thai translation, and a button
   "อธิบายประโยคนี้" (AI only) that returns a short Thai explanation (key words, grammar,
   idioms). Without an LLM key the button explains that a key is needed.
5. Meanings and explanations are saved with the item (T-0022 store) and not requested again;
   a "หาความหมายใหม่" action re-requests one item.
6. Errors (no network, 401, quota) show a Thai message in the window, never crash, and never
   pause or affect the translation pipeline. No retry storm: one batch at a time,
   cancellable, and a failed batch is not retried automatically.
7. LLM replies that are chatter or unparsable leave the item without a meaning (not a wrong
   meaning).

## Out of scope
- Quiz (T-0024), free chat (T-0025). Dictionaries/offline word lists. Text-to-speech.

## Constraints
- CLAUDE.md stability rules apply. Thai UI strings. Keys only from the Keychain.
- The translation cache and pipeline are not used for lookups (don't pollute the cache).

## Files / Modules
- `Sources/Services/` new meaning-lookup service; `LearningStore` (fields)
- `Sources/Views/LearningView.swift`
- `Sources/Providers/*` only if a small shared helper is needed
- `Tests/…`

## Acceptance Criteria
- **AC-1** [test] Building the meaning prompt includes the word, an example sentence and the
  game title; parsing a well-formed reply fills word → (pos, meaning); a malformed / chatter
  reply fills nothing and does not throw.
- **AC-2** [test] Provider choice: chat setting LLM with key → it; else selected LLM
  provider with key → it; else any LLM with key → it; else Google Free. (Use injected key
  lookup, not the real Keychain.)
- **AC-3** [test] A looked-up meaning is saved and a second lookup of the same word sends no
  request; "หาความหมายใหม่" sends one.
- **AC-4** [code] No lookup runs from `PipelineCoordinator`; no key is read at launch for
  this feature; no new permission API.
- **AC-5** [manual] Steps: with a Claude or OpenAI key, open Learning → คำศัพท์ → หาความหมาย.
  Expected: meanings in Thai that fit the game; part of speech shown; reopening the app keeps
  them.
- **AC-6** [manual] Steps: remove all LLM keys (Google Free only), look up words. Expected:
  Google meanings with the "ไม่มีบริบท" note.
- **AC-7** [manual] Steps: open a sentence → อธิบายประโยคนี้. Expected: short Thai
  explanation. Turn off Wi-Fi and try again → Thai error message, app keeps working.
- **AC-8** [build] Unit tests and Release build succeed.

## Testing Requirements
- Unit tests for AC-1 … AC-3 with a fake provider.

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

- **Started while PLANNED** on the owner's instruction; builds on T-0022 (in REVIEW,
  uncommitted, stacked).
- **`Sources/Services/MeaningService.swift`** (new):
  - `MeaningSource.choose` (pure, AC-2): the chat setting's LLM with a key (T-0025
    passes it in) → the selected translation provider if it is Claude/OpenAI with a key
    → any LLM with a key (Claude first) → Google Free.
  - `MeaningPrompt` (pure, AC-1). System prompt: game title + source language, "Thai
    meaning as used in the example line", strict one-line format
    `[N] part of speech | Thai meaning | short Thai note`. The user message lists
    `[N] word — example: "…"`. `parse` accepts only in-range numbered lines with a
    separator and a Thai meaning that isn't chatter (reuses `LLMPrompt.looksLikeChatter`).
    Everything else is skipped, so a word gets **no** meaning rather than a wrong one
    (Req 7). It never throws.
  - `MeaningService` (`@MainActor`, dependencies injectable for tests: key lookup, LLM
    factory, Google provider):
    - `lookUp(wordIDs:…)`: up to 20 words without a meaning, **one request**; saved into
      the T-0022 store with `meaningSource` "ai"/"google" and the part of speech the AI
      gives.
    - `explain(sentenceID:…)`: one AI request, saved as `explanation`.
    - One job at a time (`isWorking`), cancellable (`หยุด`), and a failure sets a Thai
      message and is **not retried** (Req 6).
    - It uses `LLMChatProvider.complete` / `GoogleFreeProvider.translateBatch` directly —
      not `TranslationService` — so the translation cache is untouched.
- **Keys:** read through `AppSettings.loadApiKeyIfNeeded` only when a lookup or
  explanation actually runs (button, or opening a word without a meaning). Nothing at
  launch; `MeaningService.shared` is created when the Learning window is shown.
- **Store fields** (T-0022 model, all optional so older files still load):
  `LearningWord.meaning / meaningSource / meaningNote`, `LearningSentence.explanation`.
  Saved with the item; a second lookup of a word with a meaning sends nothing (Req 5).
- **Learning window:**
  - Word rows: "ความหมาย: …" with an **AI** / **Google** badge.
  - Footer (คำศัพท์ tab): **หาความหมาย (N)** for the shown words without a meaning (≤ 20
    per press), progress + **หยุด**, the Thai error, or the note "ความหมายจาก Google (ไม่มีบริบท)
    — ใส่ API key ของ Claude/OpenAI จะได้ความหมายตามเกม" (Req 3).
  - Selecting a row opens a detail pane on the right:
    - word: meaning, note, source note, **หาความหมายใหม่**, examples; auto-lookup if it has no
      meaning (Req 2).
    - sentence: original, Thai, **อธิบายประโยคนี้** / **อธิบายใหม่**; without an AI key the button
      shows "ต้องมี API key ของ Claude หรือ OpenAI…" (Req 4).
- `PipelineCoordinator` has no meaning/explain call (AC-4: only the T-0022 `add`).

## Result

**Outcome:** PARTIAL — `[test]`/`[code]`/`[build]` criteria pass; AC-5 … AC-7 pending owner
**Version:** 1.12.0 → 1.13.0
**Commit:** `b8ad367`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `MeaningPromptTests`: prompt has word, example, game title; well-formed reply parsed (pos + meaning + note); chatter, no-Thai, missing separator, out-of-range, empty → nothing, no throw. |
| AC-2 | ✅ pass | `testProviderChoiceOrder` with an injected key lookup (chat → selected → any LLM → Google). |
| AC-3 | ✅ pass | `testMeaningIsSavedAndNotRequestedAgainUnlessForced` (1 request, saved; second lookup 0; force 1). Also chatter → no meaning + message; 401 → Thai message, no retry; explain without key → no request. |
| AC-4 | ✅ pass | `grep Meaning Sources/Services/PipelineCoordinator.swift` → none; keys only read inside `lookUp`/`explain`; no permission API. |
| AC-5…AC-7 | ⏳ pending owner | Steps below. |
| AC-8 | ✅ pass | `Executed 176 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 176 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files (this task only, on top of T-0022)
```
 Resources/Info.plist                    | 1.13.0
 Sources/Services/MeaningService.swift   | (new) source choice, prompts/parsing, service
 Sources/Services/LearningStore.swift    | optional meaning / explanation fields
 Sources/Views/LearningView.swift        | meanings in rows, lookup controls, detail panes
 Tests/MeaningServiceTests.swift         | (new, 8 tests)
```

### Manual checks for the owner
After `./build.sh`:
- **AC-5:** with a Claude or OpenAI key → Learning → คำศัพท์ → **หาความหมาย** → Thai meanings
  that fit the game, with part of speech and an **AI** badge; quit and reopen → still there.
- **AC-6:** with no LLM key (Google Free only) → look up words → meanings with a **Google**
  badge and the "ไม่มีบริบท" note.
- **AC-7:** open a sentence → **อธิบายประโยคนี้** → a short Thai explanation. Turn off Wi-Fi
  and press **อธิบายใหม่** → a Thai error message; the app (and translation) keeps working.

### Proposed follow-ups
- none

---

## Review

**2026-09-24 — Cowork audit review: DONE**

- AC-1…AC-4, AC-8 ✅ (MeaningServiceTests; no lookup from `PipelineCoordinator`; keys read in `lookUp`/`explain` or when Settings opens, not at launch). AC-5…AC-7 ✅ owner confirmed 2026-09-24.
- Findings (→ T-0026): prompts and Google lookups use the *current* source-language setting, not the language the game was collected in — a Japanese game looked up while the setting is English gets `from: en` / "learn English" and the wrong meaning is saved and never re-requested. Low: หยุด then หาความหมาย again lets the old task's `defer` clear `isWorking` while the new batch runs (two batches at once); opening another word while a batch runs silently skips its auto lookup.
- Changed files match *Files / Modules* (AppDelegate quit-save in T-0022 justified in notes). Stability rules: no new permission/capture API, pipeline change limited to one call.

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → PLANNED | Cowork | created; READY when T-0022 is DONE |
| 2026-09-24 | PLANNED → IN_PROGRESS | Claude Code | started on the owner's instruction ("do all of M6") while T-0022 is in REVIEW; stacked, uncommitted |
| 2026-09-24 | IN_PROGRESS → REVIEW | Claude Code | test/code/build ACs pass; AC-5…AC-7 manual pending owner |
| 2026-09-24 | REVIEW → DONE | Cowork | audit review; owner confirmed manual checks; follow-ups → T-0026 + backlog |
