# T-0010 — API key fields must save cleanly: trimmed, not on every keystroke, no session leak

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
Typing or pasting an API key in Settings must store exactly the key (no stray
spaces/newlines) and must not do heavy work on every keystroke. Today a pasted key
with a trailing space fails with HTTP 401, and each typed character writes the
Keychain, builds a new provider with a new `URLSession` that is never released,
and fires a warm-up request.

## Context
- `Sources/Views/SettingsWindow.swift` (API Keys section): every `SecureField` has
  `.onChange { pipeline.updateProvider() }`; the `@Published` key's `didSet` in
  `AppSettings` calls `KeychainStore.set` (one Keychain write per character).
- `TranslationService.switchProvider` creates a new provider (each owns a
  `URLSession`) and calls `warmUp()`; the old session is never invalidated →
  sessions accumulate for the app's lifetime.
- Keys are stored as typed; nothing trims whitespace or newlines.
- Keys must stay in the Keychain only (standing rule). Reading keys lazily
  (only the selected provider's key at launch) must be preserved.

## Requirements
1. The stored key (Keychain) and the key the provider uses have leading/trailing
   whitespace and newlines removed.
2. Typing a key does not write the Keychain or rebuild the provider per keystroke —
   it is applied once the user finishes (e.g. on submit, focus loss, or after a short
   pause; Claude Code chooses and records why). Closing the Settings window must not
   lose a key that was typed.
3. Replacing a provider releases the previous one's network session (no growing
   number of live `URLSession`s).
4. Switching provider in the picker still applies immediately.

## Out of scope
- Validating keys against the service ("test key" button) — possible later task.
- Pausing after auth errors (T-0012).

## Constraints
- CLAUDE.md stability rules apply; keys only in the Keychain; no extra Keychain
  access prompts at launch.

## Files / Modules
- `Sources/Views/SettingsWindow.swift`, `Sources/Models/AppSettings.swift`
- `Sources/Services/TranslationService.swift`, `Sources/Providers/*` (session release)
- `Tests/…`

## Acceptance Criteria
- **AC-1** [test] Key normalisation: `"  sk-abc \n"` is stored/used as `"sk-abc"`; an all-whitespace key counts as empty.
- **AC-2** [code] No Keychain write or provider rebuild per keystroke; the typed key is applied when editing ends (and not lost when the window closes).
- **AC-3** [code] Switching provider invalidates the previous provider's `URLSession` (e.g. `finishTasksAndInvalidate`).
- **AC-4** [manual] Steps: 1) Settings → Claude Haiku, paste your real key with a trailing space, close Settings. 2) Translate a game. Expected: translations appear (no HTTP 401). 3) Reopen Settings: key is still there.
- **AC-5** [build] Unit tests and Release build succeed.

## Testing Requirements
- Unit test for AC-1. Owner runs AC-4.

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
