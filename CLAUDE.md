# CLAUDE.md — GameTranslator

macOS menu bar app (Swift, AppKit + SwiftUI, macOS 14+) that captures a game
window, OCRs it with Vision, translates to Thai and shows the result as an
overlay on the text or in a floating panel. UI strings are Thai.

## Workflow rules (from the owner)

- Make changes **as git commits in this repo**; never hand over loose files.
- **Do not push.** The owner runs `git push` himself.
- **Bump the version in the same commit as the code change** —
  `CFBundleShortVersionString` in `Resources/Info.plist` is the only version
  source. Semver: fix → patch, feature/visible behaviour → minor. Docs/CI/test-only
  commits don't bump. Don't create tags.
- Commit author: `Jom <feel2hurt@gmail.com>`. Write clear commit bodies (what + why).
- Reply to the owner in Thai; technical terms in English are fine.

## Build, run, test

```bash
./build.sh            # xcodegen generate → Release build → install to /Applications → sign → launch
xcodegen generate && xcodebuild test -project GameTranslator.xcodeproj \
  -scheme GameTranslator -destination 'platform=macOS'
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
- Earlier finding (see project doc `claude/screen-recording-permission-fix.md`):
  replacing the bundle with `rm -rf` + copy, and `codesign --deep`, can reset the
  Screen Recording toggle. `build.sh` still does both — suspect it first if the
  permission keeps being asked after every build.
