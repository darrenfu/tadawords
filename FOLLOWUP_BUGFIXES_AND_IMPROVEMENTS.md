# Tada Words — Follow-up Bug Fixes & Improvements

This is the single source of truth for work discovered after the original V1
design. Product/design documents describe the current intended behavior; this
log records why it changed, which version contains it, and how it was verified.

## Versioning workflow

- `main` contains the latest accepted baseline.
- Each product iteration uses a semantic-version branch such as `v0.2`, `v0.3`.
- Daily work is grouped below by local date (`America/Los_Angeles`).
- Fix-only follow-ups use patch releases such as `v0.2.1`.
- A version is tagged only after automated checks, fresh LocalQA installation,
  and the listed physical-device checks pass.
- Replay, screenshots, simulator results, and automated tests may support an
  item, but child speech/handwriting and audible prosody require human device QA.

## Status vocabulary

- `Planned`: accepted, not yet implemented.
- `In progress`: implementation is active.
- `Automated pass`: targeted automated checks pass; device QA remains.
- `Device QA pending`: included in the device build and waiting for human check.
- `Accepted`: physically verified and included in an accepted version.

## v0.2 — 2026-07-12

Target release: `v0.2.0`

Branch: `v0.2`
Overall state: implementation and regression testing in progress.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V02-BUG-001 | Bug | Navigation | A normal tap on `Parents` must open the math Parent Gate. | Automated pass | Tap on iPhone and iPad; gate opens once. |
| V02-BUG-002 | Bug | Results | Replay icon must be a real button that starts the same mode again. | Automated pass | Complete both modes, tap Replay, verify `Practice Again` starts and grants no duplicate permanent reward. |
| V02-BUG-003 | Bug | Read recognition | Recording must not fail forever or succeed instantly without usable child speech. Permission, voice activity, endpointing, and Apple callback races must fail neutrally. | Automated pass | Silence, background audio, short sight words, normal child voice, and two retries on a physical device. |
| V02-IMP-001 | Improvement | Read | A new Profile/new word must not hear the target before the first independent response. | Automated pass | Enter Read with a fresh Profile and confirm silence until the child acts. |
| V02-IMP-002 | Improvement | Rewards | Three stars must be attainable: one immediate unaided recovery is allowed, calibration can earn Pace, and the slow side gets 25% grace. Guardian accuracy remains strict. | Automated pass | Run first-try, one-recovery, calibration, slow-grace, too-fast, and helped cases. |
| V02-IMP-003 | Improvement | Launch | Launch is Profile-first. No Profile opens `New Kid`; returning launch highlights the last valid Profile for child confirmation. No word entry appears in first-run setup. | Automated pass | Clean install, one Profile, multiple Profiles, deleted-last-Profile, and restart checks. |
| V02-IMP-004 | Improvement | Parent Words | Replace old Quick Add with Read/Write tabs, one-word Return-to-add, newest-first live queue, local Camera/Photo OCR preview, same-pool dedupe, single/bulk delete, confirmation, and Undo. | Automated pass | Type/Return, multiword OCR from both sources, duplicate import, batch order, single delete, bulk delete/Undo on iPhone and iPad. |
| V02-IMP-005 | Improvement | Word sourcing | V1 must never add Grade/catalog/smart-fill words. Every Pool entry comes from a parent typing or OCR; an undersized Pool stays undersized. | Automated pass | Empty and undersized Pool remain unchanged across launch and quest preparation. |
| V02-IMP-006 | Improvement | Write audio | Write reference pronunciation is slower and keeps final consonants audible, including the `t` in `at`. | Automated pass | Listen to `at`, `cat`, `look`, `go`, and `I` on the target phone/tablet. |
| V02-IMP-007 | Improvement | Read help | Only after two valid wrong readings, reveal `Hear it` and `See it`. `Hear it` is child-triggered standard pronunciation; `See it` shows a local picture beside known words. Unknown words must not receive guessed pictures. | Automated pass | Confirm hidden at 0/1 wrong, visible at 2 wrong, technical retries do not unlock, `dog` shows a dog, unknown word fails closed. |
| V02-IMP-008 | Improvement | Voice | Prefer an available youthful American-English female system voice, with deterministic natural-voice fallbacks. | Automated pass | Listen on target devices; confirm no missing/downloaded voice causes silence. |
| V02-IMP-009 | Improvement | Sonic logo | Launch is one natural phrase, `tā-'dá, wòrds!` (owner approximation: `它达，沃尔子`): continuous `tah-DAH`, stress on the second syllable, a 105ms comma pause, and a lower landing on `words`, without three robotic utterance seams. | Automated pass | Cold-launch listening check against the owner reference with Voice on/off and three World themes. |
| V02-IMP-010 | Improvement | Princess theme | Moonpetal adds original rainbow/unicorn details and a more upbeat, varied game-like score without covering learning controls or leaking into other themes. | Automated pass | Visual check in both landscape directions, Reduce Motion, music ducking, and recording fade-out. |
| V02-IMP-011 | Improvement | Cosmetics | Completing both Read and Write Today Quests on one local day unlocks one unearned Theme and Icon on the following day. Replay and partial days do not count; late launch catches up idempotently. | Automated pass | Same-day lock, next-day unlock, partial day, replay, duplicate completion, cross-month, restart, and per-Profile isolation. |
| V02-IMP-012 | Improvement | My Collection | Kid gets a separate screen to view and select earned Themes and Icons. Locked items are previews only; original photo avatar data is retained. | Automated pass | Select, restart, switch Profile, select photo/icon/theme, and verify persistence/isolation. |
| V02-IMP-013 | Improvement | Read matching | Slightly relax pronunciation equivalence for close Mandarin-L1 forms such as target `come` recognized as `kum/cum`, without accepting different words such as `some`, `home`, `came`, `cat/cap`, or bypassing audio/speaker confidence gates. | Automated pass | Curated positive/negative policy tests plus target-child device trials for `come` and other representative words. |
| V02-IMP-014 | Improvement | Lobby | Remove the noninteractive current-theme text pill from the upper-right header because it looks tappable. Theme identity remains in the scene and My Collection selection. | Automated pass | Verify the header is balanced on iPhone/iPad landscape and contains no dead-looking control. |
| V02-IMP-015 | Improvement | Worlds | Expand the original three Worlds to eight with five isolated, original themes: Dino Discovery, Firehouse Heroes, Brickwork City, Frostlight World, and Coaster Carnival. Each needs its own palette, edge-safe scene, mascot, rewards, and music identity. | Automated pass | Preview all eight on phone/tablet, both landscape directions, Quest dimming, Reduce Motion, music ducking, and next-day unlock order. |
| V02-IMP-016 | Improvement | Treasures | Every World has 25 relevant, visually distinct treasure icons. Locked treasures keep their own grayed artwork with a lock badge instead of becoming a generic lock. | Automated pass | Check 200 catalog entries, per-World uniqueness, symbol availability, locked/earned/current states, and compact grids. |
| V02-IMP-017 | Improvement | Profile avatar | A collected treasure can be selected as the child avatar; locked treasures cannot. Switching among treasure, earned animal icon, and original photo preserves the source photo and sync metadata. | Automated pass | Select/restart/switch Profile/sync, reject locked treasure, and confirm all child-facing avatar surfaces match. |
| V02-IMP-018 | Improvement | Mascots | Replace the shared two-dots-and-line placeholder face with friendly, World-specific, pose-aware expressions for resting, cheering, encouraging, and rescue states. | Automated pass | Inspect all eight mascots and four poses with Reduce Motion on/off; emotions remain friendly and legible at compact size. |
| V02-IMP-019 | Improvement | Write controls | `Clear` removes all writing immediately without confirmation. The single `?` icon immediately reveals the word and records guidance; no Help text or three-choice sheet remains. | Automated pass | Test nonempty/empty Clear, VoiceOver feedback, one-tap reveal, repeat reveal, timer behavior, and guidance scoring. |
| V02-IMP-020 | Improvement | Write tools | Add Pencil, Crayon, Chalk, and Brush tools plus 12 independently selectable basic colors, with persistent distinct stroke styles and gentle per-stroke movement sounds. Replace Undo with a local eraser whose path is 2.5× the active pen width; retain one-tap Clear. | Automated pass | Draw/switch tools/colors/erase partial strokes with finger and Pencil; verify old strokes retain style/color, recognition input, sound throttling, reduced-sound policy, compact layout, and no prompt-audio masking. |
| V02-IMP-021 | Improvement | Read presentation | Read words use a stable, high-contrast color selected from the active World palette for each attempt, with enough variation across words and no redraw flicker. | Automated pass | Verify all eight World palettes, deterministic redraw/rotation, WCAG contrast, and visible variety across a quest. |
| V02-IMP-022 | Improvement | Parent navigation | Rename the child-facing entry to `Parents`. Parent setup/management routes support portrait and landscape on iPhone/iPad; all child routes remain landscape-only and restore landscape immediately on exit. | Automated pass | Policy tests and iPad simulator window shapes pass. Rotate every Parent route on physical devices, return through Parent Gate, and confirm Profile/Lobby/Quest/Badge remain landscape in both landscape directions; iPhone raw simulator framebuffer captures are not acceptance evidence. |
| V02-IMP-023 | Improvement | Child visual style | Refine child-facing typography, microcopy, shapes, and decorative rhythm to feel cuter and more inviting for a Pre-K child while preserving large touch targets, reading contrast, and distinct World identities. | Automated pass | Fresh phone/tablet Profile, Lobby, Read, and Result captures pass. Complete Dynamic Type, VoiceOver, and a short target-child navigation/appeal observation on physical devices. |
| V02-IMP-024 | Improvement | Lobby | Move the former `Collection — See your world treasures` strip into the upper-right header as a compact `Badge` button that opens the same earned-cosmetics screen. | Automated pass | iPhone landscape capture shows the four-item header fits and the bottom strip is gone; physically tap Badge on phone/tablet to confirm navigation. |

