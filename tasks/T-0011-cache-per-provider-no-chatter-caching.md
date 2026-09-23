# T-0011 — Cached translations must belong to the provider and language that made them

| Field | Value |
|---|---|
| **Status** | READY |
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

## Result

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → READY | Cowork | created for M3 |
