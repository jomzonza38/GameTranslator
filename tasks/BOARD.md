# Task Board

Index of all tasks. The **Status line inside each task file is the source of
truth**; whoever changes a status updates this row in the same step.
Lifecycle and who may set each status: `WORKFLOW.md` §3.

**Next ID:** T-0037

## Active

| ID | Title | Status | Priority | Depends on | Next step by |
|---|---|---|---|---|---|
| [T-0036](T-0036-translation-box-stays-still.md) | The translation box stays still while the dialogue doesn't change | REVIEW | P1 | — | Owner (manual AC-5) — committed `e5d9101` |
| [T-0029](T-0029-tv-output-settings.md) | Capture card mode (3/3): Settings tab (Mac / external display, look, delay) | PLANNED | P2 | T-0035 | Cowork (READY after T-0035) |

## Closed

<!-- Move rows here when a task becomes DONE, REVIEW_FAILED or CANCELLED. -->

| ID | Title | Final status | Closed | Commit | Follow-up |
|---|---|---|---|---|---|
| [T-0001](T-0001-start-failure-leaves-running-state.md) | A failed start must not leave the app stuck in "running" | DONE | 2026-09-23 | `4df883b` | — |
| [T-0008](T-0008-batch-fallback-no-request-storm.md) | A failed batch request must not turn into a storm of per-line requests | DONE | 2026-09-23 | `6e589be` | — |
| [T-0002](T-0002-game-window-closed-while-capturing.md) | Closing the game while translating must stop cleanly and tell the user | DONE | 2026-09-24 | `275e90d` | — |
| [T-0005](T-0005-ocr-continuation-resumed-once.md) | OCR must never resume its continuation twice | DONE | 2026-09-24 | `878b62f` | — |
| [T-0009](T-0009-multi-monitor-coordinates.md) | Overlay, panel and region selector placed correctly on multi-monitor setups | DONE | 2026-09-24 | `7574368` | — |
| [T-0003](T-0003-stop-during-start-leaves-orphan-stream.md) | Stopping while a session is starting must not leave capture running | DONE | 2026-09-24 | `99117eb` | — |
| [T-0004](T-0004-build-sh-must-fail-on-signing-error.md) | build.sh must stop loudly when code signing fails | DONE | 2026-09-24 | `7a9618f` | — |
| [T-0006](T-0006-menu-shows-live-errors-and-status.md) | The menu must show the current error, status and stats | DONE | 2026-09-24 | `0c8273a` | — |
| [T-0007](T-0007-cancel-region-selector-restores-overlay.md) | Cancelling region selection must bring the overlay back | DONE | 2026-09-24 | `a6be575` | — |
| [T-0013](T-0013-tests-do-not-write-owner-log.md) | Unit tests must not write to the owner's GameTranslator.log | DONE | 2026-09-24 | `7c3eced` | — |
| [T-0014](T-0014-outdated-refusal-must-not-pause.md) | A refusal from an outdated request must not pause translation | DONE | 2026-09-24 | `a4a0760` | — |
| [T-0010](T-0010-api-key-fields-save-cleanly.md) | API key fields must save cleanly: trimmed, not on every keystroke, no session leak | DONE | 2026-09-24 | `0f15d05` | — |
| [T-0011](T-0011-cache-per-provider-no-chatter-caching.md) | Cached translations must belong to the provider and language that made them | DONE | 2026-09-24 | `5beb3ad` | — |
| [T-0012](T-0012-pause-on-refused-api-key.md) | Stop retrying while the API key is refused, and say so | REVIEW_FAILED | 2026-09-24 | `2cd55eb` | T-0015 |
| [T-0015](T-0015-resume-on-static-screen.md) | Resuming, switching provider and retrying must work on a static screen | DONE | 2026-09-24 | `ce43c16` | — |
| [T-0016](T-0016-idle-cpu-while-capturing.md) | A static screen must cost almost no CPU while capturing | DONE | 2026-09-24 | `8fd9f5e` | — |
| [T-0017](T-0017-slow-first-ocr-after-new-build.md) | Find out why the first OCR after a new build takes ~74 s | DONE | 2026-09-24 | `85a0893` | — |
| [T-0019](T-0019-hover-panel-entry-highlights-source.md) | Pointing at a panel entry highlights its text in the game | REVIEW_FAILED | 2026-09-24 | `0acb92a` | T-0020 |
| [T-0018](T-0018-panel-shows-source-thumbnail.md) | In full-screen mode, each panel entry shows where its text came from | DONE | 2026-09-24 | `c47e4ce` | — |
| [T-0020](T-0020-map-captured-content-to-screen.md) | Outlines and overlay text must sit exactly on the game text | DONE | 2026-09-24 | `6730abe` + `baf4aa9` | — |
| [T-0021](T-0021-point-at-game-text-scrolls-panel.md) | Pointing at a text in the game brings its translation into view in the panel | DONE | 2026-09-24 | `6dbbafa` | — |
| [T-0022](T-0022-learning-collection-window.md) | Learning window: every sentence and word the app has translated, kept per game | DONE | 2026-09-24 | `156a639` | T-0026 |
| [T-0023](T-0023-word-meanings.md) | Each word and sentence in the Learning window explains what it means | DONE | 2026-09-24 | `b8ad367` | T-0026 |
| [T-0024](T-0024-learning-quiz.md) | Multiple-choice quiz on the words and sentences collected from the game | DONE | 2026-09-24 | `2717f05` | — |
| [T-0025](T-0025-ask-ai-about-a-translation.md) | Ask the AI why a sentence was translated that way | DONE | 2026-09-24 | `141cba0` | T-0026 |
| [T-0026](T-0026-learning-data-correctness.md) | Learning data stays correct: per-game language, ordered saves, clean clear | DONE | 2026-09-24 | `b7803cf` | — |
| [T-0027](T-0027-tv-output-capture-card.md) | TV Output (1/3): capture card picture on the TV, without OBS | REVIEW_FAILED | 2026-09-26 | `fe07ca3` | T-0030 |
| [T-0031](T-0031-no-duplicate-app-copies.md) | Only the installed app shows up in Spotlight / Apps, never build copies | DONE | 2026-09-26 | `3ae8e0f` | — |
| [T-0030](T-0030-tv-output-frame-rate-and-format.md) | TV Output: set the capture frame rate safely and keep the chosen format | REVIEW_FAILED | 2026-09-26 | `f3201bf` | T-0033 |
| [T-0032](T-0032-capture-card-window-on-mac.md) | Switch picture in a window on the Mac (capture card, no OBS) | DONE | 2026-09-26 | `f221522` | T-0033 |
| [T-0033](T-0033-capture-at-60fps.md) | Capture card runs at 60 fps when the card offers it | DONE | 2026-09-26 | `52b0c56` | — |
| [T-0028](T-0028-tv-output-translation-overlay.md) | Capture card mode (2/3): Thai translation over the Switch picture | REVIEW_FAILED | 2026-09-26 | `a1f83a3` | T-0034 |
| [T-0034](T-0034-translation-must-not-slow-the-game.md) | Translating the Switch picture must not slow the game down | REVIEW_FAILED | 2026-09-26 | `fe63cd6` | T-0035 |
| [T-0035](T-0035-capture-card-translation-cpu.md) | Capture card translation: pacer on 'nothing new', pause toggle | DONE | 2026-09-26 | `0020c1d` | — |
