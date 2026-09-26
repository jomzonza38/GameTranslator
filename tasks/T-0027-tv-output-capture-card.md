# T-0027 — TV Output (1/3): the capture card's picture on the TV, directly, without OBS

| Field | Value |
|---|---|
| **Status** | REVIEW_FAILED |
| **Type** | feature |
| **Priority** | P2 (normal) |
| **Version impact** | minor |
| **Milestone** | M7 — TV Output |
| **Depends on** | — |
| **Corrects** | — |
| **Follow-up** | T-0030 |
| **Created** | 2026-09-25 by Cowork |

> Amended 2026-09-25: owner answered Q1 (⌃⌥V) and Q2 (game sound on). After Cowork's review the
> original T-0027 was too big for one reviewable commit, so it is split: **T-0027** picture on the TV
> (+ sound, hotkey, unplug handling, latency measurement) → **T-0028** OCR/translation overlay on the
> TV → **T-0029** TV Output settings tab. Everything not in this file moved to T-0028/T-0029.

## Objective
Show the Nintendo Switch 2 picture from the Kingma capture card full screen on the TV (Mac display 2),
read directly by GameTranslator — no OBS — with the lowest latency macOS allows. This comes first so
latency can be measured before the translation overlay is built on top of it.

## Context
- Owner's hardware: Switch 2 → Kingma (USB, UVC) → MacBook Air M2 → TV as display 2, set to
  **Extend** (not Mirror) in System Settings → Displays. OBS can read the Kingma (debug only; must not
  be a dependency).
- **Limitation today:** capture is ScreenCaptureKit only (`ScreenCaptureService`, a window on screen).
  It cannot read a capture card; the only current way is OBS preview → window capture (extra latency).
- Hint (lowest-latency path): **AVFoundation** — `AVCaptureSession` with the UVC device
  (`AVCaptureDevice.DeviceType.external`, macOS 14+). Picture → `AVCaptureVideoPreviewLayer` in a
  window on the TV (the system draws the frames; no copy/encode/decode in app code). Format: prefer
  50/60 FPS, ≤ 1080p, uncompressed if the card offers it; log the chosen format.
- Hint (sound, owner Q2): `AVCaptureAudioPreviewOutput` in a **separate** session so audio can't delay
  video; plays to the Mac's current output (e.g. the TV over HDMI). Auto-pick the card's own audio
  device by name; never auto-pick the Mac's microphone; if none found or permission denied → picture
  only, logged.
- Permissions: Camera prompt on first use (the card counts as a camera), Microphone for sound →
  `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`. Screen Recording grant not affected.
- Hotkeys today: ⌃⌥T start/stop window translation, ⌃⌥1…9 regions. TV Output = **⌃⌥V** (owner Q1).
- Latency risks outside the app: MJPEG in the card (~1 frame), USB, display vsync, TV processing.
  Cursor hiding on the TV is best-effort while another app is active.
- Not yet verified: that `AVCaptureVideoPreviewLayer` is at least as fast as OBS's projector. If AC-8
  fails, report the numbers — fallback options (own Metal renderer from the data output, uncompressed
  720p60) are for a follow-up task, not this one.

## Requirements
1. ⌃⌥V and a menu item "📺 เริ่ม TV Output" start TV Output; ⌃⌥V or the menu's stop item stop it.
   ⌃⌥T while TV Output runs stops it (same as any running session); ⌃⌥V while window translation runs
   stops that first, then starts TV Output.
2. Reads the capture card directly; works with OBS closed. Capture device: first non-virtual external
   video device (a picker comes in T-0029).
3. Output display: the first display that isn't the Mac's built-in one (a picker comes in T-0029). No
   such display → Thai error, nothing started.
4. On the TV: borderless window covering the whole display, above the menu bar and Dock, no title bar,
   game picture aspect-fit (letterboxed) on black, cursor hidden while over it if possible. Nothing is
   shown on the Mac's display besides the menu bar icon and menu. The window never takes focus.
