# T-0035 — Capture card translation: stop re-reading a flickering screen; measure and cut the WindowServer cost

| Field | Value |
|---|---|
| **Status** | READY |
| **Type** | fix |
| **Priority** | P1 (urgent) |
| **Version impact** | patch (minor if the translation toggle counts as a feature) |
| **Milestone** | M7 — Capture card mode |
| **Depends on** | — (stacks on T-0034; owner commits T-0034 first) |
| **Corrects** | T-0034 |
| **Follow-up** | — |
| **Created** | 2026-09-26 by Cowork |

## Objective
T-0034 made no measurable difference on the owner's Mac. Translation must stop costing ~40 % CPU and the
Mac must stop throttling.

## Context
Owner, 2026-09-26 16:06, build 1.18.1, full screen, no regions, dialogue screen:
```
GameTranslator 43.4 %  WindowServer 42.3 %  kernel_task 21.8 %  coreaudiod 12.7 %  UVCAssistant 8.2 %
Capture card: text changed — OCR at full rate          (16:06:09.868)
Capture card: same text read again — OCR at most once a second  (16:06:10.908)
Capture card: text changed — OCR at full rate          (16:06:12.042)
Capture card frames: 60 received, 60 with changed pixels, 34 sent to OCR in 10 s
```
Reading:
- **Pacer defeated:** OCR results alternate (earlier logs: 7 ↔ 8 texts on the same screen) → "text changed"
  every ~2 s → back to full rate. 3.4 OCR/s × ~100 ms ≈ the app's 43 %.
- **Grid says every frame changed** (60/60) — real animation somewhere in the full picture, not only noise.
- **WindowServer 42 % didn't drop** although the capture got ~3× smaller → its cost is probably not the
  copy size. Unknown how much of it is the picture alone (preview layer, 1080p60 full screen) — never
  measured, because ⌃⌥V always starts translation too.

## Requirements
1. **Translation on/off while the picture runs:** a menu item (and hotkey if free, e.g. ⌃⌥⇧V or similar —
   Claude Code proposes) to pause/resume translating the Switch picture without closing it. Useful for the
   owner and needed for the baseline below.
2. **Baseline first:** record in Implementation Notes the owner-run numbers (or ask the owner) for
   picture-only vs translation-on: GameTranslator / WindowServer / kernel_task.
3. **Pacer on "nothing new to translate", not exact OCR equality:** when every text on screen already has a
   translation (or is the same as before within the existing similarity rules), treat the screen as
   unchanged — a flickering extra text must not reset it. Back-off ~1 OCR/s, and down to e.g. one per 2–3 s
   after a longer quiet time; full rate again when a *new untranslated* text appears.
4. **If translation-on WindowServer is > ~10 points above the picture-only baseline:** feed OCR from the
   capture card itself (throttled `AVCaptureVideoDataOutput`, late frames dropped, ≤ capture FPS) instead of
   ScreenCaptureKit; map results onto the window's content rect (T-0032 keeps the aspect). Otherwise record
   why ScreenCaptureKit stays.
5. Everything from T-0028/T-0034 keeps working (Overlay/Panel, regions, full screen, new dialogue ≤ ~2 s).

## Out of scope
- USB 2.0 smoothness (owner buying a USB 3 adapter). Settings tab (T-0029).

## Constraints
- CLAUDE.md stability rules apply. Picture path (preview layer) unchanged.

## Files / Modules
- `Sources/Services/PipelineCoordinator.swift`, `Sources/Services/CaptureCardChangeDetection.swift`,
  `Sources/App/StatusBarController.swift`, `Sources/Services/CaptureCardService.swift` (only for Req 4), `Tests/…`

## Acceptance Criteria
- **AC-1** [test] Pacer: alternating 7↔8 texts that are all already translated → stays slowed; a new
  untranslated line → full rate at once.
- **AC-2** [code] Translation pause stops OCR/capture work completely (no SCK stream / data output running).
- **AC-3** [build] Unit tests and Release build succeed.
- **AC-4** [manual] Owner, full screen, no regions, 2 min on a dialogue screen, measured with
  `top -l 2 -n 6 -stats command,cpu -o cpu`: (a) translation paused, (b) translation on. (b) GameTranslator
  ≤ 15 % above (a); WindowServer ≤ 10 points above (a); kernel_task not higher than in (a).
- **AC-5** [manual] New dialogue → Thai ≤ ~2 s.

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
| 2026-09-26 | → READY | Cowork | T-0034 made no difference in the owner's measurement |
