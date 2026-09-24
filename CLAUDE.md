# CLAUDE.md — GameTranslator

macOS menu bar app (Swift, AppKit + SwiftUI, macOS 14+) that captures a game
window, OCRs it with Vision, translates to Thai and shows the result as an
overlay on the text or in a floating panel. UI strings are Thai.

Work is planned by **Cowork** and implemented by **Claude Code** through task
files in `tasks/` — see "Working on a task" below and `WORKFLOW.md`.

## Workflow rules (from the owner)

- Make changes **in this repo's working tree**; never hand over loose files.
- **Do not commit or push unless the owner explicitly asks** in the conversation.
  Leave changes uncommitted and report them.
- **Branches — work on `develop`, `main` is for reviewed releases:**
  - All task work and every commit happen on **`develop`**. Never commit directly on
    `main`.
  - Before starting work, check `git branch --show-current` is `develop`. If it isn't,
    stop and ask the owner — don't switch branches yourself while there are
    uncommitted changes.
  - "push" means `git push` of `develop` (tracks `origin/develop`). Push `main` only when
    the owner explicitly says so.
  - `main` moves only when the owner asks to merge `develop` into it — normally at the
    end of a milestone, after Cowork's review and the owner's manual checks. Default:
    `git checkout main && git merge --ff-only develop && git checkout develop` (or a
    GitHub PR `develop → main` if the owner prefers). If `--ff-only` fails, stop and
    report — don't create merge commits or rebase on your own.
  - CI (`.github/workflows/build.yml`) runs on pushes to `main` and on pull requests,
    **not** on pushes to `develop`. The local Verify step is the only check before
    `main`, unless a PR is opened.
- **Bump the version together with the code change** (so it lands in the same
  commit) — `CFBundleShortVersionString` in `Resources/Info.plist` is the only
  version source. Semver: fix → patch, feature/visible behaviour → minor.
  Docs/CI/test-only changes don't bump. Don't create tags.
- When asked to commit: author `Jom <feel2hurt@gmail.com>`, one task per commit,
  clear body (what + why), task ID in the body (`Task: T-0001`).
- Reply to the owner in Thai; technical terms in English are fine.

### Stability rules (from the owner — must hold after every change)

1. **A rebuild must not bring back the Screen Recording prompt.** Code changes
   and `./build.sh` must keep the TCC identity stable: same bundle ID, same
   Apple Development signing identity (never ad-hoc `-`), no change to how the
   bundle is installed or signed unless that is the task. If a change could
   reset the grant (see "macOS permission gotchas" below), say so to the owner
   *before* committing. Never add new calls that can pop the system dialog
   (`SCShareableContent` without preflight, extra `CGRequestScreenCaptureAccess()`).
2. **After the app tells the user to reopen (the "Quit & Reopen" / 🔄 เปิดแอปใหม่
   flow, or the game being closed and started again), the app must not crash or
   freeze.** A missing/closed game window or a stopped SCStream must be handled
   gracefully: stop capture, clear the overlay, show a Thai message — no
   force-unwraps, no infinite waits, no blocked main thread.
3. **The build must not break.** Before reporting any code change as finished
   (and before any commit), run the unit tests and a Release build ("Verify"
   below) and confirm `** TEST SUCCEEDED **` / `** BUILD SUCCEEDED **` with no
   `error:` lines. Never report or commit code that does not compile. If Xcode is
   not available (e.g. Linux sandbox), say clearly that it was not built and ask
   the owner to run `./build.sh` before relying on it.

## Build, run, test

**Verify** — what every task must pass. Same as CI; does not install, re-sign or
relaunch the app, so it cannot affect the Screen Recording grant:

