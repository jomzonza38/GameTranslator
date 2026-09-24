# T-0011 — Cached translations must belong to the provider and language that made them

| Field | Value |
|---|---|
| **Status** | REVIEW |
| **Type** | fix |
| **Priority** | P2 |
| **Version impact** | patch |
| **Milestone** | M3 — Providers & settings hygiene |
| **Depends on** | — |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-24 by Cowork (code audit v1.11.11 backlog + owner testing) |

## Objective
After switching translation provider (or source language) the user must see the new
provider's translations, not old cached ones. And when an LLM answers with chatter
and the app falls back to showing the source text, that fallback must not be cached
as if it were a translation.

## Context
- `TranslationService` keeps one `TranslationCache` keyed by the original text only
  (`cache.set(text, translation:, provider:)` stores the provider name but `get(text)`
  ignores it). Switching provider → cached lines still show the old provider's result
  until the app restarts or the glossary changes.
- Per-region caches in `RegionPipelineState.cachedTranslations` / `staleTranslations`
  also keep old translations on screen.
- `LLMPrompt.sanitize(_:source:)` returns the **source text** when the reply looks like
  chatter; `TranslationService.translateBatch` then caches it and the pipeline records it
  as translated → never retried.
- Hint: either key the cache by (provider, source language, text) or clear caches on
  provider/language change — Claude Code decides; explain in notes.

## Requirements
1. After changing provider or source language (while running or not), the next
   translations on screen come from the new provider/language; nothing cached under the
   old one is shown for text that appears afterwards.
2. A result that is just the source text returned because the LLM reply was chatter is
   not stored in any cache and is retried later (with the normal per-text back-off, not
   every frame).
3. Glossary behaviour, stale-grace period and similar-text reuse keep working.

## Out of scope
- Persisting the cache to disk; cache size/LRU performance.

## Constraints
- CLAUDE.md stability rules apply.

## Files / Modules
- `Sources/Services/TranslationService.swift`, `Sources/Services/TranslationCache.swift`
- `Sources/Providers/LLMChatProvider.swift` (how chatter fallback is signalled)
- `Sources/Services/PipelineCoordinator.swift`, `RegionPipelineState.swift` if needed
- `Tests/TranslationCacheTests.swift`, `Tests/LLMPromptTests.swift` or new tests

## Acceptance Criteria
- **AC-1** [test] Cache lookup for provider B does not return a translation stored by provider A (or the caches are provably cleared on switch).
- **AC-2** [test] A chatter reply from a fake LLM is not cached; a second call asks the provider again.
- **AC-3** [code] Changing provider/source language while running also drops per-region on-screen translations so they are re-translated.
- **AC-4** [manual] Steps: 1) translate a game with Google Free, 2) switch to Claude Haiku in Settings while running. Expected: within a few seconds the visible lines change to the Claude translation.
- **AC-5** [build] Unit tests and Release build succeed.

## Testing Requirements
- AC-1, AC-2 unit tests; owner runs AC-4.

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

- **Choice for Req 1: key the cache *and* reset what's on screen.**
  - `TranslationService` cache entries are keyed by `provider name | source language
    code` + text, so a lookup never returns another provider's or language's
    translation — even when not running. Switching back to a previous provider still
    reuses its results. Clearing on every switch would throw that away.
  - On screen: `PipelineCoordinator` remembers the scope of its translations and checks
    it each frame, next to the glossary check. When it changes (Settings → provider or
    game language while running), it resets the per-region states (on-screen cache,
    stale cache, similar-text reuse, text tracker) and the recent-lines context. Visible
    text is then translated again by the new provider within about 2 frames (the
    stability gate needs one frame).
