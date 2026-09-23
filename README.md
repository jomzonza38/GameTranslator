# GameTranslator

[![Build & Test](https://github.com/jomzonza38/GameTranslator/actions/workflows/build.yml/badge.svg)](https://github.com/jomzonza38/GameTranslator/actions/workflows/build.yml)

แอป macOS แปลข้อความบนหน้าจอเกมแบบ real-time เป็นภาษาไทย (อังกฤษ ญี่ปุ่น จีน เกาหลี)

A macOS menu bar app that captures text from a game window, recognizes it with OCR, translates it to Thai, and shows the translation on top of the original text or in a floating panel.

## Features

- **Screen capture** via ScreenCaptureKit — pick a specific game window
- **OCR** with Apple Vision, Fast or Accurate mode
- **Source languages**: English, Japanese, Chinese (Simplified / Traditional), Korean
- **Region selection** — drag to select an area (e.g. a dialog box) and translate only that region
- **Text diff** (Levenshtein) so unchanged text isn't re-translated, plus a translation cache
- **Two display modes**
  - *Overlay* — Thai text drawn over the original positions
  - *Panel* — floating text box that collapses at the screen edge
- **Translation providers**: Google (free, default), OpenAI GPT-4o-mini, Claude Haiku, DeepL Free / Pro, Google Cloud Translation
- **Game-aware AI translation** (OpenAI / Claude): game title and the previous few lines are sent as context so names and tone stay consistent
- **Per-game glossary** — fix how character names, places and skills are translated
- **Translation history** with search, copy and export to .txt
- **Global hotkeys** that work while the game is focused
- API keys stored in the macOS **Keychain**

## Hotkeys

| Keys | Action |
|---|---|
| ⌃⌥T | Pick a window and start / stop |
| ⌃⌥P | Pause / resume continuous translation |
| ⌃⌥Y | Translate the current screen once |
| ⌃⌥H | Hide / show translations |
| ⌘⇧R | Add a translation region (menu) |
| ⌘⇧L | Translation history (menu) |

## Pipeline

```
Screen Capture → OCR → Region Filter → Line Merge → Text Diff → Glossary / Cache → Translate → Layout → Display
```

## Requirements

- macOS 14 Sonoma or later
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

No Apple Developer account needed — the app is ad-hoc signed ("Sign to Run Locally").

## Build & Run

```bash
./build.sh
```

The script regenerates the Xcode project from `project.yml`, builds Release, installs to `/Applications` (or `~/Applications`), ad-hoc signs it, and launches the app.

Or open in Xcode:

```bash
xcodegen generate
open GameTranslator.xcodeproj
```

The `.xcodeproj` is generated and not committed — run `xcodegen generate` after pulling.

On first launch, grant **Screen Recording** permission in System Settings → Privacy & Security.

## Tests

```bash
xcodegen generate
xcodebuild test -project GameTranslator.xcodeproj -scheme GameTranslator -destination 'platform=macOS'
```

GitHub Actions runs the tests and a Release build on every push to `main`; the built `.app` is attached to each run as an artifact.

## API keys

API keys for paid providers are entered in the app's Settings window and stored in the macOS Keychain — they are never part of this repository.

Because the app is ad-hoc signed, macOS may ask to allow Keychain access after a rebuild. Choose **Always Allow**.

## Project structure

```
Sources/
  App/        App delegate, menu bar controller
  Models/     Settings, game profiles, capture regions, pipeline types
  Overlay/    Overlay window, translation panel, region selector
  Providers/  Translation providers (LLMChatProvider shares OpenAI/Claude logic)
  Services/   Capture, OCR, text tracker, cache, layout, context, hotkeys, history, pipeline
  Views/      SwiftUI settings, game & glossary, history, window picker
Tests/        Unit tests
Resources/    Info.plist, entitlements
project.yml   XcodeGen spec
build.sh      Build + install script
```

## License

[MIT](LICENSE)