```bash
xcodegen generate
xcodebuild test -project GameTranslator.xcodeproj -scheme GameTranslator \
  -destination 'platform=macOS' -derivedDataPath build 2>&1 \
  | grep -E "error:|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)"
xcodebuild build -project GameTranslator.xcodeproj -scheme GameTranslator \
  -configuration Release -derivedDataPath build CODE_SIGN_IDENTITY="-" 2>&1 \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

**Install and run** — `./build.sh` (generate → Release build → replace the app in
/Applications → sign → kill the running copy → launch). It replaces the installed
bundle, so run it only when the owner asks or a `[manual]` check needs the
installed app — never as a routine verification step.

```bash
./build.sh 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"   # errors only
```

- `GameTranslator.xcodeproj` is **generated** from `project.yml` and git-ignored.
  New files in `Sources/` / `Tests/` are picked up automatically.
- CI: `.github/workflows/build.yml` (macos-15) runs tests + Release build and
  uploads the .app. macOS uses BSD grep → use `grep -F` for literal `**` strings.
- `Package.swift` is stale and unused; build with XcodeGen/Xcode only.
- Runtime log: `~/Desktop/GameTranslator.log` (cleared at each launch).

### When you can't run Xcode (e.g. Linux sandbox)
You cannot compile here. Check syntax with tree-sitter-swift
(`pip install tree-sitter tree-sitter-swift`); known false positive:
`x as? T ?? y`. Then ask the owner to run `./build.sh` and paste errors.
Watch for Swift concurrency errors — they are compile errors under Xcode 26 SDK:
- `AppDelegate` helper methods are **nonisolated**; `StatusBarController`,
  `PipelineCoordinator`, `TranslationHistory`, `ScreenRecordingPermission`,
  SwiftUI views are `@MainActor`. Mark pure helpers `nonisolated`, or hop with
  `Task { @MainActor in … }`. Don't call MainActor code from
  `DispatchQueue.main.async` closures.

## Working on a task (Cowork × Claude Code)

Cowork decides **what/why** and writes tasks; you decide **how** and implement.
Full rules: `WORKFLOW.md` (lifecycle, section ownership, corrective tasks).
Files: `ROADMAP.md` (Cowork's plan), `tasks/BOARD.md` (index),
`tasks/T-NNNN-*.md` (one per task), `tasks/TASK_TEMPLATE.md`.

When the owner says "ทำ T-NNNN" (or "ทำ task ถัดไป" = lowest-numbered `READY` task
whose `Depends on` tasks are `DONE`):

1. **Check you may start.** The task must be `READY`, and the current branch must be
   `develop` (see *Branches*). Run `git status`: if source
   changes from another task are still uncommitted (anything outside `tasks/`,
   `ROADMAP.md`, `WORKFLOW.md`), stop and ask the owner to commit them or to allow
   stacking. One task at a time.
2. **Understand it.** Read the whole task file and the code in *Files / Modules*.
   If a requirement is ambiguous, contradicts the code, the stability rules or
   another task, or can't be met — write the question and a concrete proposal under
   *Questions*, set `BLOCKED` (task file + BOARD + Status history) and report.
   **Don't guess and don't change requirements, scope or acceptance criteria.**
3. **Claim it.** Set `IN_PROGRESS` in the task file, the BOARD row and Status history.
4. **Implement within scope.** Touch only what the task needs. If another file must
   change, record why in *Implementation Notes*. Problems you notice outside the
   scope go under *Result → Proposed follow-ups* — don't fix them. Add or update unit
   tests as *Testing Requirements* say (pure logic → unit test). Bump the version.
5. **Verify.** Run the Verify commands above. Both must succeed.
6. **Review your diff.** `git status` + `git diff`: every change belongs to the task,
   no debug code, no secrets, no unrelated formatting, version bumped once, no new
   call that can show the Screen Recording dialog.
7. **Check every acceptance criterion** and record evidence (test name, command
   output, diff reference). `[manual]` criteria → exact steps for the owner, marked
   ⏳ pending owner.
8. **Report.** Fill *Implementation Notes* and *Result* (template in
   `tasks/TASK_TEMPLATE.md`). Set `REVIEW` only if every `[test]`, `[build]` and
   `[code]` criterion passes; otherwise keep `IN_PROGRESS` (or `BLOCKED`) and say
   exactly what fails. **Never set `DONE`** — only Cowork does. Update BOARD
   (*Next step by* → Cowork). Then reply to the owner in Thai: task, outcome,
   changed files, manual checks needed.
9. **Don't commit or push** unless the owner asks. If asked, one commit per task on
   `develop`, and fill the *Commit* line in the task's Result and the BOARD.

Never edit the Cowork-owned sections of a task (header except Status, Objective →
Definition of Done, Review) and never edit `ROADMAP.md` priorities. Without a task
(ad-hoc owner request), the same rules apply except the task-file bookkeeping.

## Architecture

```
ScreenCaptureService (SCStream, window) ─► PipelineCoordinator (@MainActor)
   per enabled region: OCRService.recognizeText(cropTo:)  ← OCR only inside the region
   → RegionLayout.mergeAdjacentLines → TextTracker.diff
   → RegionPipelineState: stale cache / glossary exact match / similar-text reuse
     / stability gate (wait until text stops changing) / failure back-off
   → ONE TranslationService.translateBatch for all regions (+ TranslationContext)
   → RegionLayout.buildRegions / resolveOverlaps → Overlay or Panel
