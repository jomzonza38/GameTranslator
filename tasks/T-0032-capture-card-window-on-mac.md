# T-0032 — Switch picture in a window on the Mac (capture card, no OBS)

| Field | Value |
|---|---|
| **Status** | READY |
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

## Result

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-26 | → READY | Cowork | owner changed goal: play on the Mac screen; window + macOS full screen; keep external display as an option |
