# T-0016 — A static screen must cost almost no CPU while capturing

| Field | Value |
|---|---|
| **Status** | REVIEW |
| **Type** | fix |
| **Priority** | P2 |
| **Version impact** | patch |
| **Milestone** | M4 — Performance & first use |
| **Depends on** | — |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-24 by Cowork (owner measurement during T-0015 review) |

## Objective
While capturing a game window that doesn't change (a dialog waiting for a click, or
while paused after a refused key), GameTranslator uses **~43 % CPU** on the owner's
MacBook Air. It should be close to idle. It was 0 % when not capturing.

## Context
- Measurements, 2026-09-24, v1.11.25: not started 0 %; static screen, everything
  translated ~43 %; paused ~43 %. Full `sample` output in the owner's
  `~/Desktop/gt-sample.txt` (10:17). Summary in the T-0015 Review.
- Hot path 1 — `StreamOutput.stream(...)` (`ScreenCaptureService.swift` ~l.300):
  `let context = CIContext()` **per frame**. The profile shows Metal context
  creation/destruction dominating the capture queue.
- Hot path 2 — Vision OCR runs on every delivered frame (static or not, paused or
  not), with `NSRegularExpression` built during OCR text cleaning.
- ScreenCaptureKit keeps delivering frames with image buffers for this window at the
  configured FPS (6), so "static screen → no frames" can't be relied on. T-0015's
  re-run must keep working either way.
- Audit v1.11.11 items 15 (`CIContext` per frame) and 16 (work on MainActor every
  frame) are related.
- Hints: one reused `CIContext`, or give Vision the `CVPixelBuffer` directly; skip
  OCR when the frame is unchanged (cheap pixel/downsampled hash) unless T-0015 work
  is waiting; while paused there is nothing to translate. The HOW is Claude Code's call.

## Requirements
1. Capturing a static window: GameTranslator CPU averages **≤ 10 %** (owner's
   `top` command below) with everything translated, and while paused.
2. A moving screen still gets translated as before (latency, typewriter text,
   T-0015 re-runs, stale grace, similar-text reuse).
3. No new crash or freeze paths (CLAUDE.md stability rules); no extra permission prompts.

## Out of scope
- The ~74 s first OCR after a new build (T-0017). FPS setting UI.

## Constraints
- CLAUDE.md stability rules apply.

## Files / Modules
- `Sources/Services/ScreenCaptureService.swift`, `Sources/Services/OCRService.swift`
- `Sources/Services/PipelineCoordinator.swift` if frame skipping lives there
- `Tests/…`

## Acceptance Criteria
- **AC-1** [code] No `CIContext` (or equivalent heavy object) is created per frame.
- **AC-2** [test] The "skip this frame" decision (if added) is unit-tested: unchanged frame → skip; changed frame, or T-0015 work waiting → process.
- **AC-3** [manual] Steps: TextEdit with a few English words, start, translate, don't touch it. Run `top -l 6 -s 5 -pid $(pgrep -x GameTranslator) -stats pid,cpu | grep -E '^[0-9]'` (ignore the first sample). Expected: average ≤ 10 %. Repeat while paused with key `sk-test`: ≤ 10 %.
- **AC-4** [manual] Steps: type new words into TextEdit while translating, then switch provider. Expected: new words translated as quickly as before; T-0015 AC-3 still passes.
- **AC-5** [build] Unit tests and Release build succeed.

## Testing Requirements
- AC-2 unit test; owner runs AC-3, AC-4.

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

- **Hot path 1 — `CIContext` per frame (AC-1):** `StreamOutput` now owns **one**
  `CIContext` for the stream's lifetime. It is used only on the capture queue.
- **Hot path 2 — OCR on every frame:** frames are skipped in two steps.
  1. **Capture queue:** `FrameFingerprint.of(pixelBuffer)` is a CRC-32 + Adler-32
     of every pixel row (row padding excluded) plus the size. It is **exact** — one
     changed pixel changes it — so a single new character of typewriter text is never
     missed. Measured **~2.9 ms per 2880×1800 frame ≈ 1.8 % of one core at 6 FPS**
     (zlib, hardware-accelerated). If the pixels equal the previous frame's, the image
     is **not converted to a `CGImage`**: the delegate receives `image: nil` plus the
     fingerprint.
  2. **Coordinator:** `FrameChangeFilter` (pure, unit-tested) remembers the
     fingerprints of the last 8 **processed** frames. A frame is skipped when its
     fingerprint is among them **and** the window hasn't moved **and** no text is
     waiting to become stable. Remembering several frames, not just the last one,
     also covers things that blink between a few states: TextEdit's caret (present in
     AC-3's test window) or a game's "▼ next" arrow.