```

| Area | Files |
|---|---|
| App shell, menu, hotkeys, welcome, permission | `App/AppDelegate.swift`, `App/StatusBarController.swift`, `App/ScreenRecordingPermission.swift`, `Services/HotKeyManager.swift`, `Views/WelcomeView.swift` |
| Settings & persistence | `Models/AppSettings.swift` (UserDefaults), `Services/KeychainStore.swift` (API keys), `Models/GameProfile.swift` (per-game title + glossary) |
| Providers | `Providers/TranslationProvider.swift` (protocol, `TranslationContext`), `LLMChatProvider.swift` (shared prompt/batch/parse/sanitize for OpenAI + Claude), Google Free/Cloud, DeepL |
| Pipeline helpers (pure, unit-tested) | `RegionLayout`, `RegionPipelineState`, `TranslationContextBuilder`, `TextTracker`, `TranslationCache` |
| UI | `Overlay/*` (overlay window, panel with region chips, region selector), `Views/*` (settings tabs, history, window picker) |

Key behaviours to preserve:
- API keys live in the Keychain; only the selected provider's key is read at launch.
- LLM replies go through `LLMPrompt.sanitize` (falls back to source text if the model chats).
- Glossary: in the prompt for LLMs, pre-substituted for Google/DeepL, exact matches skip the API.
- Regions can be disabled (`CaptureRegion.isEnabled`); disabled regions are not OCR'd.
- Hotkeys: ⌃⌥T start/stop, ⌃⌥1…9 toggle region N. (Pause/once/hide were removed on request.)

## macOS permission gotchas (hard-won)

- **Signing identity decides whether TCC/Keychain remember the app.** `build.sh`
  signs with an installed Apple Development cert (auto-detected, or `SIGN_IDENTITY=…`);
  ad-hoc (`-`) = new identity every build = asked again every build.
- `CGPreflightScreenCaptureAccess()` never prompts but is **cached per process** —
  a new grant only applies after relaunch ("Quit & Reopen" / menu 🔄 เปิดแอปใหม่).
- `SCShareableContent` **pops the system dialog when not granted** — always
  preflight before calling it.
- `CGRequestScreenCaptureAccess()` is called at most once per installed build.
- A second launched copy waits 3 s for the old one to exit, otherwise it notifies
  the running copy (`com.worawalan.GameTranslator.showWelcome`) and quits.
- **Vision's OCR model cache is per signing identity** (T-0017, measured): Vision
  compiles its text-recognition model for the Neural Engine on first use and caches
  it in `~/Library/Caches/com.worawalan.GameTranslator/com.apple.e5rt.e5bundlecache/<macOS build>/`.
  The cache stays valid across new builds with the **same** signature, but switching
  between ad-hoc builds (unit tests / Verify) and the cert-signed installed app makes
  the next first OCR take **~74 s** (the log shows `MDB_MAP_FULL` at the same time). So
  after running the tests, the owner's next app launch recompiles. The app warms Vision
  up at launch (`OCRService.warmUp`) and shows "กำลังเตรียม OCR ครั้งแรก…" meanwhile.
- Earlier finding (see project doc `claude/screen-recording-permission-fix.md`):
  replacing the bundle with `rm -rf` + copy, and `codesign --deep`, can reset the
  Screen Recording toggle. `build.sh` still does both — suspect it first if the
  permission keeps being asked after every build.