5. The TV's display mode/resolution is never changed ("Native").
6. Game sound from the capture card plays while TV Output runs (see Context).
7. TV Output is **off at every launch** (not persisted) — no Camera prompt at launch.
8. TV or capture card unplugged while running, or while starting → TV Output stops, Thai message in the
   menu, no crash/freeze, app stays open; plugged back → ⌃⌥V starts it again.
9. The menu shows the capture card name and chosen format while running.
10. Existing window translation, overlay, panel, regions and hotkeys unchanged.

## Out of scope
- OCR / translation / overlay on the TV (T-0028). Settings tab and pickers (T-0029).
- Changing ScreenCaptureKit capture or the pipeline.

## Constraints
- CLAUDE.md stability rules apply (no new Screen Recording prompt, no crash/freeze after unplug or
  reopen, build never broken). Bundle ID and signing unchanged.
- Thai UI strings.

## Files / Modules
- New: `Sources/Services/CaptureCardService.swift`, `Sources/Overlay/TVOutputWindowController.swift`, `Tests/…`
- `Sources/App/StatusBarController.swift` (menu, ⌃⌥V), `Sources/Services/PipelineCoordinator.swift`
  (only if the session state must live there), `Resources/Info.plist`

## Acceptance Criteria
- **AC-1** [test] Pure logic unit-tested: capture format choice, output display choice (external first,
  none → nil), aspect-fit/letterbox rect, audio device matching (never the Mac mic).
- **AC-2** [code] The picture reaches the TV only through `AVCaptureVideoPreviewLayer` — no frame copy,
  encode or decode in app code.
- **AC-3** [code] No new ScreenCaptureKit / `CGRequestScreenCaptureAccess` call; bundle ID and signing unchanged.
- **AC-4** [build] Unit tests and Release build succeed.
- **AC-5** [manual] OBS closed, Switch 2 → Kingma → Mac, TV extended as display 2. ⌃⌥V → allow Camera
  (and Microphone) → the game fills the TV with sound; no title bar, menu bar, Dock; cursor hidden over
  the TV; nothing duplicated on the Mac display; the menu shows card name + format.
- **AC-6** [manual] ⌃⌥V again → TV window closes, sound stops. ⌃⌥T window translation still works as before.
- **AC-7** [manual] Unplug the TV while running → stops with a Thai message, no crash; plug back → ⌃⌥V
  works. Same for the capture card, also unplugged right after pressing ⌃⌥V (while starting).
- **AC-8** [manual] Latency: phone slow-motion (240 fps) filming a Joy-Con button and the TV, TV Game Mode
  **on for both**, 10 presses per path, count frames press → reaction. Kingma → OBS (Fullscreen Projector)
  → TV vs Kingma → GameTranslator → TV. Pass: GameTranslator's **median ≤ OBS's median**. Record both
  medians in the Result.

## Testing Requirements
- Unit tests for the pure helpers in AC-1. Manual AC-5…AC-8 by the owner.

## Definition of Done
- [ ] All acceptance criteria pass (`[manual]` ones confirmed by the owner)
- [ ] Unit tests added/updated as required; full suite passes
- [ ] Release build succeeds
- [ ] Version bumped per CLAUDE.md
- [ ] `git diff` contains only changes justified by this task
- [ ] Result section complete; Cowork review passed

---

## Questions
**Owner decisions, 2026-09-25** (answers to the open points in *Context*; recorded by Claude Code):
- **Q1 Hotkey:** use **⌃⌥V** to toggle TV Output. ⌃⌥T stays start/stop (Requirement 8).
- **Q2 Game sound:** **yes, pass the capture card's audio through** (the proposal in *Context*:
  `AVCaptureAudioPreviewOutput` in a separate session, never auto-pick the Mac's microphone).
  So `NSMicrophoneUsageDescription` is needed.
