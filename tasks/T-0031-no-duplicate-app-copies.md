# T-0031 — Only the installed app shows up in Spotlight / Apps, never build copies

| Field | Value |
|---|---|
| **Status** | DONE |
| **Type** | fix |
| **Priority** | P2 (normal) |
| **Version impact** | none (build scripts / docs only) |
| **Milestone** | — |
| **Depends on** | — |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-26 by Cowork |

## Objective
Searching "GameTranslator" in Spotlight / the Apps list must show exactly one app: the one `./build.sh`
installed. Today every task leaves extra copies, and opening the wrong one is an ad-hoc-signed build —
which can bring back the Screen Recording prompt and costs the ~74 s Vision recompile (stability rule 1, T-0017).

## Context
- Owner's screenshot 2026-09-26: Spotlight "ga" shows **three** GameTranslator apps.
- Found in the repo (2026-09-26): `build/Build/Products/Debug/GameTranslator.app` (01:50, 1.16.1) and
  `build/Build/Products/Release/GameTranslator.app` (15:38 on 09-25, 1.16.1) — both from the **Verify**
  step (`xcodebuild test` → Debug, `xcodebuild build -configuration Release` → Release). Third = the
  installed copy in /Applications (or ~/Applications).
- `build.sh` removes only its own Release product and writes `build/.metadata_never_index` — macOS only
  honours that file at a volume root, so it has no effect in `build/`. Verify never removes anything.
- Unit tests launch the Debug app as test host, so Launch Services registers it even if Spotlight
  didn't index the folder.
- Also possible: products in `~/Library/Developer/Xcode/DerivedData/GameTranslator-*` if the project was
  ever built from the Xcode IDE (not reachable from Cowork — owner to check).
- Hint: Spotlight skips folders whose name ends in **`.noindex`** (Xcode itself uses `*.noindex`), e.g.
  `-derivedDataPath build.noindex`; Launch Services entries can be removed with
  `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u <app>`.

## Requirements
1. After Verify (tests + Release build) and after `./build.sh`, Spotlight / Apps shows only the installed app.
2. Verify and CI still produce what they need (test host, Release build log; CI still uploads the .app artifact).
3. `build.sh` still installs, signs and launches exactly as today (same bundle ID, same signing, same
   install path) — stability rule 1.
4. Old leftovers are cleaned once: the two copies in `build/Build/Products`, their Launch Services entries.
5. `CLAUDE.md` Verify commands and `.gitignore` match the new layout.

## Out of scope
- The `rm -rf` + copy / `codesign --deep` question in `build.sh` (separate backlog item).

## Constraints
- CLAUDE.md stability rules apply. Never touch the installed copy's signature or TCC entries.

## Files / Modules
- `build.sh`, `CLAUDE.md` (Verify), `.github/workflows/build.yml`, `.gitignore`

## Acceptance Criteria
- **AC-1** [code] Verify/build.sh/CI use one derived-data folder Spotlight does not index; no build
  product `.app` stays registered with Launch Services after Verify or build.sh.
- **AC-2** [code] Install, signing and launch steps of `build.sh` unchanged.
- **AC-3** [build] Verify (tests + Release build) succeeds with the new commands.
- **AC-4** [manual] Owner: run Verify, then `./build.sh`, then Spotlight "GameTranslator" → exactly one
  result, and it is the one in /Applications (⌘-click / "Show in Finder"). No Screen Recording prompt.

## Definition of Done
- [ ] All acceptance criteria pass (`[manual]` ones confirmed by the owner)
- [ ] Full test suite passes; Release build succeeds
- [ ] Version: none (scripts/docs only)
- [ ] `git diff` contains only changes justified by this task
- [ ] Result section complete; Cowork review passed

---

## Questions

## Implementation Notes
- **One derived-data folder: `build.noindex/`** for Verify (CLAUDE.md), `build.sh` and CI. Spotlight skips
  `*.noindex` folders (checked: `mdfind` finds no app under `build.noindex/` after the Release build).
- **Launch Services.** Running the tests launches the Debug app as test host, and Launch Services
  registers both products even without Spotlight (seen in `lsregister -dump` right after Verify). So:
  - Verify (CLAUDE.md) got a last step: `lsregister -u` for every `build.noindex/Build/Products/*/GameTranslator.app`.
  - `build.sh`: after copying to /Applications it runs the same unregister step (`unregister_build_copies`:
    only paths under `build.noindex/` and the old `build/` — never the installed app), then deletes
    the Release product (as before) and any app copy left in the old `build/` folder. The useless
    `touch build/.metadata_never_index` is gone (only honoured at a volume root).
  - Install, signing, verification, quarantine, kill and launch steps are unchanged (AC-2); only the
    `-derivedDataPath` and the source path of `cp -R` changed. `build.sh` itself was **not run** here
    (it replaces the installed app) — `bash -n build.sh` passes; AC-4 runs it.
- **CI:** `-derivedDataPath build.noindex`, logs in `build.noindex/*.log`, artifact
  `build.noindex/Build/Products/Release/GameTranslator.app` — same outputs, new folder. (CI runs on
  `main`/PRs only, so this is first exercised when `develop` is merged or a PR is opened.)
