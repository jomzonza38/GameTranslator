# T-0012 — Stop retrying while the API key is refused, and say so

| Field | Value |
|---|---|
| **Status** | REVIEW |
| **Type** | fix |
| **Priority** | P2 |
| **Version impact** | patch |
| **Milestone** | M3 — Providers & settings hygiene |
| **Depends on** | T-0010 |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-24 by Cowork (code audit v1.11.11 backlog + owner testing) |

## Objective
When the provider refuses the API key (HTTP 401/403, missing key) or the quota is used
up, the app must stop sending requests and tell the user what to fix, instead of
retrying every ~3 s for as long as text is on screen.

## Context
- Seen in the owner's test 2026-09-24 00:10: invalid Claude key → `✗ Translation error:
  … HTTP 401 …` every ~3.4 s, indefinitely (`PipelineCoordinator.retryDelay = 3`,
  per-text `failedAt` back-off).
- Errors are shown in the menu since T-0006 (`lastError`). T-0008 already stops
  per-line fallback on these errors; `BatchFallback.shouldRetryPerLine` classifies them.
- Depends on T-0010 because that task changes when/how a new key is applied, which is
  the natural "retry now" signal.

## Requirements
1. After an auth error (401/403 / `missingApiKey`) or quota error, translation requests
   pause: no further requests until the key or provider changes (or the user stops and
   starts again).
2. While paused, the menu shows a Thai message saying the key was refused / quota used
   up and which provider (Claude Code picks wording); capture and overlay stay as they are.
3. Saving a new key or switching provider resumes translation automatically.
4. Rate limits (429) and network errors keep the current back-off (not paused).

## Out of scope
- Automatic key validation in Settings; notifications outside the menu.

## Constraints
- CLAUDE.md stability rules apply.

## Files / Modules
- `Sources/Services/PipelineCoordinator.swift`, `Sources/Services/TranslationService.swift`
- `Sources/Providers/LLMChatProvider.swift` (`BatchFallback`) if the classification is reused
- `Tests/…`

## Acceptance Criteria
- **AC-1** [test] The pause decision: 401/403/missing key/quota → pause; 429, timeout, 5xx → no pause.
- **AC-2** [code] While paused no provider request is made; key or provider change clears the pause.
- **AC-3** [manual] Steps: 1) set an invalid Claude key, translate a game for 30 s. Expected: log shows one (or very few) 401 lines, not one every 3 s; menu shows the Thai message. 2) Enter the real key. Expected: translation resumes without restarting.
- **AC-4** [build] Unit tests and Release build succeed.

## Testing Requirements
- AC-1 unit test; owner runs AC-3.

## Definition of Done
- [ ] All acceptance criteria pass (`[manual]` ones confirmed by the owner)
- [ ] Unit tests added/updated as required; full suite passes
- [ ] Release build succeeds
- [ ] Version bumped per CLAUDE.md
- [ ] `git diff` contains only changes justified by this task
- [ ] Result section complete; Cowork review passed

---

## Questions

## Implementation Notes

- **Started while PLANNED** on the owner's instruction ("do all tasks, review after").
  It builds on T-0010, which is in REVIEW and uncommitted, not DONE.
- **Pause decision (Req 1, Req 4):** new `TranslationRefusal` in
  `LLMChatProvider.swift`, next to `BatchFallback`:
  - `kind(of:)` → `.keyRefused` for `missingApiKey` and `HTTP 401`/`HTTP 403` messages
    (Google Cloud and DeepL already map 401/403 to `missingApiKey`); `.quotaUsedUp` for
    `quotaExceeded` (DeepL 456, the DeepL Free monthly limit).
  - Everything else — 429, network errors, timeouts, 5xx, invalid replies,
    cancellation — returns `nil`, so the existing 3 s per-text back-off still applies.
  - `BatchFallback` is unchanged. I didn't make it call the new type: its own list
    already rejects the same errors, and leaving it alone keeps T-0008 behaviour exact.
- **Pipeline (AC-2):** `PipelineCoordinator.isTranslationPaused`.
  - Set in `translatePending`'s `catch` when `pauseMessage(...)` is non-nil. `lastError`
    becomes the Thai message and the log says `⏸ Translation paused…`.
  - While paused, `translatePending` returns **before** any request (after collecting
    texts). Capture, OCR, glossary exact matches and already-cached lines keep working,
    so the overlay stays as it is (Req 2).
- **Resume (Req 3):** `updateProvider()` clears the pause, the error and the per-text
  `failedAt` back-off, so the new key is tried at once, and logs `▶︎ Translation
  resumed`. Settings calls it when the provider is picked and when a key is saved
  (T-0010: once, when editing ends). A new start also clears the pause.
- **Menu text (Req 2)**, shown as `⚠️ …` (menu refreshes on open, T-0006):
  - key: `หยุดแปลชั่วคราว: <provider> ไม่รับ API Key — แก้ Key ใน ⚙️ ตั้งค่า แล้วจะแปลต่อเอง`
  - quota: `หยุดแปลชั่วคราว: <provider> ใช้โควต้าหมดแล้ว — เปลี่ยน provider ใน ⚙️ ตั้งค่า แล้วจะแปลต่อเอง`
  - Google Free (no key) 403: `หยุดแปลชั่วคราว: Google Translate (Free) ปฏิเสธคำขอ — ลองเปลี่ยน provider ใน ⚙️ ตั้งค่า`

## Result

**Outcome:** PARTIAL — all `[test]`/`[code]`/`[build]` criteria pass; AC-3 pending owner
**Version:** 1.11.21 → 1.11.22
**Commit:** `2cd55eb`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `TranslationRefusalTests`: 401/403/missing key/quota → pause; 429, 500, 503, timeout, offline, invalid response, cancel → no pause; message texts. |
| AC-2 | ✅ pass | `translatePending`: `guard !isTranslationPaused else { return }` before the only `translationService.translateBatch` call; `updateProvider()` clears the pause. |
| AC-3 | ⏳ pending owner | Steps below. |
| AC-4 | ✅ pass | `Executed 92 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 92 tests, with 0 failures (0 unexpected) in 0.733 (0.778) seconds
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files (this task only, on top of T-0011)
```
 Resources/Info.plist                        | 1.11.22
 Sources/Providers/LLMChatProvider.swift     | TranslationRefusal
 Sources/Services/TranslationService.swift   | currentProviderUsesApiKey
 Sources/Services/PipelineCoordinator.swift  | pause on refusal, resume in updateProvider
 Tests/TranslationRefusalTests.swift         | (new, 3 tests)
```

### Manual checks for the owner
**AC-3** — after `./build.sh`:
1. Settings → Claude Haiku → key `sk-test` (press Return). Translate a game for 30 s.
   Expected: the log has **one** `HTTP 401` line followed by `⏸ Translation paused…`,
   not one every 3 s. The menu shows `⚠️ หยุดแปลชั่วคราว: Claude Haiku ไม่รับ API Key — …`.
2. Enter the real key (Return or wait 1 s). Expected: log `▶︎ Translation resumed`,
   translations appear without restarting, and the ⚠️ line is gone.

### Proposed follow-ups
- none

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → PLANNED | Cowork | created for M3; READY when T-0010 is DONE |
| 2026-09-24 | PLANNED → IN_PROGRESS | Claude Code | started on owner's instruction ("do all tasks, review after") while T-0010 is still in REVIEW; stacked on T-0010/T-0011, uncommitted |
| 2026-09-24 | IN_PROGRESS → REVIEW | Claude Code | test/code/build ACs pass; AC-3 manual pending owner |