- Still open (not answered): which glossary/profile to use in TV mode.
- Cowork, 2026-09-25: open glossary question resolved for now — one profile per capture card name
  (see T-0028); per-game profiles in TV mode → backlog.

## Implementation Notes
- **Structure.** `CaptureCardService` (capture only: discovery, format choice, video + audio
  `AVCaptureSession`s on one serial queue) · `TVOutputWindowController` (borderless panel on the TV +
  preview layer) · **new `Sources/Services/TVOutputController.swift`** (not in *Files / Modules*): the
  `@MainActor` start/stop sequence, permissions and unplug handling. Kept out of `StatusBarController`
  (already ~680 lines) and out of `PipelineCoordinator` (not needed for T-0027; T-0028 can hook the
  pipeline to this controller). `PipelineCoordinator` is untouched.
- **Picture path (AC-2).** Session → `AVCaptureVideoPreviewLayer` only; no data output, no frame in app
  code. Layer frame = `TVOutputLayout.aspectFitRect` (gravity `.resizeAspect` too), black window.
- **Format choice** (`CaptureCardSelection.bestFormatIndex`): ≥ 50 fps first → largest picture that fits
  1920×1080 (smallest above if none fits) → uncompressed over MJPEG at the same size → fps nearest 60.
  So a card offering YUY2 only at 1080p5 / 720p10 gets **MJPEG 1080p60** (uncompressed 720p60 is the
  follow-up option in *Context*). Runs at 60 fps if the format allows (`frameRate(for:)`). All formats
  the card offers and the chosen one are written to the log.
- **Capture card** = first `.external` video device that isn't virtual (transport `virt`, or "virtual"
  / "OBS " in the name).
- **Sound (Q2).** Separate audio session with `AVCaptureAudioPreviewOutput` (default output, volume 1).
  Device = audio input whose name is the same as the card's, or shares a distinctive word with it
  (generic words like USB/Video/Audio/Capture/HDMI ignored); built-in, virtual and aggregate devices are
  always refused → never the Mac microphone. Microphone permission is asked only if such a device
  exists. No match / denied → picture only, reason in the menu and log. The audio start runs after the
  window is shown, so it can't delay the picture.
- **Output display** = first non-built-in display, preferring one that isn't the primary display
  (differs from "first external" only with 2+ external displays, e.g. a Mac mini). Display mode is never
  touched (Req 5).
- **Window.** `NSPanel` `.borderless + .nonactivatingPanel`, `canBecomeKey/Main = false`, level
  `.screenSaver` (above menu bar and Dock), all Spaces, `hidesOnDeactivate = false`. Cursor:
  `NSCursor.hide/unhide` on enter/exit (balanced) — macOS may ignore it while the game app is active.
- **Stop / unplug / cancel.** Every start has a generation; `stop` bumps it and tells the capture queue,
  which cancels any older start whether it runs before or after it (also re-checked after the blocking
  `startRunning()`). Card unplug = `AVCaptureDevice.wasDisconnectedNotification` (while starting: any
  video device) + session runtime error / interruption; TV unplug = `didChangeScreenParameters` and
  the display ID gone (resolution change → window re-fitted). A start that hangs > 15 s stops with a
  Thai message. Nothing waits on the main thread.
- **Sessions.** ⌃⌥V while window translation runs → `pipeline.stop()` then TV Output; ⌃⌥T or picking a
  game window while TV Output is on → stops TV Output. While TV Output is on, the menu hides
  "เลือก Window..." and shows card, format, TV name, sound and "⏹ หยุด TV Output ⌃⌥V".
