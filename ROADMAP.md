# ROADMAP — GameTranslator

Owned by **Cowork** (WHAT and WHY). Claude Code reads it for context but does not
change goals or priorities. Workflow: `WORKFLOW.md`.

## Product

macOS menu bar app that reads text from a game window (ScreenCaptureKit + Vision
OCR), translates it to Thai (Google, DeepL, OpenAI, Claude) and shows it as an
overlay or floating panel. Users: Thai players of English / Japanese / Chinese /
Korean games. Current version: see `CFBundleShortVersionString` in
`Resources/Info.plist` (1.11.19 on 2026-09-24).

## Standing quality goals (always in force)

From the owner — every task must keep these (details in `CLAUDE.md`):
1. Rebuilding never brings back the Screen Recording permission prompt.
2. The app never crashes or freezes after it asks the user to reopen, or when the
   game is closed and started again.
3. The build and unit tests never break.

## Milestones

| Milestone | Goal | Status | Tasks |
|---|---|---|---|
| M0 — Workflow | Cowork × Claude Code task system in place | done 2026-09-23 | — |
| M1 — Stability | Close the gaps found in the 2026-09-23 audits that affect the standing goals | done 2026-09-24 | T-0001 … T-0005 |
| M2 — Reliability & UX | Errors visible to the user, no request storms, correct placement on every display | done 2026-09-24 | T-0006 … T-0009 |
| M3 — Providers & settings hygiene | Keys saved cleanly, right cache per provider, no endless retries on a refused key, clean test logs | done 2026-09-24 | T-0010 … T-0015 (T-0012 corrected by T-0015) |
| M4 — Performance & first use | Near-idle CPU on a static screen; no silent minute-long wait on the first OCR | done 2026-09-24 | T-0016, T-0017 |
| M5 — Know where each translation came from | When the whole window is translated (text in many places, e.g. Graveyard Keeper), the player can tell which translation belongs to which text | done 2026-09-24 | T-0018, T-0019 (→ T-0020), T-0021 |
| M6 — Learn the language from the games you play | Words and sentences the app translated are kept per game; the player sees what each word/sentence means, practises with a multiple-choice quiz and can ask an AI why a line was translated that way | done 2026-09-24 (fix T-0026 open) | T-0022 … T-0025, T-0026 |

## Backlog (not yet tasks)

Untriaged items. Cowork decides priority and turns them into tasks; remove an item
here once it has a task ID (link the task instead).

### From the 2026-09-23 code audit (Claude Code)
Already fixed on 2026-09-23 (1.11.6 – 1.11.11): Google Free `&`/`+` encoding,
Google batch line shifting, DeepL Free quota counting other providers, OCR `...`
collapse, concurrent pipelines, in-flight work after stop.

Remaining (now tasks): failed start → T-0001.

### From the 2026-09-23 code audit v1.11.11 (Cowork)
Full report: project doc `claude/code-audit-2026-09-23-v1.11.11.md`.
Turned into tasks: game window closed while capturing → T-0002 · stop during start
→ T-0003 · build.sh hides signing failures → T-0004 · OCR double resume → T-0005 ·
errors never shown in the menu → T-0006 · Esc in region selector hides overlay →
T-0007 · batch fallback request storm → T-0008 · multi-monitor coordinates → T-0009.

### Backlog (not yet tasks)
- → T-0011 · **LLM chatter fallback is cached forever** — when a model replies with chatter,
  `LLMPrompt.sanitize` returns the source text, which is then cached as the
  "translation" and never retried until the glossary changes or the app restarts.
- → T-0011 · **Translation cache ignores the provider** — after switching provider, cached
  lines still show the previous provider's translation.
- **`build.sh` may reset the Screen Recording grant** — `rm -rf` + copy and
  `codesign --deep` are still suspected (see `CLAUDE.md` gotchas). T-0004 only makes
  signing failures visible. Related to stability goal 1. From T-0004: sign and
  verify the build output *before* replacing the installed app, so a failed
  signature never leaves a broken copy in /Applications.
- → T-0010 · **API key field** — every keystroke writes the Keychain, creates a new provider and
  a new `URLSession` that is never invalidated (leak) and sends a warm-up request;
  keys are not trimmed (pasted whitespace → 401).
- **Game window resize / FPS change while running** — stream size is fixed at start
  (`frame × 2`); `updateFrameRate` is never called.
- **Test coverage gap** — providers, `OCRService` and `PipelineCoordinator` have few
  or no unit tests; most recent bugs were in these areas.
