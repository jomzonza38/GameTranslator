# T-0029 — Capture card mode (3/3): Settings tab

| Field | Value |
|---|---|
| **Status** | PLANNED |
| **Type** | feature |
| **Priority** | P2 (normal) |
| **Version impact** | minor |
| **Milestone** | M7 — Capture card mode |
| **Depends on** | T-0028 |
| **Corrects** | — |
| **Follow-up** | — |
| **Created** | 2026-09-25 by Cowork |

> Amended 2026-09-26: default output is now a window on the Mac (T-0032). "Output Display" = **จอ Mac
> (ค่าเริ่มต้น)** or a connected TV/monitor (T-0027 path). "Fullscreen" = open in macOS full screen on the
> Mac / borderless on an external display.

## Objective
The owner can control TV Output from Settings: which display and devices, how the translation looks on
the TV, and how long a new line waits before it is translated.

## Context
- Builds on T-0027 (auto display/device choice) and T-0028 (overlay on the TV).
- Settings window: `Sources/Views/SettingsWindow.swift` (tabs). Settings persistence: `AppSettings`.

## Requirements
New tab **"TV Output"**:

| Setting | Meaning | Default |
|---|---|---|
| Enable TV Output | Switch showing and changing the *current* state (same as ⌃⌥V). Not persisted — off at launch. | OFF |
| Output Display | "จอ Mac" or a connected external display (TV/monitor). Saved by display name; a saved display that isn't connected falls back to the Mac and shows "(ไม่ได้ต่ออยู่)". | จอ Mac |
| Capture Card | Picker of capture devices; "อัตโนมัติ" = T-0027 rule. | อัตโนมัติ |
| Game sound | ปิด / อัตโนมัติ (card's own audio) / a listed audio device. | อัตโนมัติ |
| Resolution | Label "Native (ตามจอ TV)" — the TV mode is never changed; show the capture format in use. | Native |
| Fullscreen | ON = borderless over the whole TV (T-0027). OFF = normal resizable window on the TV. | ON |
| Show Translation | Hide/show the Thai boxes on the TV (OCR/translation keep running). | ON |
| Show Original Text | Original text under the Thai, TV only (the Overlay tab's setting stays for window mode). | OFF |
| Overlay Opacity | Whole TV overlay, 20–100 %. | 100 % |
| Translation Delay | Seconds a *new* line must stay on screen before it is sent for translation: 0 (current behaviour: as soon as it is stable), 0.5, 1, 1.5, 2. TV Output only. | 0 |

- Changing any of these while TV Output runs applies immediately (display/fullscreen → window rebuilt;
  look → redrawn even on a static screen). Device lists refresh when displays change and on a button.

## Out of scope
- Changing the TV's resolution. TV regions. Per-game profiles.

## Constraints
- CLAUDE.md stability rules apply. Thai UI strings.

## Files / Modules
- `Sources/Views/SettingsWindow.swift`, `Sources/Models/AppSettings.swift`, `Sources/Services/PipelineCoordinator.swift`,
  `Sources/Services/RegionPipelineState.swift` (delay), `Sources/Overlay/*`, `Tests/…`

## Acceptance Criteria
- **AC-1** [test] Translation Delay: 0 never holds a text back; with 1 s a new text is sent only after ≥ 1 s on screen.
- **AC-2** [test] Settings defaults as in the table; values persist (except Enable).
- **AC-3** [build] Unit tests and Release build succeed.
- **AC-4** [manual] Each setting changed while TV Output runs takes effect without restarting it.
- **AC-5** [manual] Two displays connected: picking the other one moves the output there; unplugging the
  picked one stops TV Output with a Thai message (T-0027 behaviour).
- **AC-6** [manual] Window translation's Overlay tab settings are unaffected by the TV ones.

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
| 2026-09-25 | → PLANNED | Cowork | split from T-0027; READY once T-0028 is DONE |
| 2026-09-26 | — | Cowork | amended: Mac window is the default output; external display optional |