- **`.gitignore`:** `build.noindex/` added; `build/` kept for the old folder.
- **One-time cleanup (Req 4), 2026-09-26:** the two copies in `build/Build/Products/{Debug,Release}` had
  already been removed (moved to the Trash at 09:03, before this task started). Registered with Launch
  Services were still: `~/.Trash/GameTranslator.app`, `~/.Trash/GameTranslator 09.03.38.app` and an
  old Claude Code scratchpad build `/private/tmp/claude-501/…/29123007-…/scratchpad/dd/…/Release/GameTranslator.app`.
  All three unregistered with `lsregister -u`. After that: `lsregister -dump` and `mdfind` for bundle ID
  `com.worawalan.GameTranslator` → only `/Applications/GameTranslator.app`. The installed copy, its
  signature and TCC entries were not touched.
- Not removed: the old `build/` folder (430 MB, no app inside any more — only caches/logs) and
  `~/Library/Developer/Xcode/DerivedData/GameTranslator-*` (no Products folder). Both can be deleted by
  the owner any time; nothing uses them now.
- For Cowork: build/test evidence is now under `build.noindex/Logs/` (was `build/Logs/`).

## Result

**Outcome:** PARTIAL — `[code]`/`[build]` criteria pass; AC-4 pending owner
**Version:** none (scripts/docs only) — stays 1.16.1
**Commit:** `3ae8e0f`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `build.sh`, CLAUDE.md Verify and `build.yml` all use `-derivedDataPath build.noindex`. Verify run: `lsregister -dump` listed `build.noindex/…/Debug` and `…/Release` after the build and neither after the unregister step. `build.sh` unregisters + deletes its products after install. |
| AC-2 | ✅ pass | `git diff build.sh`: only `DERIVED_DATA`/`APP_PATH`, the unregister function and the clean-up block changed; `cp -R`, `codesign`, verification, `xattr`, `killall`, `open` untouched. |
| AC-3 | ✅ pass | New Verify commands: see below. |
| AC-4 | ⏳ pending owner | Steps below. |

### Build & test
```
Executed 230 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 build.sh                    | build.noindex, unregister build copies, remove useless .metadata_never_index
 CLAUDE.md                   | Verify uses build.noindex + lsregister -u step; note why
 .github/workflows/build.yml | build.noindex for derived data, logs and the uploaded .app
 .gitignore                  | build.noindex/
```

### Manual checks for the owner
**AC-4** — in the repo: run the Verify commands from CLAUDE.md (all four steps), then `./build.sh`.
Then Spotlight (⌘Space) "GameTranslator" → exactly **one** app; ⌘-click it (or "Show in Finder") → it is
`/Applications/GameTranslator.app`. It launches without a Screen Recording prompt. Optional: empty the
Trash (two old copies are there) and delete the old `build/` folder — neither is used any more.

### Proposed follow-ups
- none

---

## Review
**Cowork code review, 2026-09-26 — code passes; waiting for the owner's AC-4 (manual).**
Evidence: `build.noindex/Logs/Test` 2026-09-26 09:05 (230 tests, 0 failures); diff read in full.

| AC | Verdict | Note |
|---|---|---|
| AC-1 | ✅ | Verify, `build.sh`, CI all on `build.noindex`; Verify ends with `lsregister -u`; `build.sh` unregisters then deletes its products. Globs with no match are guarded (`[ -d ]`, `rm -rf` of a literal is harmless). |
| AC-2 | ✅ | Only `-derivedDataPath`, `APP_PATH` (source of `cp -R`) and the clean-up block changed; `cp`/`codesign`/verify/`xattr`/`killall`/`open` untouched, `lsregister -u` only on build paths — never /Applications. |
| AC-3 | ✅ | New Verify commands ran (evidence above). |
| AC-4 | ⏳ | Owner: Verify → `./build.sh` → Spotlight shows one app = /Applications, no Screen Recording prompt. |

Notes (no change needed):
- The Debug test host stays on disk in `build.noindex/` (Spotlight skips it; unregistered after Verify).
  Anyone running only `xcodebuild test` without the last Verify step registers it again — CLAUDE.md
  now says why the step matters.
- The one-time clean-up touched the owner's Launch Services database (Trash + old /tmp scratch copies):
  in scope (Req 4), unregister only, nothing deleted outside the repo.
- Old `build/` (430 MB caches) and `~/Library/Developer/Xcode/DerivedData/GameTranslator-*` can be deleted
  by the owner; nothing uses them now.

Decision: DONE once AC-4 is confirmed.

**2026-09-26 — owner confirmed AC-4** ("แอพไม่สร้างเพิ่มแล้ว": one app after Verify + build.sh). **DONE.**

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-26 | → READY | Cowork | from owner's report: 3 GameTranslator apps in Spotlight |
| 2026-09-26 | READY → IN_PROGRESS | Claude Code | started |
| 2026-09-26 | IN_PROGRESS → REVIEW | Claude Code | code/build ACs pass; AC-4 manual pending owner |
| 2026-09-26 | — | Cowork | code review passed; waiting for owner manual AC-4 |
| 2026-09-26 | REVIEW → DONE | Cowork | owner confirmed AC-4 |
