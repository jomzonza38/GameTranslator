# T-0032 — Switch picture in a window on the Mac (capture card, no OBS)

| Field | Value |
|---|---|
| **Status** | DONE |
| **Type** | feature |
| **Priority** | P1 (urgent) |
| **Version impact** | minor |
| **Milestone** | M7 — Capture card mode |
| **Depends on** | — (builds on T-0027 + T-0030 code, commits `fe07ca3`, `f3201bf`) |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-26 by Cowork |

## Objective
Owner changed the goal (2026-09-26): play the Nintendo Switch 2 **on the Mac's own screen** — the
capture card's picture in a window on the Mac, with the Thai translation over it (T-0028) — with the
lowest latency possible and without OBS. No TV or monitor needed.

## Context
- T-0027/T-0030 already read the Kingma with AVFoundation and show it through
  `AVCaptureVideoPreviewLayer` (no frame through app code), but only on an **external** display
  (borderless panel at `.screenSaver` level); with only the built-in display ⌃⌥V says "ไม่พบจอที่สอง".
- Owner decisions 2026-09-26:
  - **Window style = option 1:** a normal window (resize, move) that can go **macOS full screen**
    (green button / ⌃⌘F, own Space). Menu bar stays reachable; nothing can get stuck on screen.
  - **External display kept:** the Mac is the default; sending the picture to a TV/monitor stays
    possible and becomes a choice in Settings (T-0029).
- Latency: window vs full screen differ by at most ~1 frame of compositing; measure both (AC-7).
  The capture card's own MJPEG step is outside the app.
- Keep the picture path of T-0027 unchanged (preview layer only). Start/stop, permissions, unplug,
  sound and the 15 s timeout stay in `TVOutputController`.

## Requirements
1. ⌃⌥V (and the menu item) opens the Switch picture in a **window on the Mac's built-in display**
   by default — with or without an external display connected. ⌃⌥V again closes it.
2. Window: title bar ("Nintendo Switch — Game Translator" or the card name), resizable with the
   picture's aspect ratio kept (no stretching; black bars only inside full screen), movable, remembers
   its size/position between uses, macOS full screen via green button / ⌃⌘F.
3. Closing the window (red button / ⌘W) stops capture and sound, same as ⌃⌥V.
4. Cursor hidden over the picture only in full screen (best effort); visible in window mode.
5. The window can be focused (it is where the owner plays); the menu bar icon and hotkeys keep working.
6. Until T-0029 adds the choice, the external-display path of T-0027 is kept in code but not used by
   default (no dead code removal needed; no behaviour lost permanently).
7. Unplugging the capture card → window closes with the Thai message (T-0027). Unplugging an external
   display no longer matters in Mac mode.
8. Existing window translation (⌃⌥T), overlay, panel and regions unchanged.

## Out of scope
- Translation over the picture (T-0028). Settings / display choice (T-0029).

## Constraints
- CLAUDE.md stability rules apply. Thai UI strings. No new Screen Recording calls.

## Files / Modules
- `Sources/Overlay/TVOutputWindowController.swift` (or a new window controller next to it),
  `Sources/Services/TVOutputController.swift`, `Sources/App/StatusBarController.swift` (menu wording), `Tests/…`

## Acceptance Criteria
- **AC-1** [test] Pure logic tested: window content size for the video aspect ratio (resize keeps it),
  default output = built-in display.
- **AC-2** [code] Picture still only through `AVCaptureVideoPreviewLayer`; no frame copies/encode.
- **AC-3** [build] Unit tests and Release build succeed.
- **AC-4** [manual] OBS closed, only the MacBook screen. ⌃⌥V → Switch picture in a window with sound;
  resize keeps the aspect ratio; ⌃⌘F → full screen, cursor hides; ⌃⌘F again → window; menu bar works.
- **AC-5** [manual] Red button or ⌃⌥V → closes, sound stops. Reopen → same size/position.
- **AC-6** [manual] Unplug the Kingma while playing → window closes, Thai message in the menu, no crash;
  plug back → ⌃⌥V works. ⌃⌥T window translation still works as before.