- Minor: data races hidden by `@unchecked Sendable` (OCR settings, provider swap,
  AppSettings read off-main); `overlayBackgroundOpacity = 0` not persisted (`nonZero`);
  DeepL 403 shown as "API key not set", DeepL >50 texts per request; Google Cloud key
  in URL query; `CIContext` per frame; `TranslationCache` LRU O(n); TextTracker /
  layout on the main actor every frame; `GameLog` not thread-safe and logs all game
  text to the Desktop; several window pickers can be open at once.
- → T-0013 · **Unit tests write the owner's log** — the test host is the app, so `GameLog`
  lines from tests land in `~/Desktop/GameTranslator.log` (seen 2026-09-23 23:49).
- From T-0008: typed HTTP status in `TranslationError` instead of "HTTP 401: …" text.
- From T-0009: overlay text `contentsScale` uses `NSScreen.main` — may blur on a
  Retina + non-Retina pair.
- → T-0012 · **Auth errors retried forever** — with an invalid key the pipeline retries every
  ~3 s for as long as text is on screen (seen 2026-09-24, HTTP 401). Pause
  translation (or back off much longer) after 401/403 until the key changes.
- From T-0011 review: a line the LLM always answers with chatter is retried every 3 s
  for as long as it is on screen (one paid request each time). Consider a growing
  back-off or a retry cap for chatter.
- → T-0017 · First OCR after launching a new build takes ~74 s.
- → T-0016 · CPU ≈ 43 % on a static screen (`CIContext` per frame + OCR on every frame).
- From T-0017: sign the Verify/unit-test builds with the same Apple Development certificate as
  `build.sh`, so tests and app share one Vision model cache (no ~74 s first OCR after each
  Claude Code verify). Risk: a test host with the same bundle ID + certificate may touch the
  Screen Recording grant (stability goal 1) — owner to decide before it becomes a task.
- From T-0016: a game whose background keeps moving still gets OCR on every frame (6 FPS).
  Measure in a real game first; if it's heavy → adaptive FPS / region-only change detection.

### From the 2026-09-24 "where did this translation come from" discussion (owner + Cowork)
Already in place (no task needed): OCR lines merged into blocks (`RegionLayout.mergeAdjacentLines`),
frame-to-frame tracking (`TextTracker`), stability gate for typewriter text, region mode
(colour bar + name in the panel, OCR cropped to the region). Tasks: T-0018, T-0019.
- From T-0018/T-0019 review: key panel pictures and entry ids by text **and position**, so the
  same text shown twice gets its own picture and the hover never jumps between the copies.
- From owner's test 2026-09-24: number-only texts ("15", "10", "7/1" read as "71") fill the panel
  and get sent for translation. Skip or pass through texts with no letters.
- From T-0020 review: a resize `Task` still awaiting `updateConfiguration` when translation is
  stopped and restarted can write its size into the new session — guard with the stream identity.
- **CPU bursts in a real game** (owner, M5 check): top 12:29:13–38, v1.11.31, Graveyard Keeper: 0.0 / 28.4 / 57.0 / 31.4 / 7.9 / 7.1 % — settles ≤ 10 % (T-0016 goal), bursts of 30–57 % for ~15 s. Find what
  runs during a burst (log: OCR count/time per run, frame changes, capture resizes) before deciding a
  fix. Related: T-0016 follow-up about games whose background keeps moving; round 2 of T-0020 also
  made full-screen frames ~10 % larger (no longer scaled down).
- Numbered badges (①②③) on the game next to each text, same number in the panel.
  Decide after T-0018/T-0019 whether it is still needed.
- Panel order: newest text first with a "ใหม่" marker, instead of top-to-bottom
  (`TranslationPanelData.update` sorts by `minY`). Owner to decide which order he prefers.
- Tell dialog / tooltip / HUD apart in full-screen mode (static HUD → cache and push
  down; tooltip → short-lived). Only if the panel still feels cluttered after M5.

### From the 2026-09-24 learning-menu request (owner + Cowork)
Owner decisions: learning data saved permanently per game; word meanings from AI when an
LLM key exists, else Google Free; the chat AI is chosen in Settings. Tasks: T-0022 … T-0025.
- Later, if wanted: spaced repetition across days, export to Anki/CSV, text-to-speech.
- From the M6 audit (low, not yet tasks):
  - `LearningStore.shared` loads `learning.json` synchronously on the main actor at the first
    translation — preload off the main actor at launch if the file grows large.
  - The open Learning window re-filters and re-sorts the whole list on every new translation.
  - หยุด then หาความหมาย again: the old task's `defer` clears `isWorking` while the new batch
    runs; opening another word during a batch silently skips its auto lookup.
  - Changing the game picker during a quiz keeps the old questions and records answers into
    the new game.
  - Editing the key in "AI สำหรับแชทเรียนรู้" calls `pipeline.updateProvider()` even when it
    isn't the translation provider's key.
  - A word's chat sends the word as "Game line" without its example sentence.
