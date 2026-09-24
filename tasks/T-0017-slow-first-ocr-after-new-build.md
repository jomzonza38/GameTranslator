# T-0017 — Find out why the first OCR after a new build takes ~74 s

| Field | Value |
|---|---|
| **Status** | REVIEW |
| **Type** | investigation |
| **Priority** | P2 |
| **Version impact** | none (patch if code changes) |
| **Milestone** | M4 — Performance & first use |
| **Depends on** | — |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-24 by Cowork (owner's logs) |

## Objective
After installing a new build, the first translation session shows nothing for
**over a minute**. Find the cause and either fix it or make the wait visible to the user.

## Context
- Owner's log 2026-09-24, both times the first capture after launching a freshly built app:
  - v1.11.24: start 09:32:42 → `09:33:56 OCR [Region 1]: 0 texts in 74039ms`
  - v1.11.25: start 09:59:30 → `10:00:44 OCR [Region 1]: 1 texts in 73652ms`
  Later OCR runs take 25–150 ms. A second start in the same launch was fast.
- The `sample` from T-0015's review shows `ANEServicesThread` threads. Hint (unverified):
  Vision's text recognizer may compile its Neural Engine model on first use, and the
  compiled cache may be tied to the app build/signature. That would explain why it
  happens after every rebuild but may not affect a normally installed app.
- Unknown: does it also happen on the first launch after a reboot without rebuilding?
  Does it depend on OCR Fast vs Accurate or on the recognition languages?

## Requirements
1. Report the cause, with evidence (timings, conditions under which it does and doesn't happen).
2. If it can be avoided or shortened (e.g. warming Vision up at launch in the
   background), do it. Otherwise show a Thai status in the menu/panel
   (e.g. "กำลังเตรียม OCR ครั้งแรก…") while the first OCR is running.
3. No new crash or freeze paths; launch stays responsive.

## Out of scope
- General OCR speed after warm-up. CPU while idle (T-0016).

## Constraints
- CLAUDE.md stability rules apply.

## Files / Modules
- `Sources/Services/OCRService.swift`, `Sources/App/AppDelegate.swift` (warm-up), menu/panel status if needed

## Acceptance Criteria
- **AC-1** [code] Implementation Notes record the cause, with measurements, and which conditions reproduce it.
- **AC-2** [manual] Steps: `./build.sh`, start translating a window with text right away. Expected: text translated within ~5 s of start, **or** the Thai "preparing OCR" status is visible until it is.
- **AC-3** [build] Unit tests and Release build succeed.

## Testing Requirements
- Owner runs AC-2 after a fresh build.

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

### Cause (AC-1) — measured
Vision compiles its text-recognition model for the Apple Neural Engine on first use
and caches it per app bundle ID and macOS build in
`~/Library/Caches/com.worawalan.GameTranslator/com.apple.e5rt.e5bundlecache/26A428/…`.
Each entry is a small `.bundle` that points at the compiled program
(`model.anehash`). **The cache is only valid for the code-signing identity that
compiled it.** Switching identity forces a full recompile (~74 s). A new binary with
the same identity does not.

Experiments (same bundle ID, `OCRServiceTests` = real Vision OCR as the probe, time
of the first recognition):

| # | Build | Signed with | First OCR |
|---|---|---|---|
| E1 | current code | ad-hoc (after an ad-hoc run) | 0.10 s, run 2: 0.08 s |
| E2 | **new binary** (new CDHash) | ad-hoc | **0.10 s** — a new build alone is not the cause |
| E3 | same code | **Apple Development cert** | **73.5 s** (+ `mdb_txn_commit error: MDB_MAP_FULL` at the same moment); run 2: 0.08 s |
| E5 | **new binary** | same Apple Development cert | **0.11 s** — like a normal `build.sh` rebuild |
| E4 | same code | back to **ad-hoc** | **~76 s** wall time for 3 tests (normally ~7 s) |

- The bundles' timestamps confirm it: all three were rewritten at 10:24:57–10:25:36,
  during the T-0016 test run (the owner's cert-signed app had used the cache at 10:17).
- **Why the owner saw it "after every new build":** in this workflow, every build is
  followed by Claude Code's Verify step. Verify runs the unit tests in an **ad-hoc**
  build with the same bundle ID, so the owner's next launch of the cert-signed app
  finds a cache made by the other identity. This matches the timeline: slow app starts
  at 09:32 and 09:59 came right after my test runs; my slow test runs (T-0010, T-0015,
  T-0016) came right after the owner had run the app.
- **When it does *not* happen:** a new `./build.sh` build when nothing ad-hoc with this
  bundle ID ran in between (E5); a second start in the same launch.
- **Other expected triggers (not reproduced here):** a macOS update (the cache folder is
  named after the OS build, `26A428`); a cleared `~/Library/Caches`.
- **Not determined:** whether Fast and Accurate share one compiled model (the probe
  used Accurate; the cache holds 3 bundles). The warm-up below uses the user's
  current setting, so either way the model the user needs is prepared.
- `MDB_MAP_FULL` is a system framework's LMDB database logging while it recompiles.
  It shows up with every recompile; I haven't shown it's a cause.

### Fix (Req 2)
- **Warm-up at launch:** `OCRService.warmUp(recognitionLevel:languages:)` runs one
  recognition on a blank 64×32 image on a background queue (utility QoS) right after
  the menu bar item is created. It uses the user's current OCR level and languages.
  With a valid cache it costs ~0.1 s; after an identity switch or a macOS update the
  ~74 s compile happens in the background, usually before the user starts translating.
  It is logged: `OCR warm-up done in X s` (+ an explanation if > 5 s). Launch stays
  responsive: nothing waits on it (Req 3).
- **Status while the first OCR is still running** (the user started before the warm-up
  finished): `OCRService.isVisionReady` becomes true after the first recognition
  (warm-up or real). Until then, each pipeline run sets `PipelineStatus.preparingOCR`,
  so the menu shows `สถานะ: กำลังเตรียม OCR ครั้งแรก… (อาจนานถึง ~1 นาที)`. The panel's
  empty state shows the same text instead of `กำลังรอข้อความ...`. It switches back to
  `กำลังทำงาน` when the OCR returns.
- Unit tests: `OCRServiceTests.testVisionIsReadyAfterARecognition`,
  `testPreparingStatusIsThai`.
- **CLAUDE.md** (*macOS gotchas*) now records the finding.

## Result

**Outcome:** PARTIAL — AC-1 and AC-3 pass; AC-2 pending owner
**Version:** 1.11.26 → 1.11.27
**Commit:** not committed (owner asked for T-0016 and T-0017 first, review after)

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | Cause, the experiment table (E1–E5) and trigger conditions above. |
| AC-2 | ⏳ pending owner | Steps below. |
| AC-3 | ✅ pass | `Executed 117 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 117 tests, with 0 failures (0 unexpected) in 0.642 (0.699) seconds
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                              | 1.11.27
 Sources/Services/OCRService.swift                 | warmUp, isVisionReady
 Sources/App/AppDelegate.swift                     | start warm-up at launch
 Sources/Models/PipelineTypes.swift                | PipelineStatus.preparingOCR (Thai)
 Sources/Services/PipelineCoordinator.swift        | preparing status around the first OCR
 Sources/Overlay/TranslationPanelController.swift  | panel "preparing OCR" text
 Tests/OCRServiceTests.swift                       | +2 tests
 CLAUDE.md                                         | gotcha: OCR model cache per signing identity
```

### Manual checks for the owner
**AC-2** — the tests I just ran were ad-hoc, so **your next launch will hit the slow
case** (a good moment to check):
1. `./build.sh`. The log should show `OCR warm-up done in ~74 s (Vision prepared its model …)`.
2a. **Start translating right away** (within a few seconds of launch). Expected: the menu
    status shows `กำลังเตรียม OCR ครั้งแรก…` (and the panel in Panel mode) until the text is
    translated.
2b. Or wait until the warm-up line appears, then start. Expected: translated within ~5 s.

### Proposed follow-ups
- **Avoid the switch altogether:** sign the Verify/unit-test builds with the same
  Apple Development certificate when it is installed (like `build.sh` does). Then
  tests and app share one valid cache. This touches the Verify commands and signing
  (stability rule 1), so it's for Cowork/owner to decide. CI has no certificate and
  is unaffected.

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → READY | Cowork | from owner's logs 09:33 / 10:00 |
| 2026-09-24 | READY → IN_PROGRESS | Claude Code | started (stacked on T-0016, uncommitted) |
| 2026-09-24 | IN_PROGRESS → REVIEW | Claude Code | cause measured (signing-identity switch); warm-up + Thai status; AC-2 manual pending owner |
