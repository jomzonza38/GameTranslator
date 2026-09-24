# T-0025 — Ask the AI why a sentence was translated that way

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
From a sentence or word in the Learning window the owner can open a chat and ask questions
such as "ทำไมประโยคนี้ถึงแปลแบบนี้", "คำนี้ใช้ยังไง", "มีคำอื่นที่แปลได้อีกไหม" and get Thai
answers from an AI that knows the sentence, its Thai translation and the game.

## Context
- Owner decision (2026-09-24): the chat provider is **chosen in Settings** (new setting).
- OpenAI and Claude exist as `LLMChatProvider` with `complete(system:user:maxTokens:)`
  (single turn). Keys are in the Keychain per provider.
- Hint: a multi-turn chat can either extend the providers with a messages list or send the
  recent turns inside the user message — Claude Code decides; the translation prompt path
  (`LLMPrompt`, `sanitize`) must stay unchanged.
- T-0023 may land first and add a provider-choice helper; reuse it if so.

## Requirements
1. Settings gets **"AI สำหรับแชทเรียนรู้"** with choices: Claude Haiku 4.5, OpenAI GPT-4o-mini
   (default: the selected translation provider if it is one of these, else Claude). It shows
   whether a key for that provider is saved, and links to where to enter it.
2. In the Learning window, a sentence or word has **"💬 ถาม AI"**. It opens a chat pane
   (inside the Learning window) with the item shown on top and quick questions:
   "ทำไมแปลแบบนี้?", "แยกคำศัพท์ในประโยคนี้", "แปลแบบอื่นได้ไหม?", "ยกตัวอย่างประโยคอื่น".
   The user can also type freely (Return to send, Shift-Return for a new line).
3. The AI gets as context: original text, the game's Thai translation, game title, glossary
   terms that appear in it, and the conversation so far (last ~10 turns). It answers in
   Thai, as a friendly language teacher, and may point out when the game translation was
   wrong or could be better.
4. While waiting: a typing indicator and a Stop button; the send button is disabled so a
   question can't be sent twice. Errors (no key, 401, quota, network) show a Thai message
   in the chat and never affect the translation pipeline.
5. Each item keeps its chat for the session (switching items and back shows it again);
   "ล้างแชท" clears it. Saving chats to disk is not required.
6. No request is ever sent without the user pressing send / a quick question.
7. The key of the chat provider is read only when the chat is used, not at launch.

## Out of scope
- Voice, images, chat not tied to an item, saving chat history permanently.
- Changing how game text is translated.

## Constraints
- CLAUDE.md stability rules apply. Thai UI strings. Keys only in the Keychain; never logged.
- Game text in prompts is fine; don't write the chat into `GameTranslator.log` beyond one
  line per request (status, length) — no answers or keys.

## Files / Modules
- `Sources/Models/AppSettings.swift`, `Sources/Views/SettingsWindow.swift` (setting)
- `Sources/Services/` new chat service; `Sources/Providers/*` if multi-turn is added
- `Sources/Views/LearningView.swift` (+ chat view)
- `Tests/…`

## Acceptance Criteria
- **AC-1** [test] The chat prompt contains the original, the translation, the game title and
  only the glossary terms that appear in the text; history is trimmed to the last N turns.
- **AC-2** [test] The chat-provider setting defaults as in Req 1 and persists.
- **AC-3** [test] With no key for the chosen provider the service returns the Thai "ใส่ API
  key" error without sending a request (fake transport).
- **AC-4** [code] `LLMPrompt` translation path and `sanitize` behaviour unchanged; the chat
  provider key is not read at launch; no key in logs.
- **AC-5** [manual] Steps: choose Claude (or OpenAI) with a key, open a sentence →
  💬 ถาม AI → "ทำไมแปลแบบนี้?", then ask a follow-up. Expected: Thai answers that refer to the
  sentence and the previous answer.
- **AC-6** [manual] Steps: while an answer is loading press Stop; choose a provider without a
  key and ask. Expected: stops cleanly; Thai "ใส่ API key" message; translation of the game
  keeps running normally meanwhile.
- **AC-7** [build] Unit tests and Release build succeed.

## Testing Requirements
- Unit tests for AC-1 … AC-3 with a fake provider / transport.

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