- **Why "text waiting to become stable" forces processing:** the stability gate needs
  the same text in two runs before it translates. When new text appears, the next
  identical frames are therefore still processed (latency as before, Req 2) until it
  is translated. `isWaitingForStableText` comes from `planRerun` and is false while
  paused.
- **Why a moved window forces processing:** the overlay only repositions when the
  pipeline runs (`OverlayWindowController.windowTrackingTimer` is never started). So
  a frame with the same pixels but a different `currentWindowFrame` is processed.
- **"Processed" is recorded when a frame actually runs** (in `drainPipeline`), not when
  it is queued. A frame that was queued and then replaced before running is never
  marked as seen.
- **T-0015 re-runs** call `processFrame(lastFrame)` directly and bypass the filter.
  Paused static screen: frames are skipped, and T-0015 schedules nothing, so the app
  is idle apart from receiving and fingerprinting frames.
- **Also:** `OCRService.cleanOCRText` built an `NSRegularExpression` for every
  recognised line; it is now a `static let`.
- **Not measured here:** the CPU of the running app (AC-3). Launching a build other
  than the installed one would ask for Screen Recording permission (stability rule
  1), so the owner measures it after `./build.sh`. Expected per static frame: receive
  + fingerprint (~3 ms), no image conversion, no OCR.

## Result

**Outcome:** PARTIAL — `[code]`/`[test]`/`[build]` criteria pass; AC-3 and AC-4 pending owner
**Version:** 1.11.25 → 1.11.26
**Commit:** not committed (owner asked for T-0016 and T-0017 first, review after)

### Acceptance criteria
| AC | Result | Evidence |
|---|---|---|
| AC-1 | ✅ pass | `StreamOutput.ciContext` created once per stream; no `CIContext()` in the per-frame path. Identical frames skip `createCGImage` entirely. |
| AC-2 | ✅ pass | `FrameChangeFilterTests` (8): unchanged → skip; changed / moved window / work waiting → process; blink between states → skip; capacity; reset. `FrameFingerprintTests` (4): same pixels, one changed pixel, row padding ignored, size. |
| AC-3 | ⏳ pending owner | Steps below. |
| AC-4 | ⏳ pending owner | Steps below. |
| AC-5 | ✅ pass | `Executed 115 tests, with 0 failures`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`. |

### Build & test
```
Executed 115 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
fingerprint benchmark: 2.94 ms / 2880×1800 frame (crc32 + adler32)
```

### Changed files
```
 Resources/Info.plist                         | 1.11.26
 Sources/Services/ScreenCaptureService.swift  | FrameFingerprint, shared CIContext, image nil for identical frames
 Sources/Services/PipelineCoordinator.swift   | CapturedFrame, FrameChangeFilter, handleCapturedFrame, isWaitingForStableText
 Sources/Services/OCRService.swift            | regex built once
 Tests/FrameSkippingTests.swift               | (new, 12 tests)
```

### Manual checks for the owner
After `./build.sh`:

**AC-3** — TextEdit with a few English words, start, let it translate, don't touch it:
```
top -l 6 -s 5 -pid $(pgrep -x GameTranslator) -stats pid,cpu | grep -E '^[0-9]'
```
Ignore the first sample. Expected average ≤ 10 %. Repeat while paused with key
`sk-test`: ≤ 10 %.

**AC-4** — type new words into TextEdit while translating (and type a sentence
character by character): new words are translated as quickly as before. Then switch
provider: T-0015 AC-3 still passes (Google/Claude translation appears on the
untouched window).

### Proposed follow-ups
- If AC-3 is still above 10 %, the next cost is the frame delivery itself (6 FPS,
  2× window size). A lower FPS while nothing changes would be a separate task (FPS is
  out of scope here).

---

## Review

## Status history
| Date | Change | Who | Note |
|---|---|---|---|
| 2026-09-24 | → READY | Cowork | from T-0015 review (sample: CIContext per frame + OCR every frame) |
| 2026-09-24 | READY → IN_PROGRESS | Claude Code | started (owner: do T-0016 and T-0017, review after) |
| 2026-09-24 | IN_PROGRESS → REVIEW | Claude Code | code/test/build ACs pass; AC-3, AC-4 manual pending owner |
