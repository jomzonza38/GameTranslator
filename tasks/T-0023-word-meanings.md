# T-0023 — Each word and sentence in the Learning window explains what it means

| Field | Value |
|---|---|
| **Status** | PLANNED |
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

## Result

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → PLANNED | Cowork | created; READY when T-0022 is DONE |