## Daily notes

### 2026-07-12

- Created `v0.2` from accepted `main` baseline `ca76fcf`.
- Physical iPhone first-pass feedback defined `V02-BUG-001` through
  `V02-IMP-005`.
- Added speech, hint, voice, theme/audio, and next-day cosmetic requirements.
- Reworked the sonic logo from three queued speech fragments into one SSML
  phrase matching the owner reference `tā-'dá, wòrds!`.
- Added conservative Mandarin-L1 pronunciation-equivalence tuning for Read.
- Removed the misleading noninteractive theme label from the Lobby header.
- Expanded the World catalog from three to eight without changing the first
  three unlock positions, and added distinct procedural scenes/music.
- Added 25 stable treasure icons per World, locked-icon previews, and collected
  treasure avatar selection while preserving the source photo.
- Replaced placeholder mascot faces with pose-aware expressions.
- Simplified Write Clear and Help, then added a four-tool writing/eraser design.
- Added 12 independent pen colors and theme-aware Read word color variation.
- Renamed the Parent entry, scoped portrait support to Parent routes, and kept
  every child route landscape-only.
- Moved Collection from the Lobby body to a compact upper-right `Badge` entry.
- Opened a focused Pre-K visual-style refinement pass; fresh screenshots and
  target-child observation remain required before acceptance.
