# T-0025 — Ask the AI why a sentence was translated that way

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

- **Started while PLANNED** on the owner's instruction; stacked on T-0022/T-0023 (in REVIEW,
  uncommitted).
- **Setting (Req 1):** `AppSettings.learningChatProvider` (Claude Haiku 4.5 / OpenAI
  GPT-4o-mini), key `learningChatProvider`. Default = the translation provider if it is
  one of those, else Claude (`loadLearningChatProvider`, testable). Settings →
  **"AI สำหรับแชทเรียนรู้"** has the picker, **that provider's key field** (the API Keys section
  above only shows the translation provider's key), a status line "✓ มี API key ของ … แล้ว"
  / "ยังไม่มี API key … — ใส่ในช่องด้านบน", and what it's used for. T-0023's meaning lookup now
  prefers this provider (`MeaningService` default `chatProvider`).
- **Multi-turn without touching the providers:** `ChatPrompt.user` sends the context plus the
  recent conversation ("Student: … / Teacher: …", last 10 turns, notices excluded) inside
  one user message, through the existing `LLMChatProvider.complete`. `LLMPrompt` and
  `sanitize` are untouched (no diff under `Sources/Providers/` in this task — AC-4).
- **Prompt (Req 3, AC-1):**
  - system: friendly Thai language teacher for the game (title, source language); answer
    in Thai, and point out a wrong or weak game translation.
  - user: game line, the game's Thai translation (for a word: its meaning), **only the
    glossary terms that appear in the line** (`relevantGlossary`, case-insensitive), the
    trimmed history, then the question.
- **`LearningChatService`** (`@MainActor`; provider, key lookup and LLM factory are
  injectable):
  - one chat per item (sentence/word id) kept for the session (Req 5), "ล้างแชท" clears it.
  - `send` is ignored while an answer is loading (the send and quick-question buttons are
    disabled too — Req 4), and `stop()` cancels.
  - No key → the Thai notice "ยังไม่มี API key ของ … — ใส่ API key ได้ที่ ตั้งค่า → AI สำหรับแชทเรียนรู้"
    and **no request** (AC-3). Errors appear as Thai notices in the chat. It never touches
    the pipeline.
  - The key is read only when a question is sent (Req 7). Opening Settings reads the chosen
    provider's key to show its status (Req 1) — that's on the user's action, not at launch.
  - Log: one line per request and answer with **lengths only** — no text, no key.
- **UI (Req 2):** each detail pane (T-0023) ends with **"💬 ถาม AI"**, which opens the chat:
  - the four quick questions ("ทำไมแปลแบบนี้?", "แยกคำศัพท์ในประโยคนี้", "แปลแบบอื่นได้ไหม?",
    "ยกตัวอย่างประโยคอื่น")
  - the conversation (user / AI bubbles, notices in orange)
  - "AI กำลังตอบ…" with **หยุด**
  - a text box: Return sends, Shift-Return adds a new line (`onKeyPress`)
  - **ส่ง**, **ล้างแชท**
  - The chat opens again automatically when you come back to an item that has one.
- New file `Sources/Services/LearningChatService.swift`.

## Result

**Outcome:** PARTIAL — `[test]`/`[code]`/`[build]` criteria pass; AC-5 and AC-6 pending owner
**Version:** 1.13.0 → 1.14.0
**Commit:** `141cba0`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `ChatPromptTests.testPromptHasOriginalTranslationGameAndOnlyRelevantGlossary` (Bishop included, Graveyard not), `testHistoryIsTrimmedToTheLastTurnsWithoutNotices` (last 10, no notices). |
| AC-2 | ✅ pass | `testChatProviderDefaultAndPersistence` (translation LLM / else Claude / stored choice / non-LLM ignored). |
| AC-3 | ✅ pass | `LearningChatServiceTests.testNoKeyGivesThaiMessageWithoutARequest` (0 requests). Also the follow-up includes the history, chats per item, and a second question while waiting is ignored. |
| AC-4 | ✅ pass | No change under `Sources/Providers/`; key read in `send` only; log lines contain lengths only. |
| AC-5, AC-6 | ⏳ pending owner | Steps below. |
| AC-7 | ✅ pass | `Executed 182 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 182 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files (this task only, on top of T-0023)
```
 Resources/Info.plist                         | 1.14.0
 Sources/Services/LearningChatService.swift   | (new) ChatTurn, ChatPrompt, LearningChatService
 Sources/Models/AppSettings.swift             | learningChatProvider
 Sources/Views/SettingsWindow.swift           | "AI สำหรับแชทเรียนรู้" section
 Sources/Services/MeaningService.swift        | prefers the chat provider
 Sources/Views/LearningView.swift             | ChatPane in both detail panes
 Tests/LearningChatTests.swift                | (new, 6 tests)
```

### Manual checks for the owner
After `./build.sh`:
- **AC-5:** Settings → AI สำหรับแชทเรียนรู้ → Claude (or OpenAI) with a key → Learning → pick a
  sentence → **💬 ถาม AI** → "ทำไมแปลแบบนี้?" → a Thai answer about that line; then type a
  follow-up (Return) → the answer refers to the previous one.
- **AC-6:** ask something and press **หยุด** while it loads → stops cleanly. Choose a
  provider without a key and ask → Thai "ยังไม่มี API key …" message, nothing sent. The game
  keeps being translated normally meanwhile.

### Proposed follow-ups
- none

---

## Review

**2026-09-24 — Cowork audit review: DONE**

- AC-1…AC-4, AC-7 ✅ (ChatPromptTests / LearningChatServiceTests; providers and `LLMPrompt` untouched; log lines carry lengths only). AC-5, AC-6 ✅ owner confirmed 2026-09-24.
- Findings: chat uses the current source-language setting (→ T-0026). Low (backlog): editing the key in "AI สำหรับแชทเรียนรู้" calls `pipeline.updateProvider()` even when it isn't the translation provider's key (re-translates the screen / lifts a pause for no reason); a word's chat sends the word as "Game line" without its example sentence.
- Changed files match *Files / Modules* (AppDelegate quit-save in T-0022 justified in notes). Stability rules: no new permission/capture API, pipeline change limited to one call.

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → PLANNED | Cowork | created; READY when T-0022 is DONE |
| 2026-09-24 | PLANNED → IN_PROGRESS | Claude Code | started on the owner's instruction ("do all of M6") while T-0022 is in REVIEW; stacked, uncommitted |
| 2026-09-24 | IN_PROGRESS → REVIEW | Claude Code | test/code/build ACs pass; AC-5, AC-6 manual pending owner |
| 2026-09-24 | REVIEW → DONE | Cowork | audit review; owner confirmed manual checks; follow-ups → T-0026 + backlog |
