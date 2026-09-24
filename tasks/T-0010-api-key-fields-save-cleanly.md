# T-0010 — API key fields must save cleanly: trimmed, not on every keystroke, no session leak

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
  > Amended 2026-09-24 (Cowork, review): also met by one shared `URLSession` per provider type, so rebuilding a provider creates no new session. Invalidation was dropped because a request started on an invalidated session raises an uncaught NSException (Claude Code tested it); that would break stability rule 2.
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

- **Trimming (Req 1):** new `APIKeyInput` in `AppSettings.swift`:
  - `normalized(_:)` trims whitespace and newlines, so an all-whitespace key becomes `""`.
  - `valueToSave(draft:current:)` returns the trimmed draft, or nil if it wouldn't
    change the stored key.
  - The Settings field only ever saves trimmed values. `loadApiKey` also trims keys
    read from the Keychain or migrated from UserDefaults, so a key saved with a
    trailing space by an older version is used trimmed, and gets rewritten trimmed
    on the next save.
- **Not per keystroke (Req 2):** the four `SecureField`s are now an `APIKeyField`
  (private SwiftUI view in `SettingsWindow.swift`). It edits a local `draft`. It saves
  (Keychain write once + `pipeline.updateProvider()` once) on:
  - Return, or the field losing focus
  - the field disappearing: Settings window closed, or another provider picked
  - a **1 s pause** in typing

  Why the pause as well: closing a window doesn't reliably deliver focus-loss or
  `onDisappear` to SwiftUI on every macOS version. With the pause, a typed key is
  saved within 1 s even if the window is then closed, so closing can't lose it.
  Unchanged values are not saved again. If the Keychain value arrives after the
  field appeared, the draft follows it unless the user is typing.
- **Sessions (Req 3) — deviation from AC-3's example, please confirm:** I tested
  invalidating a `URLSession` and then calling `data(for:)` on it (small Swift
  program). Result: **the process crashes** (`libc++abi: terminating due to uncaught
  exception of type NSException`) instead of throwing. A request can still start on
  the old provider after a switch — e.g. T-0008's per-line fallback after the batch —
  so `finishTasksAndInvalidate()` on switch could crash the app (stability rule 2).
  Instead, each provider type keeps **one `static` shared session** (same
  configuration as before). Rebuilding a provider no longer creates a session, so the
  number of live sessions stays at ≤ 5 (one per provider type ever used) and nothing
  needs invalidating. `GoogleFreeProvider(configuration:)` still creates its own
  session, for tests only.
- **Provider picker (Req 4):** unchanged — `onChange(of: selectedProvider)` still calls
  `updateProvider()` immediately.
- Keys stay Keychain-only; lazy loading of only the selected provider's key is untouched.

## Result

**Outcome:** PARTIAL — `[test]`/`[build]` pass; AC-2 passes; AC-3 met by an alternative (see notes, Cowork to confirm); AC-4 pending owner
**Version:** 1.11.19 → 1.11.20
**Commit:** `0f15d05`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `APIKeyInputTests` (5 tests): `"  sk-abc \n"` → `"sk-abc"`, whitespace-only → `""`, save decisions. |
| AC-2 | ✅ pass | `SettingsWindow.swift`: no `onChange(of: settings.<key>)` → `updateProvider()` any more; `APIKeyField` saves on submit / focus loss / disappear / 1 s pause; a window close after typing can't lose the key (pause-save). |
| AC-3 | ⚠️ alternative | No per-instance session left to invalidate: each provider type uses one static session, so sessions no longer accumulate. Invalidation was rejected because a request on an invalidated session crashes the app (tested). |
| AC-4 | ⏳ pending owner | Steps below. |
| AC-5 | ✅ pass | `Executed 83 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 83 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                        |  2 +-
 Sources/Models/AppSettings.swift            | APIKeyInput + trimmed loads
 Sources/Views/SettingsWindow.swift          | APIKeyField, 4 fields use it
 Sources/Providers/{OpenAI,Claude,DeepL,GoogleCloud,GoogleFree}Provider.swift | shared session
 Tests/APIKeyInputTests.swift                | (new, 5 tests)
```

### Manual checks for the owner
**AC-4** — after `./build.sh`:
1. Settings → Claude Haiku → paste your real key **with a trailing space**, close
   Settings right away.
2. Translate a game. Expected: translations appear (no `HTTP 401` in the menu/log).
3. Reopen Settings → Claude Haiku: the key is still there.
Also: typing a key character by character should not make the log show a provider
change per character.

### Proposed follow-ups
- none

---

## Review

**Cowork, 2026-09-24 — code review passed; waiting for owner's AC-4.**

| AC | Verdict | Note |
|---|---|---|
| AC-1 | ✅ | `APIKeyInput.normalized` + 5 tests. Keys loaded from Keychain / UserDefaults are trimmed too, which is a good extra. |
| AC-2 | ✅ | `APIKeyField` edits a local draft and saves on Return, focus loss, disappear, or a 1 s pause. `valueToSave` skips a save when nothing changed, so `onAppear`/`onChange(key)` don't loop. |
| AC-3 | ✅ (alternative accepted) | Shared static session per provider type. Invalidating would crash an in-flight request on the old provider (T-0008 per-line fallback), so accepting the alternative is the right call. Spec amended. At most 5 sessions exist. |
| AC-4 | ⏳ owner | |
| AC-5 | ✅ | 83 tests. |

- Note, no action: the 1 s pause can save a half-typed key while the user types by hand. That costs one warm-up request, and while running it can hit a 401 → pause (T-0012) until the full key is saved. That's acceptable. The race it can trigger is covered by T-0014.

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → READY | Cowork | created for M3 |
| 2026-09-24 | READY → IN_PROGRESS | Claude Code | started (owner: do T-0010…T-0013, review after) |
| 2026-09-24 | IN_PROGRESS → REVIEW | Claude Code | AC-3 met by shared sessions instead of invalidation (crash risk) — Cowork to confirm; AC-4 manual |
| 2026-09-24 | — | Cowork | code review passed; AC-3 alternative accepted (spec amended); waiting for owner AC-4 |