- **AC-7** [manual] Latency (method of T-0027 AC-8, 10 presses each, Joy-Con + Mac screen in one 240 fps
  shot): OBS preview (full screen) vs GameTranslator **window** vs GameTranslator **full screen**.
  Pass: GameTranslator full screen median ≤ OBS median. Record all three medians.

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
- **New `Sources/Overlay/CaptureCardWindowController.swift`** (the "new window controller next to it"):
  a normal `NSWindow` (title, close, minimise, resize), `contentAspectRatio = picture size` so resizing
  never stretches, `collectionBehavior = .fullScreenPrimary` (green button). Frame saved with
  `saveFrame(usingName: "CaptureCardWindow")` on move/resize **only in window mode** (never the full-screen
  frame); reopened with `setFrameUsingName`, and if the saved size has another aspect ratio (other card
  format) its height is corrected (`CaptureCardWindowLayout.keepingAspect`). First open: 75 % of the
  built-in display's visible area, centred (`defaultContentSize`, `TVOutputLayout.macDisplayIndex`).
- **Shortcuts:** the app has no main menu, so ⌃⌘F (toggle full screen) and ⌘W (close) are handled in the
  window's `performKeyEquivalent`. The green button works natively.
- **Close = stop:** `windowWillClose` (red button / ⌘W) → `TVOutputController.stop()`; a stop from ⌃⌥V,
  the menu or an unplug closes the window without calling back (delegate cleared first).
- **Cursor:** `TVPictureView` (from T-0027, now internal instead of private) got `hidesCursor`; the Mac
  window sets it only between `windowDidEnterFullScreen` / `windowDidExitFullScreen`. The TV window keeps
  hiding it always.
- **Focus:** the window is made key and the app activated, so it is where the owner plays; Carbon hotkeys
  and the status item keep working while it is key.
- **`TVOutputController`:** new `Output` (`.macWindow` default, `.externalDisplay` = T-0027 path, kept
  and reachable by setting `output`, which T-0029 will do). The "no second display" check and the
  display-unplug stop apply only to the external path. Start/stop, permissions, sound, unplug and the
  15 s timeout are shared and unchanged. Picture path unchanged: session → `AVCaptureVideoPreviewLayer`
  in `TVPictureView` (AC-2).
- **Menu wording (`StatusBarController`):** "📺 เปิดภาพ Switch (capture card)" / "⏹ ปิดภาพ capture card"
  (⌃⌥V), info "📺 Capture card: <name>", format, "🖥 หน้าต่างบน Mac" (or "จอ: <TV>"), sound. Unplug
  messages say "ปิดภาพ capture card แล้ว เพราะ…". Alert: "เปิดภาพ capture card ไม่ได้".
- Risk for AC-4: the app is a menu bar (accessory) app. macOS normally lets its windows go full screen
  in their own Space; if the green button shows no full-screen option on the owner's macOS, report it —
  the fix would be switching the activation policy while the window is open (not done here).

## Result

**Outcome:** PARTIAL — `[test]`/`[code]`/`[build]` criteria pass; AC-4…AC-7 pending owner
**Version:** 1.16.1 → 1.17.0
**Commit:** `f221522`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `TVOutputTests`: `testDefaultWindowSizeKeepsThePicturesAspectRatio`, `testDefaultWindowSizeOnATallScreenIsLimitedByHeight`, `testSavedSizeIsCorrectedToThePicturesAspectRatio` (window size / resize keeps aspect), `testMacWindowUsesTheBuiltInDisplayEvenWithATV`, `testMacWindowWithoutBuiltInDisplayUsesThePrimary` (default output = built-in). |
| AC-2 | ✅ pass | `CaptureCardWindowController.show` → `TVPictureView.attach(session:)` → `AVCaptureVideoPreviewLayer`; `CaptureCardService` unchanged (no data output, no frame copy). |
| AC-3 | ✅ pass | See below. |
| AC-4 | ⏳ pending owner | Steps below. |
| AC-5 | ⏳ pending owner | Steps below. |
| AC-6 | ⏳ pending owner | Steps below. |
| AC-7 | ⏳ pending owner | Steps below — record three medians. |

### Build & test
```
Executed 235 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                              | 1.17.0
 Sources/Overlay/CaptureCardWindowController.swift | (new) window on the Mac, aspect, frame memory, full screen, ⌃⌘F/⌘W
 Sources/Overlay/TVOutputWindowController.swift    | macDisplayIndex; TVPictureView shared + hidesCursor
 Sources/Services/TVOutputController.swift         | Output (.macWindow default / .externalDisplay), close = stop
 Sources/App/StatusBarController.swift             | menu wording
 Tests/TVOutputTests.swift                         | 5 new tests
```

