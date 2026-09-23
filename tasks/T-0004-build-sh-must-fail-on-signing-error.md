# T-0004 — build.sh must stop loudly when code signing fails

| Field | Value |
|---|---|
| **Status** | READY |
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

## Result

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-23 | → READY | Cowork | created from code audit v1.11.11 |
