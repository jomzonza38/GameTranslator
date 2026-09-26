# T-0035 — Capture card translation: stop re-reading a flickering screen; measure and cut the WindowServer cost

| Field | Value |
|---|---|
| **Status** | DONE |
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
- **Req 1 — translation on/off, picture stays:** menu item under "⏹ ปิดภาพ capture card":
  "⏸ หยุดแปลชั่วคราว (ภาพยังเปิดอยู่)" / "▶︎ แปลภาพ Switch", hotkey **⌃⌥⇧V** (free; next to ⌃⌥V, which opens/closes
  the picture). Pause = `pipeline.stop()` → the ScreenCaptureKit stream, OCR and overlay/panel stop completely
  (AC-2); the picture and sound keep running. Resume = the same `translateCaptureCardPicture()` as after ⌃⌥V
  (also works as a retry after "window not found"). The menu shows "⏸ หยุดแปลชั่วคราว — กด ⌃⌥⇧V เพื่อแปลต่อ".
  Closing the picture clears the pause; ⌃⌥V always opens with translation on (T-0028 Req 8).
- **Req 3 — pacer on "nothing new":** `OCRPacer` rewritten. After each capture card OCR run it gets all texts on
  screen and the ones without a translation. "New" = untranslated **and** not seen in the last 30 s — so the
  7 ↔ 8 alternation of an already translated screen, or a text that flickers and never becomes stable, stays
  quiet; a new dialogue line (first time seen, untranslated) → full rate at once. Pace: full → after 3 quiet
  runs at most 1 OCR/s → after 15 s quiet at most 1 OCR per 2 s. Text still settling (stability gate) always
  bypasses the pacer, as in T-0034. Log lines: `Capture card: new text — OCR at full rate` /
  `nothing new to translate — OCR at most once a second` / `quiet for a while — OCR at most every 2 s`.
  Worst case for new dialogue: ≤ 2 s until the next paced read, then the normal stability + translation.
- **Req 2 — baseline:** not measured yet — needs the owner's hardware; the pause toggle makes it possible
  (steps in AC-4). ⏳
- **Req 4 — ScreenCaptureKit stays for now.** T-0034 cut the capture ~3× and WindowServer stayed at 42 %, so
  its load is most likely the 1080p60 full-screen video window itself, not the ScreenCaptureKit copy — and a
  `AVCaptureVideoDataOutput` feed would not remove that. Decision pending the baseline: if (b) WindowServer is
  > ~10 points above (a), the data-output feed becomes a follow-up (recorded under follow-ups).
- Files: all within *Files / Modules* (`CaptureCardService` not touched).

## Result

**Outcome:** PARTIAL — `[test]`/`[code]`/`[build]` criteria pass; AC-4, AC-5 (and Req 2 baseline) pending owner
**Version:** 1.18.1 → 1.19.0 (minor: the pause toggle is a new menu item + hotkey)
**Commit:** `0020c1d`

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `CaptureCardChangeDetectionTests`: `testAlternatingSevenAndEightTranslatedTextsStaysSlowed`, `testFlickeringUntranslatedTextDoesNotResetThePace`, `testNewUntranslatedLineGoesBackToFullRateAtOnce`, `testQuietForLongerSlowsDownFurther`, `testTextSeenLongAgoCountsAsNewAgain`. |
| AC-2 | ✅ pass | `toggleCaptureCardTranslation()` pause path → `await pipeline.stop()` → `tearDown` → `screenCapture.stopCapture()` (stream stopped), pipeline task cancelled, overlay/panel hidden. No data output exists. |
| AC-3 | ✅ pass | See below. |
| AC-4 | ⏳ pending owner | Steps below (also gives Req 2's baseline). |
| AC-5 | ⏳ pending owner | Steps below. |

### Build & test
```
Executed 265 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
```

### Changed files
```
 Resources/Info.plist                              | 1.19.0
 Sources/Services/CaptureCardChangeDetection.swift | OCRPacer: "nothing new to translate", 1 s / 2 s tiers
 Sources/Services/PipelineCoordinator.swift        | feeds texts + untranslated to the pacer, new log lines
 Sources/App/StatusBarController.swift             | ⌃⌥⇧V + menu item: pause/resume translation, menu note
 Tests/CaptureCardChangeDetectionTests.swift       | pacer tests replaced (5)
```

### Manual checks for the owner
`./build.sh`, OBS closed, ⌃⌥V, full screen (⌃⌘F), no regions, a dialogue screen.

**AC-4 (+ Req 2 baseline)** — (a) press **⌃⌥⇧V** (menu: "⏸ หยุดแปลชั่วคราว"), wait 2 min, run
`top -l 2 -n 6 -stats command,cpu -o cpu` and keep the second sample. (b) ⌃⌥⇧V again (translation on), wait
2 min on the same screen, run it again. Pass: GameTranslator (b) ≤ (a) + 15 %, WindowServer (b) ≤ (a) + 10,
kernel_task (b) not higher than (a). Please paste both samples — they decide Req 4. The log should show
`nothing new to translate` / `quiet for a while` lines and few `sent to OCR`.

**AC-5** — new dialogue → Thai ≤ ~2 s after it stops typing (log: `new text — OCR at full rate`).

### Proposed follow-ups
- Only if (b) WindowServer > (a) + 10: OCR frames straight from the capture card (`AVCaptureVideoDataOutput`,
  throttled, late frames dropped) instead of ScreenCaptureKit (Req 4).

---

## Review
**Cowork, 2026-09-26 — code passes; waiting for owner AC-4 (baseline a/b) and AC-5.** Evidence:
`build.noindex/Logs/Test` 16:15 (265 tests). Pause toggle stops the stream/OCR fully (⌃⌥⇧V); pacer now keys on
"new untranslated text not seen in 30 s", so the 7↔8 flicker can't reset it; tiered back-off 1 s → 2 s.
Req 4 deferred with a sound reason (WindowServer didn't move when the copy shrank 3×) — decided by the baseline.
No blocking findings.

**Owner AC-4, 2026-09-26** (full screen, no regions; `top -l 2`, single samples — noisy):
| | WindowServer | GameTranslator | kernel_task | coreaudiod | UVCAssistant |
|---|---|---|---|---|---|
| (b) translation on | 45.4 | 16.1 | 12.8 | 15.1 | 10.3 |
| (a) paused | 46.2 | 27.1 | 15.6 | 13.5 | 8.9 |
→ WindowServer is the picture itself (Req 4 not needed); kernel_task not higher with translation; AC-4 ✅.
Before T-0034/35: GameTranslator 43 %, kernel_task 22 %, 34 OCR/10 s → now 16 %, 13 %, 16 OCR/10 s.
Open: GameTranslator 27 % *while paused* (sample noise or real?) and the picture-only load → follow-up.
AC-5 ✅ owner: new dialogue → Thai in ~2 s. **DONE.** (New issue — the translation box keeps moving/changing on an unchanged line → T-0036.)

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-26 | → READY | Cowork | T-0034 made no difference in the owner's measurement |
| 2026-09-26 | READY → IN_PROGRESS | Claude Code | started |
| 2026-09-26 | IN_PROGRESS → REVIEW | Claude Code | test/code/build ACs pass; AC-4 (baseline), AC-5 manual pending owner |
| 2026-09-26 | — | Cowork | code review passed; waiting for owner AC-4/AC-5 |
| 2026-09-26 | REVIEW → DONE | Cowork | AC-4/AC-5 confirmed by owner |