- **Errors.** Failed start (no TV, no card, Camera denied, card won't start) → Thai alert + menu line.
  Unplug while running → menu line only (no alert that would steal focus from the game).
- **Info.plist:** `NSCameraUsageDescription`, `NSMicrophoneUsageDescription` (Thai). No entitlement,
  bundle ID or signing change (the app is neither sandboxed nor hardened-runtime, so no camera/audio
  entitlement is needed); the Screen Recording grant is not affected. Camera/Microphone prompts appear
  only at the first ⌃⌥V, never at launch.

## Result

**Outcome:** PARTIAL — `[test]`/`[code]`/`[build]` criteria pass; AC-5…AC-8 pending owner
**Version:** 1.15.1 → 1.16.0
**Commit:** not committed (waiting for owner)

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `TVOutputTests` (23 tests): format choice (`testPicks1080p60MJPEGOverSlowUncompressedAnd4K30`, `testPrefersUncompressedAtTheSameSizeAndRate`, `testOnlyAbove1080pPicksTheSmallest`, `testFrameRateCapsAtSixty` …), display (`testPicksTheExternalDisplay`, `testOnlyBuiltInDisplayGivesNil` …), letterbox (`testFourByThreeIsPillarboxed`, `testWideContentIsLetterboxed` …), devices (`testNeverTheMacMicrophone`, `testNotAnUnrelatedUSBMicOrVirtualDevice`, `testSkipsVirtualCameras` …). |
| AC-2 | ✅ pass | `CaptureCardService` adds only an `AVCaptureDeviceInput` to the video session (no output); the picture is drawn by `AVCaptureVideoPreviewLayer` in `TVPictureView.attach`. No `AVCaptureVideoDataOutput` / sample-buffer code anywhere in the new files. |
| AC-3 | ✅ pass | No `SCShareableContent` / `CGRequestScreenCaptureAccess` in the new code (grep); `project.yml`, entitlements, `build.sh` unchanged; Info.plist only adds two usage strings + version. |
| AC-4 | ✅ pass | See below. |
| AC-5 | ⏳ pending owner | Steps below. |
| AC-6 | ⏳ pending owner | Steps below. |
| AC-7 | ⏳ pending owner | Steps below. |
| AC-8 | ⏳ pending owner | Steps below — record both medians here. |

### Build & test
```
Executed 221 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                          | 1.16.0, NSCameraUsageDescription, NSMicrophoneUsageDescription
 Sources/App/StatusBarController.swift         | ⌃⌥V, menu items/info, one session at a time
 Sources/Services/CaptureCardService.swift     | (new) selection logic + video/audio sessions
 Sources/Services/TVOutputController.swift     | (new) start/stop, permissions, unplug handling
 Sources/Overlay/TVOutputWindowController.swift| (new) TV window + preview layer, display choice, aspect fit
 Tests/TVOutputTests.swift                     | (new, 23 tests)
```

### Manual checks for the owner
Install with `./build.sh`. The first ⌃⌥V asks for **Camera** and (if the card's audio is found)
**Microphone** — allow both. The Screen Recording permission should not be asked again.

**AC-5** — OBS closed. Switch 2 → Kingma → Mac, TV set to **Extend** as display 2. Press ⌃⌥V → the game
fills the TV with sound; no title bar, menu bar or Dock on the TV; move the mouse onto the TV → cursor
hidden (best-effort); nothing extra on the Mac's display. Open the menu → "📺 TV Output: <card>", the
format (e.g. `1920×1080 @ 60 fps · MJPEG`), "🖥 จอ: <TV>", "🔈 เสียง: <device>". If it says 🔇, send
`~/Desktop/GameTranslator.log` (lines `TV Output: audio devices: …`).

**AC-6** — ⌃⌥V again → TV window closes, sound stops. Then ⌃⌥T → pick a game window → window
translation works as before. Also: ⌃⌥V while window translation runs → translation stops, TV Output starts.

**AC-7** — (a) While running, unplug the TV's HDMI → TV Output stops, menu shows
"⚠️ หยุด TV Output แล้ว เพราะทีวีถูกถอดออก…", app still responds; plug it back → ⌃⌥V works.
(b) Same with the capture card's USB → "…capture card ถูกถอดออก…". (c) Press ⌃⌥V and unplug the card
straight away → stops with a message (or an alert "เริ่ม TV Output ไม่ได้"), no hang; plug back → ⌃⌥V works.

**AC-8** — TV Game Mode on. Phone at 240 fps filming a Joy-Con button and the TV in the same shot.
10 presses with Kingma → OBS (Fullscreen Projector on the TV), 10 with Kingma → GameTranslator (⌃⌥V).
For each press count frames from the button going down to the first change on the TV. Pass: the
GameTranslator median ≤ the OBS median. Write both medians (frames and ms = frames × 4.17) here.

### Proposed follow-ups
- If AC-8 fails: own Metal renderer from a data output, or force uncompressed 720p60 (per *Context*).
- Picker for the capture device / TV / audio device is planned in T-0029; the log lists every device
  and format to help if auto-choice picks the wrong one.

---

## Review
**Cowork code review, 2026-09-26 — REVIEW_FAILED → corrective task T-0030.**
Build/test evidence present (`build/Logs/Test` 2026-09-25 22:35: 221 tests, 0 failures).

| AC | Verdict | Note |
|---|---|---|
| AC-1 | ✅ | 23 tests cover format, display, letterbox, device matching. Gap: only continuous frame-rate ranges are tested (see F-1). |
| AC-2 | ✅ | Video session has only an input; picture only via `AVCaptureVideoPreviewLayer`. |
| AC-3 | ✅ | No ScreenCaptureKit/`CGRequestScreenCaptureAccess` added; project, entitlements, build.sh unchanged. |
| AC-4 | ✅ | See evidence above. |
| AC-5…AC-8 | ⏳ | Not run yet — moved to T-0030 so the owner tests the corrected build once. |

Findings:
- **F-1 (blocking — possible crash, stability rule 2).** `startVideoOnQueue` builds the frame duration as
  `CMTime(1000, fps×1000)` from a Double. UVC cards usually report *discrete* rates (range min = max),
  and HDMI cards often report 59.94 (= 60000/1001). Then `1000/59940` is not exactly the supported
  `1001/60000`, and `activeVideoMinFrameDuration` raises `NSInvalidArgumentException` for an unsupported
  value — an Objective-C exception Swift can't catch → the app quits on ⌃⌥V. Same for 29.97.
- **F-2 (should fix — AC-8 depends on it).** The device is unlocked *before* `startRunning()`. On macOS
  the session may re-apply its preset (`.high`) when it starts and change the chosen format/frame rate,
  while the menu still shows the chosen one. The latency test would then run on an unknown format.
- **F-3 (minor).** While starting, *any* video device disconnecting (e.g. an iPhone Continuity camera)
  cancels the start — acceptable, just note it in the log line.
- **F-4 (note for the owner, no change).** If the TV is set as the *main* display, the menu bar with the
  app icon is under the TV window; ⌃⌥V still stops it. Card audio is matched by name only — a card
  named "USB Video" / "USB Digital Audio" gives no sound until the picker in T-0029.

Good: clean split (`TVOutputController` / `CaptureCardService` / window), generation-based cancel on one
serial queue, nothing blocking the main thread, 15 s start timeout, no alert on unplug, sound after
the picture, non-activating panel, balanced cursor hide.

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-25 | → PLANNED | Cowork | created from owner's request; waiting for owner decisions (hotkey, game sound) |
| 2026-09-25 | — | Claude Code | recorded owner decisions Q1 (⌃⌥V), Q2 (sound on) |
| 2026-09-25 | PLANNED → READY | Cowork | spec amended after review: split into T-0027/T-0028/T-0029 |
| 2026-09-25 | READY → IN_PROGRESS | Claude Code | started |
| 2026-09-25 | IN_PROGRESS → REVIEW | Claude Code | test/code/build ACs pass; AC-5…AC-8 manual pending owner |
| 2026-09-26 | REVIEW → REVIEW_FAILED | Cowork | code review: frame-duration crash risk (F-1), format may be reset at start (F-2) → T-0030 |