### Manual checks for the owner
Install with `./build.sh` (Camera/Microphone were already allowed in T-0027's build — if macOS asks,
allow). This build also covers T-0030 AC-5.

**AC-4** — OBS closed, only the MacBook screen, Switch 2 → Kingma → Mac. ⌃⌥V → the Switch picture in a
window with sound. Drag a corner → the picture keeps its shape (no stretching). ⌃⌘F (or the green
button) → full screen, the cursor hides over the picture; ⌃⌘F again → back to the window. The menu bar
icon works in both. Menu shows "📺 Capture card: …", the format, "🖥 หน้าต่างบน Mac", the sound line.

**AC-5** — red button (or ⌘W, or ⌃⌥V) → window closes, sound stops. Move/resize it first; ⌃⌥V again →
same size and position.

**AC-6** — while playing, unplug the Kingma → window closes, menu shows "⚠️ ปิดภาพ capture card แล้ว เพราะ
capture card ถูกถอดออก…", no crash; plug back → ⌃⌥V opens it. ⌃⌥T → pick a game window → translation
works as before.

**AC-7** — 240 fps phone video with the Joy-Con and the Mac screen in one shot, 10 presses each:
(a) OBS preview full screen, (b) GameTranslator window, (c) GameTranslator full screen. Count frames from
button down to the first change on screen. Pass: (c) median ≤ (a) median. Write all three medians here.

### Proposed follow-ups
- CLAUDE.md Verify: the last step's `lsregister -u` prints error -10814 (exit 1) for a product that is
  already unregistered (e.g. running it twice). Harmless; add `2>/dev/null || true` to the loop.

---

## Review
**Cowork code review, 2026-09-26 — code passes; waiting for the owner's AC-4…AC-7 (manual).**
Evidence: `build.noindex/Logs/Test` 2026-09-26 12:42 (235 tests, 0 failures); diff read in full.

| AC | Verdict | Note |
|---|---|---|
| AC-1 | ✅ | Default size, saved-size aspect correction, built-in display choice (also with a TV) tested. |
| AC-2 | ✅ | Same `TVPictureView` → `AVCaptureVideoPreviewLayer`; `CaptureCardService` untouched. |
| AC-3 | ✅ | Evidence above. |
| AC-4…AC-7 | ⏳ | Owner. This build also covers T-0030 AC-5. |

Good: external path kept behind `Output` (no dead end for T-0029), display-unplug stop limited to it,
close = stop without a callback loop (delegate cleared first), frame saved only in window mode,
⌃⌘F/⌘W handled although the app has no main menu, risk about full screen in an accessory app named up front.

Findings (none blocking):
- **F-1 (minor, watch in AC-5).** `windowDidResize` fires during the full-screen *enter* animation;
  `isFullScreen` is only set in `windowDidEnterFullScreen`, so the guard relies on
  `styleMask.contains(.fullScreen)` already being set at that moment. If after full screen → close →
  ⌃⌥V the window reopens screen-sized, set the flag in `windowWillEnterFullScreen` instead (follow-up).
- **F-2 (minor).** A saved frame on a display that is no longer connected: check in AC-5 that the window
  comes back on the Mac screen (AppKit usually moves it; if not → follow-up).
- **F-3 (note).** Accessory app: while the window is in its own full-screen Space the app has no Dock
  icon and isn't in ⌘Tab — get back with a three/four-finger swipe or Mission Control.
- Claude Code's follow-up (`lsregister -u` error -10814 when already unregistered) accepted → backlog.

Decision: DONE once AC-4…AC-7 are confirmed; then T-0030 → DONE and T-0028 → READY.

**2026-09-26 — owner: "ทุกอย่างโอเคแล้ว ไม่หน่วง"** — AC-4…AC-6 pass; AC-7: no lag felt (medians not recorded,
accepted). Not smooth → cause is the frame-rate choice from T-0030 (runs at 30 fps), fixed in T-0033. **DONE.**

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-26 | → READY | Cowork | owner changed goal: play on the Mac screen; window + macOS full screen; keep external display as an option |
| 2026-09-26 | READY → IN_PROGRESS | Claude Code | started |
| 2026-09-26 | IN_PROGRESS → REVIEW | Claude Code | test/code/build ACs pass; AC-4…AC-7 manual pending owner |
| 2026-09-26 | — | Cowork | code review passed; waiting for owner manual AC-4…AC-7 |
| 2026-09-26 | REVIEW → DONE | Cowork | owner confirmed; smoothness → T-0033 |
