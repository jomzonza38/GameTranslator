# T-0004 — build.sh must stop loudly when code signing fails

| Field | Value |
|---|---|
| **Status** | REVIEW |
| **Type** | fix |
| **Priority** | P1 |
| **Version impact** | none (build script only) |
| **Milestone** | M1 — Stability |
| **Depends on** | — |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-23 by Cowork (code audit v1.11.11, finding 4) |

## Objective
If `./build.sh` cannot sign the installed app with the chosen identity, the owner
must know immediately instead of getting an app that silently asks for Screen
Recording permission again. This protects stability goal 1.

## Context
- `build.sh` lines ~85/87: `codesign --force --deep --sign "$SIGN_IDENTITY" ... || true`
  followed by `echo "🔏 Signed ($SIGN_IDENTITY)"` — a failed signature is ignored and
  reported as success. The app then keeps the ad-hoc signature from xcodebuild
  (`CODE_SIGN_IDENTITY="-"`) → new TCC identity → the permission prompt comes back.
- Separate, **not** part of this task: whether `rm -rf` + `cp -R` and `--deep` reset
  the Screen Recording grant (still in ROADMAP backlog).

## Requirements
1. If signing fails, the script prints a clear Thai error with the codesign output
   and exits non-zero **before** killing the running copy or launching the new one.
2. After signing, the script verifies the installed app is signed by the expected
   identity (not ad-hoc when a certificate was found) and fails the same way if not.
3. When no certificate is found (ad-hoc fallback), current behaviour and warning stay.
4. A successful build behaves exactly as today (same install path, same steps).

## Out of scope
- Replacing `rm -rf`/`cp -R`, removing `--deep`, or changing the entitlements.
- CI workflow and Swift sources.

## Constraints
- CLAUDE.md stability rule 1: do not change how the bundle is installed or which
  identity is used. Running `./build.sh` for verification only if the owner agrees
  (it replaces the installed app).

## Files / Modules
- `build.sh`

## Acceptance Criteria
- **AC-1** [code] No `|| true` (or equivalent) remains on the codesign commands; a
  failure exits non-zero with a Thai message and the codesign output.
- **AC-2** [code] A verification step (e.g. `codesign --verify` + checking the
  signing authority) runs after signing when a certificate identity is used.
- **AC-3** [code] Kill/relaunch of the app happens only after signing and
  verification succeeded.
- **AC-4** [manual] Steps: run `SIGN_IDENTITY="Nonexistent Identity" ./build.sh`.
  Expected: script stops with a Thai signing error, non-zero exit code, the running
  GameTranslator is not killed.
- **AC-5** [manual] Steps: run `./build.sh` normally. Expected: builds, installs,
  launches as before and Screen Recording is **not** asked again.
- **AC-6** [build] Unit tests and Release build succeed (Swift code unchanged).

## Testing Requirements
- `bash -n build.sh` syntax check; owner runs AC-4 and AC-5.

## Definition of Done
- [ ] All acceptance criteria pass (`[manual]` ones confirmed by the owner)
- [ ] Release build succeeds
- [ ] Version: none (script-only change)
- [ ] `git diff` contains only changes justified by this task
- [ ] Result section complete; Cowork review passed

---

## Questions

## Implementation Notes

- **Signing** (`build.sh`, section "Sign with entitlements"): the two `codesign …
  || true` lines are replaced by one call built from an argument array (same flags:
  `--force --deep --sign "$SIGN_IDENTITY" [--entitlements …] --timestamp=none`).
  On failure `sign_failed` prints a Thai error with the indented codesign output and
  `exit 1`. `set -e` alone would also stop the script, but silently — hence the
  explicit `if ! …; then`.
- **Verification** (only when `SIGN_IDENTITY != "-"`), all before `xattr`, `killall`,
  `tccutil` and `open`:
  1. `codesign --verify --deep --strict "$TARGET"` must succeed.
  2. `codesign -dvv` must not show `Signature=adhoc`.
  3. When the identity is a name, one line must be exactly `Authority=<identity>`
     (`grep -qxF`). An identity given as a 40-hex SHA-1 can't be matched by name →
     only checks 1–2.
  On success it prints `✅ ตรวจ signature แล้ว — sign ด้วย …`.
- **Ad-hoc fallback (Req 3):** unchanged — same warning at the top, signs with `-`,
  no verification step, `tccutil reset` still runs for ad-hoc only. A codesign
  failure in ad-hoc mode now also stops the script (AC-1: no `|| true` on codesign).
- **Success path (Req 4):** same steps in the same order; only the extra ✅ line is
  printed. Install path, `rm -rf`/`cp -R`, `--deep`, entitlements unchanged.
