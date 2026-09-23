# GameTranslator

แอป macOS แปลข้อความบนหน้าจอเกมแบบ real-time (English → Thai)

A macOS menu bar app that captures English text from a game window, recognizes it with OCR, translates it to Thai, and shows the translation on top of the original text or in a floating panel.

## Features

- **Screen capture** via ScreenCaptureKit, pick a specific game window
- **OCR** with Apple Vision
- **Region selection** — drag to select an area (e.g. a dialog box) and translate only that region
- **Text diff** (Levenshtein) so unchanged text isn't re-translated, plus a translation cache
- **Two display modes**
  - *Overlay* — Thai text drawn over the original positions
  - *Panel* — floating text box that collapses at the screen edge
- **Pluggable translation providers**: Google (free, default), OpenAI GPT-4o-mini, Claude Haiku, DeepL Free / Pro, Google Cloud Translation
- Menu bar app (no Dock icon), global hotkey **⌘⇧T**

## Pipeline

```
Screen Capture → OCR → Region Filter → Text Diff → Translate → Display (Overlay / Panel)
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

On first launch, grant **Screen Recording** permission in System Settings → Privacy & Security.

## API keys

API keys for paid providers are entered in the app's Settings window and stored locally on your Mac — they are never part of this repository.

## Project structure

```
Sources/
  App/        App delegate, menu bar controller
  Models/     Settings, capture region, detected/translated text
  Overlay/    Overlay window, translation panel, region selector
  Providers/  Translation provider implementations
  Services/   Screen capture, OCR, text tracker, cache, pipeline
  Views/      SwiftUI settings & window picker
Resources/    Info.plist, entitlements
project.yml   XcodeGen spec
build.sh      Build + install script
```