- **Chatter signal (Req 2):**
  - `LLMPrompt.translation(fromReply:source:)` returns `nil` for an empty or chatter
    reply. `sanitize` keeps its old contract (`?? source`), so existing callers and
    tests are unchanged.
  - New protocol method `translateBatchMarkingFallbacks(...) -> [String?]`: the default
    (Google, DeepL) wraps `translateBatch`; `LLMChatProvider` implements it and returns
    `nil` per chatter line. Its `translateBatch(context:)` still returns the source text
    for those lines (behaviour unchanged for other callers).
  - `TranslationService` uses the marking variant and **neither caches nor returns**
    `nil` lines.
  - In `translatePending`, a text with no translation now gets `failedAt = now`, so it
    is retried after the normal 3 s back-off instead of on every frame. It is not added
    to history/context and is logged `✗ No translation for "…" — will retry`. This also
    closes an older gap: previously any missing result was retried every frame.
- **Testability:** the cache + provider part of `translateBatch` became
  `static TranslationService.translateBatch(_:with:cache:sourceLanguage:targetLanguage:context:beforeRequest:)`
  (no `AppSettings`). The DeepL Free limit check is passed in as `beforeRequest`, so it
  still runs only when a request is needed.
- **Removed:** `TranslationService.translate(_:)` (single text). It had no callers and
  used the old unscoped cache key, so leaving it would have kept the bug reachable.
- **Req 3:** glossary exact matches (`contextBuilder.fixedTranslation`), glossary change
  handling, the stale grace period and similar-text reuse are unchanged. After a
  provider/language change they start empty for the new scope, which is intended.

## Result

**Outcome:** PARTIAL — all `[test]`/`[code]`/`[build]` criteria pass; AC-4 pending owner
**Version:** 1.11.20 → 1.11.21
**Commit:** `5beb3ad`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `TranslationServiceCacheTests`: `testCacheOfOneProviderIsNotUsedForAnother` (Claude gets its own request, not Google's cached line), `testSameProviderUsesItsCache`, `testCacheIsPerSourceLanguage`. |
| AC-2 | ✅ pass | `testChatterReplyIsNotCachedAndIsAskedAgain` (2 calls, nothing returned), `testChatterForOneLineOfABatchKeepsTheOthers` (other line cached), `testLLMTranslateBatchStillShowsSourceForChatter`. |
| AC-3 | ✅ pass | `PipelineCoordinator.applyTranslationScopeChangeIfNeeded()` (called at the start of every frame) resets `globalState`, every `regionStates` value and recent lines when `translationService.translationScope` changes. |
| AC-4 | ⏳ pending owner | Steps below. |
| AC-5 | ✅ pass | `Executed 89 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 89 tests, with 0 failures (0 unexpected) in 0.420 (0.466) seconds
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files (this task only, on top of T-0010)
```
 Resources/Info.plist                         | 1.11.21
 Sources/Providers/TranslationProvider.swift  | translateBatchMarkingFallbacks (+ default)
 Sources/Providers/LLMChatProvider.swift      | nil for chatter; LLMPrompt.translation(fromReply:)
 Sources/Services/TranslationService.swift    | scoped cache key, static testable batch, no caching of nil
 Sources/Services/PipelineCoordinator.swift   | scope-change reset; missing result → back-off
 Tests/TranslationServiceCacheTests.swift     | (new, 6 tests)
```

### Manual checks for the owner
**AC-4** — after `./build.sh`: translate a game with Google Free, then (still running)
Settings → Claude Haiku. Expected: within a few seconds the visible lines change to
Claude's translation; the log shows `Translation provider/language changed (Claude
Haiku|en) — re-translating on-screen text`. Switching back to Google Free shows the
Google lines again (from its cache, no delay).

### Proposed follow-ups
- none

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → READY | Cowork | created for M3 |
| 2026-09-24 | READY → IN_PROGRESS | Claude Code | started (stacked on T-0010, uncommitted — owner asked for all tasks before review) |
| 2026-09-24 | IN_PROGRESS → REVIEW | Claude Code | test/code/build ACs pass; AC-4 manual pending owner |