- **Tested without running `./build.sh`** (it would replace the installed app): the
  sign/verify sections were extracted from `build.sh` and run under `set -eo pipefail`
  on scratch copies of the app:
  | Case | Result |
  |---|---|
  | `SIGN_IDENTITY="Nonexistent Identity"` | exit 1, `❌ Sign ไม่สำเร็จ … no identity found` |
  | `SIGN_IDENTITY="-"` | signs ad-hoc, continues (no verification) |
  | verify: installed app vs its real identity | ✅ passes |
  | verify: installed app vs a different identity name | exit 1, lists the actual `Authority=` lines |
  | verify: ad-hoc app vs identity name / vs SHA-1 | exit 1, `แอพยังเป็น ad-hoc signature` |
  Signing with the real certificate was not run here, to avoid a Keychain prompt —
  that is AC-5.
- **Heads-up for the reviewer (not changed, out of scope):** signing happens *after*
  the old app was deleted and the new one copied to `/Applications`. So when signing
  fails, the running copy is untouched (Req 1), but `/Applications/GameTranslator.app`
  is already the new, wrongly signed bundle. The error message says not to open it
  and to rerun `./build.sh`. Signing before installing would avoid this, but it changes
  the install flow (Out of scope / stability rule 1) → proposed follow-up.

## Result

**Outcome:** PARTIAL — all `[code]`/`[build]` criteria pass; AC-4 and AC-5 pending owner
**Version:** none (script-only change, as specified)
**Commit:** `7a9618f`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `grep "|| true" build.sh` → only lines 14 (identity lookup), 79 (`touch`), 137 (`killall`), 144 (`tccutil`); none on `codesign`. Failure path tested: exit 1 + Thai message + codesign output. |
| AC-2 | ✅ pass | `build.sh` lines ~111–128: `--verify --deep --strict`, ad-hoc check, `Authority=` match; tested pass/fail cases above. |
| AC-3 | ✅ pass | codesign + verification at lines ~104–128; `killall` at 137, `open` at 150; `sign_failed` exits before them. |
| AC-4 | ⏳ pending owner | Steps below. |
| AC-5 | ⏳ pending owner | Steps below. |
| AC-6 | ✅ pass | `bash -n build.sh` OK; `Executed 60 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
bash -n build.sh  → OK
Executed 60 tests, with 0 failures (0 unexpected) in 0.081 (0.108) seconds
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 build.sh                                           | 49 ++++++++++++++++++++--
 tasks/BOARD.md, tasks/T-0004-…md                   | (status + this report)
```

### Manual checks for the owner
**AC-4** — with GameTranslator running:
```bash
SIGN_IDENTITY="Nonexistent Identity" ./build.sh; echo "exit=$?"
```
Expected: `❌ Sign ไม่สำเร็จ (Nonexistent Identity) … no identity found`, `exit=1`,
GameTranslator is still running. **Afterwards run `./build.sh` normally** — this step
leaves a wrongly signed copy in /Applications (see Implementation Notes).

**AC-5** — `./build.sh` normally. Expected: the new line
`✅ ตรวจ signature แล้ว — sign ด้วย Apple Development: …`, then install, relaunch as
before; Screen Recording is **not** asked again.

### Proposed follow-ups
- Sign (and verify) the build output *before* deleting and replacing the installed
  app, so a signing failure leaves the working installed copy untouched. Changes the
  install flow → needs Cowork/owner decision (relates to the ROADMAP item about
  `rm -rf` + `cp -R` and `--deep`).

---

## Review

**Cowork, 2026-09-23 — code review passed; waiting for owner's AC-4 / AC-5.**

| AC | Verdict | Note |
|---|---|---|
| AC-1 | ✅ | `|| true` gone; failure → Thai message + codesign output + `exit 1`. |
| AC-2 | ✅ | `--verify --deep --strict`, not ad-hoc, `Authority=` must match (SHA-1 identities skip the name match — reasonable). |
| AC-3 | ✅ | All checks run before `killall`/`open`. |
| AC-4, AC-5 | ⏳ owner | |
| AC-6 | ✅ | Swift untouched. |

- Minor, no action: with `set -o pipefail`, `echo … \| grep -q` could in theory report SIGPIPE; output is tiny, so not a real risk.
- Follow-up accepted → ROADMAP backlog: sign/verify the build output **before** replacing the installed app (merges with the `rm -rf`/`--deep` item).

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-23 | → READY | Cowork | created from code audit v1.11.11 |
| 2026-09-23 | READY → IN_PROGRESS | Claude Code | started |
| 2026-09-23 | IN_PROGRESS → REVIEW | Claude Code | code/build ACs pass; AC-4, AC-5 manual pending owner |