- Completed the branch-wide Swift suite: 479/479 passed with zero failures
  before the focused Phase 1 presentation test was added.
- Built the LocalQA app successfully for iPhone 17 Pro Max and iPad Pro 13-inch
  (M5) simulators. Fresh signed physical-device installation remains open.

### 2026-07-13

- Promoted `V02-IMP-022` to Automated pass after orientation-policy coverage
  and iPad simulator Parent/child window-shape evidence. iPhone raw framebuffer
  orientation remains inconclusive, so real-device rotation is still required.
- Promoted `V02-IMP-024` to Automated pass after the iPhone landscape capture
  showed the four-item header fitting without the former bottom Collection
  strip. Physical Badge tap-through remains required.
- Promoted `V02-IMP-023` to Automated pass after the approved Phase 1 visual
  refinement: the remembered Profile is statically emphasized; iPhone Lobby
  uses a 48-point icon dock inside 72-point touch frames while iPad retains
  labels; Lobby/Read/Result mascots, the iPad Read card and word, and Result
  reward/replay emphasis are larger through centralized child-scale tokens.
- Reviewed fresh Profile, Lobby, Read, and Result captures on iPhone 17 Pro Max
  and iPad Pro 13-inch (M5). No clipping, overlap, or World-identity leakage was
  observed; physical Dynamic Type, VoiceOver, and target-child appeal remain.
- Completed the post-refinement branch-wide suite: 480/480 passed with zero
  failures, and both LocalQA simulator builds passed.
- Locked the launch-voice implementation target to one continuous `tah-DAH`
  SSML phrase, a 105ms pause, and a lower `words`, matching
  `tā-'dá, wòrds!` / `它达，沃尔子`; device listening approval remains open.

## Device acceptance record

To be filled after the final `v0.2.0` candidate is installed.

| Date | Device | Build/version | Tester | Result | Notes/evidence |
|---|---|---|---|---|---|
| Pending | iPhone 17 Pro Max | `v0.2.0` candidate | Parent + child | Pending | Full checklist above. |
| Pending | iPad Pro 13-inch (M5) | `v0.2.0` candidate | Parent + child | Pending | Full checklist above. |
