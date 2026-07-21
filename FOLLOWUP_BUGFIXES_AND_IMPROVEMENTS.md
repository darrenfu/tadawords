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
Overall state: merged to `main` by PR #1 at merge commit `7728f28`; physical-device acceptance remains open.

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
| V02-IMP-009 | Improvement | Sonic logo | Launch is one natural phrase, `Ta-dá↗ woooords↘!` (owner approximation: `它达，沃尔子`): `da` rises slightly and leads directly into a clearly lengthened, falling `wor`, without a deliberate comma pause or robotic utterance seams. | Implemented; device listening pending | Cold-launch listening check against the owner reference with Voice on/off and three World themes. |
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
- Updated the launch-voice target to one continuous `Ta-dá↗ woooords↘!`
  phrase: `da` rises and joins directly into a longer, falling `wor`, matching
  `它达，沃尔子`; device listening approval remains open.

## Device acceptance record

To be filled after the final `v0.2.0` candidate is installed.

| Date | Device | Build/version | Tester | Result | Notes/evidence |
|---|---|---|---|---|---|
| Pending | iPhone 17 Pro Max | `v0.2.0` candidate | Parent + child | Pending | Full checklist above. |
| Pending | iPad Pro 13-inch (M5) | `v0.2.0` candidate | Parent + child | Pending | Full checklist above. |

## v0.3 — 2026-07-13

Target release: `v0.3.0`

Branch: `v0.3`
Baseline: `main` at `7728f28`, which merged v0.2 through PR #1.
Overall state: merged to `main` by PR #2 at merge commit `cc42e17`; human physical-device acceptance remains open.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V03-BUG-001 | Bug | OCR import | `Add all N to Read/Write` must remain tappable after recognition and must show progress or an actionable error while saving. | Automated pass | Recognize a photo, dismiss the keyboard, tap the sticky Add All action once, and verify the Pool changes exactly once. |
| V03-BUG-002 | Bug | Voice setup | Voice setup must record usable enrollment samples instead of showing a generic error or leaving Finish disabled. Configure the audio session before reading the input format and preserve accepted progress when a sample is rejected. | Automated pass | Complete setup on a physical device, including one rejected sample, interruption, retry, and final save. |
| V03-BUG-003 | Bug | Write canvas | Short dots, later letters, and connected strokes must remain in the drawing. Writing sound must use cached, throttled playback without stutter. | Automated pass | Write `i`, a three-letter word, and connected `vv`/`w` with each tool; listen for gaps, clipping, or repeated startup noise. |
| V03-BUG-004 | Bug | Parent Gate | A wrong full-length answer must auto-clear without making its error feedback flash and disappear. Keep the message visible until the parent starts the next answer. | Automated pass | Enter a wrong answer, observe the cleared field and persistent message, then type the next digit and confirm the message dismisses. |
| V03-BUG-005 | Bug | Quest transition | Advancing to the next word must not rebuild the root Quest shell or change its transition identity. | Automated pass | Record a multiword Write Quest frame by frame and confirm the canvas coordinate space stays fixed during each advance. |
| V03-BUG-006 | Bug | Quest feedback | Read `You got it!` and Write completion feedback must dismiss once and advance; an old delayed callback must never cover or advance a newer word. | Automated pass | Critical XCUITest completes two consecutive words in each mode and confirms both transient cards disappear. |
| V03-BUG-007 | Bug | Parent interactions | Keyboard dismissal must not swallow Add All, sort, or delete taps. Every confirmed deletion keeps Undo, while only the first deletion in a Parent session asks for confirmation. | Automated pass | Critical XCUITest performs two deletes, Undo exposure, Photos-picker dismissal, OCR Add All, Pool refresh, and A–Z sort. |
| V03-BUG-008 | Bug | Write recognition | Short word `of` must pass when Vision returns the exact spelling in a lower-ranked candidate, splits the letters, varies case, or confuses handwritten `o` with `0`; unrelated neighbors must remain rejected. | Automated pass; child handwriting remains open | Verify `of`, `Of`, `OF`, `O` + `F`, and safe `0f` normalization through the real resolver; reject `if`, `on`, `or`, `ot`, and `off`, then repeat with the child on the target iPhone. |
| V03-IMP-001 | Improvement | OCR review | Select multiple library photos or take additional camera photos in one import. Number recognized words from 1, enforce a 500-word maximum per image, dedupe, and sort by source order, A-Z, or practice frequency. Keep top/back and bottom jump controls available during long reviews. | Automated pass | Import several photos, trigger the per-image 500-word error, edit numbered rows, change all sort orders, and use both scroll controls. |
| V03-IMP-002 | Improvement | Parent Words | Sort either Pool by added order, A-Z, or most practiced; show practice frequency; and support type-ahead search with Hear and Delete actions. | Automated pass | Search partial words, use both row actions, and compare all sort orders against known frequencies. |
| V03-IMP-003 | Improvement | Parent input | Tapping outside any Parent input dismisses its keyboard. The first word removal in a Parent session asks for confirmation; later removals in that session execute directly and retain Undo. | Automated pass | Exercise typing, search, OCR review, and gate fields; then delete one, several, and a later single word. |
| V03-IMP-004 | Improvement | Parent navigation | Parent Gate checks as soon as the expected number of digits is present. A wrong complete answer resets for retry. Tapping `Lock` in Parents locks the route and returns to Kid selection. | Automated pass | Enter correct and incorrect one- and two-digit answers, then enter Parents and tap Lock from the dashboard. |
| V03-IMP-005 | Improvement | Picture hints | Bundle the complete reviewed picture catalog with the app. On the first genuine Write mismatch, show a tappable picture icon for a catalogued concrete word without a network request. Function and abstract words such as `the`, `come`, and `kind` receive no image. Missing, corrupt, or oversized assets fail closed without blocking practice. | Automated pass | Verify all 74 manifest assets decode within the size limit, add `dog` and `the`, force one Write mismatch, and confirm a fresh offline install shows only the bundled dog hint while practice continues. |
| V03-IMP-006 | Improvement | Voice setup | Replace generic sample recording with six shuffled, short Pre-K sentences. The child hears and repeats each sentence; accepted/rejected progress stays visible, and raw audio is not persisted. | Automated pass | Finish enrollment with a target child, retry rejected speech/noise samples, restart, and confirm only the device-local template remains. |
| V03-IMP-007 | Improvement | Voice | Use one canonical teacher voice for every Profile; remove the six-style picker and discard its legacy preference on the next save. The client may call only a configured HTTPS teacher-audio endpoint and must never contain a provider API key. Without that endpoint it uses one deterministic clarity-ranked Apple fallback. | Automated pass; remote endpoint and listening remain open | Confirm no style UI or persisted style remains, no credential is present, and missing network/endpoint still produces one clear fallback voice. Configure and validate the restricted server endpoint separately. |
| V03-IMP-008 | Improvement | Learning audio | Prioritize clear, fluent Read `Hear it` and Write reference speech over an exact slowdown multiplier. The offline fallback selects the clearest installed natural American-English voice, avoids consonant-smearing ultra-low rates and artificial pitch, adds one silent terminal boundary, and keeps music ducked through a longer release. The remote contract remains one canonical teacher at its supported slowest speed. | Automated synthesis pass; physical-device listening remains open | A/B synthesize and transcribe `of`, `at`, `cat`, `come`, and `look`; then listen on the target iPhone with both compact-only and optional premium/enhanced voices. Verify one uninterrupted word, a distinct final consonant, and no mid-word gap. |
| V03-IMP-009 | Improvement | Read help | After two valid wrong readings, reveal only child-triggered `Hear it`; remove the Read picture button. Technical retries never unlock help. | Automated pass | Confirm hidden at 0/1 wrong, visible at 2 wrong, absent after technical retries, and reset for the next word. |
| V03-IMP-010 | Improvement | Results | Replay only words missed or helped in the completed run. A perfect run has no empty Replay action. | Automated pass | Complete both modes with one tricky word, tap Replay, verify only that word returns, and confirm no duplicate permanent reward. |
| V03-IMP-011 | Improvement | Scoring | Accuracy earns at 75% first-independent correctness or one eligible immediate unaided recovery. Personal Pace accepts calibration and 50% slow-side grace. Scores use up to 80 accuracy points plus 20 pace points; a perfect first try always earns 100 points and all three stars. Guardian evidence stays strict. | Automated pass | Compare perfect, 75%, recovered, helped, calibrating, too-fast, and slow-out-of-band runs with Guardian reports. |
| V03-IMP-012 | Improvement | Write controls | Never pre-show spelling when a word begins. `Clear` acts without confirmation; `?` alone reveals the word. Accept initial-cap, uppercase, and lowercase handwriting. Keep completion feedback visible for 830 ms, 400 ms longer than v0.2. | Automated pass | Test new/review words, all supported case forms, one-tap Help/Clear, timing, and guidance scoring. |
| V03-IMP-013 | Improvement | Write tools | Offer Pencil, Chalk, and Brush with black ink only; hide the color picker and remove Crayon from selectable tools. Persist the selected tool per Profile. Migrate legacy Crayon or colored settings to black Pencil. Use a 4× eraser; a blank-canvas tap after erasing restores the prior pen. | Automated pass | Switch all three tools, restart and change Profiles, load legacy tool/color data, erase partial strokes, tap blank canvas, and verify retained tool and recognition input. |
| V03-IMP-014 | Improvement | Write layout | Make the writing region 10% wider and keep its frame fixed when feedback appears. Keep the root Quest transition identity stable across word changes so animation never shifts the handwriting coordinate space. | Automated pass | Record error feedback and word-to-word transitions on phone/tablet; compare canvas bounds and root transition keys. |
| V03-IMP-015 | Improvement | Canonical pronunciation | Remove pronunciation-context editing from every Parent input and OCR path. Every new word uses isolated canonical teacher pronunciation; legacy contextual metadata remains decode-compatible only. | Automated pass | Add ordinary, homophone, and heteronym examples through typing and Add All; verify no editor appears and every new prompt has an isolated audio cue. |
| V03-IMP-016 | Improvement | Read presentation | Replace per-word color variation with one fixed, coordinated, high-contrast design token per World. Every Read word in the active World uses that token; color changes only when the child changes Worlds. | Automated pass | Verify all eight World tokens are visually distinct, meet WCAG contrast on the Read card, remain fixed across words/retries, and change only after a World switch. |
| V03-FEAT-001 | Feature | Cross-device sync | Sync Profiles, Read/Write pools, Profile settings, immutable attempts/corrections, event-derived progress, calendar completions, and rewards through parent-opted-in CloudKit while every Quest remains fully local-first. Voiceprints stay per-device; picture and canonical teacher-audio caches re-download. | v0.7.0 source implementation and deterministic simulator E2E complete; production CloudKit and physical/human acceptance remain open | Keep the exact-HEAD simulator artifact green, then validate one-Apple-ID private sync and two-Apple-ID `CKShare` sync on paid-Team Release builds. Delete a test-only Profile while another device is offline and prove the tombstone prevents resurrection while non-tombstone CloudKit data is erased. See `Docs/ADR-0001-CROSS-DEVICE-FAMILY-SYNC.md`. |

## v0.3 daily notes

### 2026-07-13

- Created `v0.3` from merge commit `7728f28` after PR #1 merged v0.2 to `main`.
- Rebuilt Parent word management around sticky Add All, numbered multi-photo OCR review, a strict 500-word-per-image limit, sort/search/frequency tools, session-scoped removal confirmation, and keyboard dismissal.
- Made Parent Gate auto-submit at the expected digit count, preserved wrong-answer feedback through the automatic clear, and made Parent `Lock` return directly to Kid selection.
- Replaced voice enrollment with shuffled repeat-after-me sentences. Practice now exposes one canonical teacher-voice contract; the former six-style picker and stored preference are removed, and a clarity-ranked Apple voice is the offline fallback.
- Reworked Read and Write fallback speech around clarity: a natural quality-first American-English voice, moderate `0.40` AVSpeech rate, neutral pitch, one terminal boundary, and an extended release. Rendered A/B samples for `of`, `at`, `cat`, `come`, and `look` all returned the intended word in the local transcription check; physical-device listening remains required.
- Reduced Read help to `Hear it` after two valid misses. Result Replay now contains only tricky words; perfect runs do not show an empty Replay action.
- Relaxed child rewards to a 75% Accuracy threshold, 50% slow-side pace grace, and guaranteed 100 points/three stars for a perfect first try, without changing strict Guardian evidence.
- Hardened handwriting capture for dots, later letters, and connected strokes; cached/throttled writing audio; changed the eraser to 4×; and restored the prior pen after a blank eraser tap.
- Set Write to never pre-show the answer, accept capitalization variants, show Help only after `?`, and offer a concrete-word picture after the first real miss. The toolbox now keeps only Pencil, Chalk, and Brush with black ink; the selected tool persists per Profile.
- Widened the Write canvas and stabilized both its local layout and the root Quest transition identity so feedback and word changes do not move its coordinates. Extended completion feedback from 430 ms to 830 ms.
- Replaced per-word Read color variation with one unique, high-contrast design token per World so words remain visually consistent until the World changes.
- Added pinned Twemoji 17.0.3 concrete-word hints, private on-device caching, abstract-word fail-closed behavior, and repository attribution in `THIRD_PARTY_NOTICES.md`.
- At the v0.3 checkpoint, audited the existing local-first/CloudKit foundation and recorded the cross-device Profile + Progress Sync contract in `Docs/ADR-0001-CROSS-DEVICE-FAMILY-SYNC.md`. The design kept parent opt-in, made voiceprints device-local and caches re-downloadable, and identified durable outbox, event-derived progress, business-key convergence, unconditional tombstones, CloudKit erasure, and paid-Team two-device acceptance as the next work. The source-side items were implemented in v0.7.0; production CloudKit and physical/human acceptance remain open.
- Completed the v0.3 branch-wide Swift suite: 548/548 passed with zero failures.
- Added five critical XCUITest flows; all 5/5 pass on the iPhone 17 Pro Max simulator, including OCR Review → Add All → Pool → Sort and consecutive Read/Write feedback dismissal.
- Built fresh v0.3 LocalQA apps for iPhone 17 Pro Max and iPad Pro 13-inch
  (M5) simulators with zero build failures.

### 2026-07-14

- Removed the Parent pronunciation-help section from typing, OCR, Pool display, import requests, copy, and documentation. Legacy contextual metadata remains decode-only and never appears or blocks an import.
- Fixed the P0 Read/Write completion overlays by binding feedback to the current prompt and invalidating delayed callbacks before the next word.
- Fixed gesture competition that swallowed Parent Add All, sort, and later delete actions; moved session Undo state into the long-lived dashboard model and made demo-store initialization single-flight.
- Fixed `of` handwriting recognition by providing `of`/`Of`/`OF` to Vision, evaluating its five best candidates and split fragments, and allowing only target-aligned `0` → `o` glyph normalization. Neighbor words remain exact mismatches.
- Reworked the offline teacher fallback for clear, fluent short words: quality-first American-English voice selection, one uninterrupted utterance, moderate rate, neutral pitch, terminal boundary, and longer release. Local synthesis/transcription recognized `of`, `at`, `cat`, `come`, and `look` 5/5; human speaker listening remains required.
- Regenerated the Xcode project, passed 548/548 Swift tests and 5/5 critical XCUITests, built fresh LocalQA apps for both target simulators, signed the physical-device build, and installed it on the connected iPhone 17 Pro Max.

## v0.3 device acceptance record

Installation evidence is recorded here; human child/parent acceptance remains separate.

| Date | Device | Build/version | Tester | Result | Notes/evidence |
|---|---|---|---|---|---|
| 2026-07-14 | iPhone 17 Pro Max | `v0.3.0` (`2026071401`) LocalQA | Codex install; Parent + child acceptance pending | Installed | Signed build installed successfully. Human `of`, pronunciation, speech, handwriting, rotation, and accessibility checks remain. |
| Pending | iPad Pro 13-inch (M5) | `v0.3.0` candidate | Parent + child | Pending | Full v0.3 checklist above. |

## v0.3.1 — 2026-07-14

Target release: `v0.3.1`

Branch: `v0.3.1`
Baseline: `main` at `cc42e17`, which merged v0.3 through PR #2.
Overall state: production fix, automated regression, signed iPhone and iPad installation, physical-device production Vision tests, physical-iPad critical UI pass, offline teacher-audio candidate, and simulator-verified World-art clearance. Child handwriting, audio listening, rotation, and accessibility acceptance remain open.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V031-BUG-001 | Bug | Write recognition | Real handwriting recognition must accept `of` and `go` independent of lowercase, initial-cap, or all-caps input. Tests must exercise the production renderer and Vision service rather than fabricated OCR candidates or the demo recognizer. Literal `90` and neighboring words must not pass as `go` or `of`. | Automated physical iPhone and iPad synthetic pass; child handwriting pending | Physical production-service tests have passed on iPhone and iPad. Next, have the child write `of`, `Of`, `OF`, `go`, `Go`, and `GO` twice each without Help; require 12/12 or capture a privacy-safe failure diagnostic. |
| V031-IMP-001 | Improvement | Learning audio | Read `Hear it` and Write reference speech use one canonical offline teacher contract. The 500-word Katie pack provides separate 0.90× Read and 0.82× Write clips; a documented `bun` voice/speed override fixes an objectively unclear rendering. Pack misses fail closed to Apple en-US TTS. Spoken prompts use a spoken-audio playback session, duck App music and external audio, then restore the normal mix without interrupting recording. | Automated decode, bundle, and transcription pass; physical listening pending | On the target iPhone and iPad, listen to `of`, `at`, `cat`, `come`, `look`, `bun`, and one pack-miss word. Confirm the intended voice, one clear utterance, audible final consonants, no clipped start/end, and smooth music duck/recovery. |
| V031-FEAT-001 | Feature | Profiles and preset words | Every new Profile path requires an explicit age from 3 through 8. Parent setup retains explicit grade control; Kid self-create derives the currently supported grade suggestion from age. Parents may browse an offline, versioned catalog ranked by age/grade, search or navigate its hierarchy, select individual/all words, and explicitly add to Read, Write, or Both. No recommendation auto-adds. Each import remains bound to the Profile that initiated it. A Both import compensates if either Pool fails, returns a partial result, or returns mismatched membership IDs. Compensation reverses only memberships inserted or reactivated by that request and preserves already-active words. | Automated pass; physical iPad explicit-approval flow pass; manual layout pending | Create Profiles through first-run, Kid self-create, and Parents; verify saved age and grade. Browse all roots, search a word, open one list without any Pool mutation, then explicitly add to each destination and confirm normalized de-duplication. Exercise failure, partial-result, mismatch, refresh-failure, concurrent activation, and cross-Profile cases for Both. |
| V031-FEAT-002 | Feature | Preset catalog content | Ship an independently curated 3–8 / Pre-K–Grade 3 catalog with 34 leaf presets, 1,365 word references, and 1,166 normalized unique words. Each leaf contains 40–45 valid single words across sight vocabulary, phonics/spelling, fine noun topics, verbs, emotions, and concepts. Keep one generated Obsidian Markdown catalog aligned with the App JSON and disclose methodology sources. | Automated content audit pass | Run the bundled-catalog auditor, verify every leaf remains within 30–50 words and every source ID resolves, then sample review age/grade fit, child safety, spelling, category relevance, and the generated Obsidian note. |
| V031-FEAT-003 | Feature | Parent word deletion | Read and Write each expose `Delete all N words`. The action always confirms the exact count/mode, deactivates the Pool without erasing learning history, leaves the other mode untouched, and offers full Undo. First-delete confirmation and Undo state remain isolated per Profile. A snapshot failure compensates the membership mutation before reporting failure. | Automated pass; physical iPad Delete All/restore and sequential-delete flows pass; manual layout pending | Clear each mode with mixed history, cancel once, confirm once, Undo once, then switch Profiles. Verify the other mode/Profile plus historical reports are unchanged and a failed post-mutation snapshot leaves no hidden Pool change. |
| V031-NIT-001 | UI polish | World scenes | Move castle, unicorn, vehicle, animal, and expansion-World story art farther into the lower side bands without moving foreground controls. Ambient art may drift only downward from its safe baseline. Moonpetal's unicorn must remain fully on-canvas and visibly separated from the Write card and shadow at every animation frame. | Implemented; focused geometry 5/5 and iPhone/iPad simulator visual pass | On iPhone 17 Pro Max and iPad landscape, wait through a full ambient cycle in Moonpetal and one expansion World. Require a visible background gap around every Quest card and no bottom/side clipping. |

### 2026-07-14 v0.3.1 notes

- Added the offline 3–8 / Pre-K–Grade 3 Preset Catalog, explicit age capture, and generated Obsidian catalog. Age and grade rank suggestions but never add words.
- Bound preset imports to the initiating Profile. Both imports now compensate exact inserted/reactivated memberships after failure, partial success, mismatched results, or refresh errors while preserving already-active words.
- Added per-Pool Delete All with exact confirmation and complete Undo. Confirmation and Undo state now stay isolated per Profile, and snapshot failures compensate the Pool mutation.
- Expanded regression coverage to 595 Swift tests. The 1,008 bundled audio files decode cleanly as mono 44.1 kHz AAC-LC, and fresh iPhone/iPad app bundles contain byte-identical resource trees with no credential-shaped token.
- Shifted World story art down into safe side bands. Moonpetal additionally shortens and right-shifts the unicorn enough to preserve a visible gap below the Write card throughout the ambient cycle. iPhone Moonpetal and full-screen iPad Dino simulator captures pass without clipping or foreground overlap.

### What the earlier tests missed

- The earlier case tests began after Vision by injecting strings such as `of`,
  `Of`, and `OF`. They proved case normalization only when OCR had already
  emitted the right letters.
- The critical Write XCUITest intentionally uses a deterministic demo
  recognizer. It proves feedback dismissal and navigation, not handwriting
  accuracy.
- Before v0.3.1, no asserted test sent nonempty strokes through the production
  renderer, Apple Vision, transcript resolver, and final decision together.

### Root cause and bounded fix

- Actual production-chain probes showed lowercase `of` produced no Vision
  observation at the default 26-point raster width. A 36-point fallback raster
  returned exact `of`.
- Lowercase `go` produced top candidate `90` plus lower candidate `g0`; a
  separately drawn literal `90` did not contain any corroborating `g` candidate.
- Production now runs at most two independent raster passes (26 and 36 points),
  enables target-word language correction, and supplies lower, Initial-cap, and
  ALL-CAPS vocabulary. Each pass must independently resolve the complete target.
- Matching remains exact after case normalization. `0` may normalize to `o` only
  inside a complete target match. `9` may normalize to `g` only when another
  same-length Vision candidate explicitly contains `g` in that position. There
  is no edit-distance or accept-any-ink fallback, and literal `90` stays rejected.

### Verification

- Strict Swift formatting and the full Swift suite pass: 595/595, zero failures.
- The focused macOS actual-Vision suite passes 15/15, including six `of`/`go`
  case variants and real rendered negatives `on`, `if`, `off`, `do`, `no`, and
  literal `90`.
- The connected iPhone 17 Pro Max on iOS 26.5.1 passes the new production-service
  device target: 2/2 XCTest cases, covering 6/6 positive variants and 4/4 negative
  controls. Fixtures are anonymous synthetic vectors; no child strokes are stored
  or committed.
- The seven critical UI flows pass 7/7 on the iPhone 17 Pro Max simulator. They
  remain lifecycle/navigation evidence and are not counted as Vision accuracy.
- Darren iPad Air 13-inch (M4) on iPadOS 26.5 passes the production physical
  DeviceTests 2/2: wrong-word rejection and `of/go` case variants.
- The same iPad passes the LocalQA critical XCUITest target 7/7: OCR Add All,
  Delete All/restore, explicit Preset approval, sequential deletes/sort, Photo
  picker/sort, and Read/Write completion dismissal.
- The final [iPhone Moonpetal](QAArtifacts/v0.3.1-2026-07-14/iPhone17ProMax-moonpetal-clearance.jpg)
  and [iPad Dino](QAArtifacts/v0.3.1-2026-07-14/iPadPro13-dino-clearance.jpg)
  captures keep all lower story art visibly clear of the foreground Quest cards
  after waiting through the ambient motion cycle.
- Fresh LocalQA simulator builds pass for iPhone 17 Pro Max and iPad Pro 13-inch
  (M5). Signed `Tada Words QA` v0.3.1 (`2026071402`) was installed and launched on
  the connected iPhone.
- Team `6S245NCUPQ` signed `Tada Words QA` v0.3.1 (`2026071403`) was installed and
  launched on the connected iPad. Child handwriting, audio, layout, rotation,
  Apple Pencil, and accessibility acceptance remain open.

## v0.3.1 device acceptance record

| Date | Device | Build/version | Tester | Result | Notes/evidence |
|---|---|---|---|---|---|
| 2026-07-14 | iPhone 17 Pro Max, iOS 26.5.1 | `v0.3.1` (`2026071402`) LocalQA | Codex automated device test; Parent + child acceptance pending | Installed; synthetic production Vision pass | 6/6 positive case variants and 4/4 negative controls passed through the production service. Child manual `of`/`go` 12-attempt gate remains. |
| 2026-07-14 | Darren iPad Air 13-inch (M4), iPadOS 26.5 | `v0.3.1` (`2026071403`) LocalQA, Team `6S245NCUPQ` | Codex automated device and UI tests; Parent + child acceptance pending | Installed and launched; DeviceTests 2/2; Critical XCUITest 7/7 | Production tests passed wrong-word rejection and `of/go` case variants. UI tests passed OCR Add All, Delete All/restore, explicit Preset approval, sequential deletes/sort, Photo picker/sort, and Read/Write completion dismissal. Child handwriting, audio, layout, rotation, Apple Pencil, and accessibility remain. |

## v0.4 — 2026-07-14

Target release: `v0.4`

Branch: `agent/v0.4-offline-audio`

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| AUDIO-FEAT-001 | Feature | Teacher word audio | Use a Katie-led 500-word offline pack with separate 0.90× Read hints and 0.82× Write prompts. The manifest may document a word-level voice or speed override when objective QA rejects the canonical rendering. Bundle misses must fail closed into Apple en-US TTS; no provider key or runtime dependency may ship. | Implemented; automated pass | On iPhone and iPad, compare `a`, `i`, `at`, `come`, `of`, `the`, `said`, `bun`, and two long animal words in both modes. Confirm correct pronunciation, complete final consonants, smooth ducking, and Apple fallback for one word outside the manifest. |
| AUDIO-FEAT-002 | Feature | Launch and transitions | Use Aurora for the approved continuous `Ta-dá↗ woooords↘!` cold-launch mark, six nonrepeating correct-answer micro-celebrations, and one Quest-complete line. Keep immediate World-specific synthesized feedback underneath; Reduced Sound suppresses decorative speech. | Implemented; automated structure pass; device listening pending | Cold launch twice, confirm rising `da`, no deliberate gap, lengthened falling `wor`, then complete one Read and one Write Quest. Toggle Voice/Sound Effects/Reduced Sound and confirm no overlap with recording, no repeated cold-launch mark, comfortable loudness, and no fatigue. |

### Audio implementation evidence

- Generated and manifest-checked 1,000 Katie word clips plus eight Aurora clips.
- All 1,008 files decode as mono 44.1 kHz AAC-LC; combined audio size is 6,807,998 bytes. The teacher pack duration is 674.80 seconds and Aurora duration is 8.74 seconds.
- A full 1,000-clip Apple Speech audit was reviewed with a second Whisper pass for true suspects. Homophone spelling differences were ignored; `near` and `chick` were corrected through IPA, and `bun` now uses a manifest-documented Aurora override after both recognizers rejected Katie. The final targeted clips pass both recognizers.
- The owner rejected the first direct-TTS launch render because `da` did not rise and the connection sounded too long, then rejected the staged replacement because the first syllable sounded like falling-tone “塔” instead of light “他” and a repeated source slice produced an extra stressed `a` after `da`. Aurora pack 1.0.2 keeps only the naturally level-to-rising onset for a short `/tə/` (approximately 332→334 Hz), stretches one unrepeated continuous `/dɑː/` window through approximately 380→394→459 Hz, and uses only an 8 ms click-safe join into `words`. Silence detection finds no internal pause. Exact character and naturalness remain owner device-listening QA.
- Swift 6 package suite passes 594/594 with bundled manifest, variant routing, fallback, and Aurora resource checks. Physical speaker fatigue, mix, and child reaction remain manual acceptance items.

## v0.4.1 — 2026-07-14

Target release: `v0.4.1`

Branch: `agent/v0.4.1-slower-teacher-audio`

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| AUDIO-FIX-003 | Improvement | Teacher word audio | Generate both Read and Write isolated words at `1/1.5 ≈ 0.67×`; preserve terminal consonants such as the `/t/` in `at`. | Implemented; automated acoustic and recognition pass | On iPhone and iPad, listen to `at`, `cat`, `sit`, `dog`, `help`, `look`, and `with` in both modes. Confirm the pace is comfortable for Pre-K and no final consonant is masked by speaker response or music recovery. |
| AUDIO-FIX-004 | Improvement | Spoken transitions | Remove `Ta-da!` as a correct-answer interjection and from the Quest-complete line. The `Tada Words` cold-launch brand name remains separate. | Implemented; automated manifest and recognition pass | Complete enough words to rotate through every correct-answer phrase, then finish one Quest. Confirm no transition says `Ta-da`; cold launch must still say the product name. |

### v0.4.1 implementation evidence

- Regenerated all 1,000 Katie/Aurora-override teacher clips from manifest version 1.1.0 at 0.67×. Each clip receives 120 ms of post-waveform padding before AAC encoding; playback already waits for the full `AVAudioPlayer` completion callback.
- All 1,000 teacher files decode as mono 44.1 kHz AAC-LC. Teacher duration is 863.12 seconds; all 1,008 audio resources total 7,428,104 bytes.
- The new `at` clips are 0.68–0.76 seconds versus 0.48–0.56 seconds before the change. Silence/energy inspection shows the stop closure, a following `/t/` release, and then the protected tail.
- Whisper independently transcribed both Read and Write samples for `at`, `it`, `cat`, `hat`, `sit`, `hit`, `get`, `cut`, `hot`, `not`, `dog`, `big`, `red`, `stop`, `help`, `look`, `fish`, `duck`, `back`, `off`, and `with` with their terminal consonants intact. Across 50 available curated clips, 43 were exact words; seven differed only in the vowel or initial consonant while retaining the expected terminal consonant. Three requested audit words were not members of the parent-approved 500-word manifest and were excluded rather than silently added.
- The correct-answer manifest now exposes five lines and no longer exposes `Ta-da!`. The regenerated Quest-complete clip contains only `Quest complete!`; Whisper transcribes it as `Quest complete.` The private `correct/ta-da.m4a` resource remains solely as the reproducible source component for the separate cold-launch brand mark and is not reachable by transition rotation.
- Integrated current `origin/main` (`02e23aa`) before release so the v0.3.1/v0.3.2 World-art, device-QA, Vision, UI-copy, and project-setting changes remain the baseline. Only the newer v0.4.1 audio resources and audio contract supersede their earlier counterparts.
- Strict Swift formatting and the full post-integration 595-test package suite pass. The earlier generic iOS Simulator build contains all 1,008 resources, and its bundled `at` hash matches the reviewed source asset; a fresh merged-tree iOS build is required before merge.

## v0.4.2 — 2026-07-14

Target release: `v0.4.2`

Branch: `agent/v0.4.2-transition-pause`

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| AUDIO-FIX-005 | Improvement | Inter-word audio timing | A new word must never attach directly to the end of correct-answer transition audio. Await the complete transition, keep the existing visible feedback minimum, then leave 700ms of silence before advancing to any non-final Read/Write item. Do not add the inter-item pause before Quest results. | Implemented; 600/600 pre-merge tests and simulator build passed | Complete consecutive Write items with Voice on, Voice off, Reduced Sound, and normal Sound Effects. Confirm every next prompt starts after a distinct pause and no transition is truncated; repeat Read to confirm its word card does not advance early. |

## v0.5 — 2026-07-14

Target release: `v0.5.0`

Branch: `v0.5`

Baseline: merged `v0.4.2`, including the recovered v0.3.2 device-QA fixes and
the v0.4.1 offline teacher-audio pack.
Overall state: integrated automated verification passed; physical iPad
child/parent acceptance remains open.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V05-UX-001 | UX redesign | Parent navigation | Replace the long Parent dashboard with one compact `Parent Home`: a single `Kids` Profile entrance, `Words & Practice`, `Progress & Performance`, `App & Family`, and `Lock`. Word management and child performance must never share a category. Remove duplicate Pool/Manage/Preset entrances and return every detail page to its owning category hub. | Automated pass; visual device QA pending | On iPhone and iPad in both Parent orientations, reach every existing Parent capability exactly once, verify Back returns to the owning hub, and confirm no card text wraps or clips at supported Dynamic Type sizes. |
| V05-FEAT-001 | Feature | Write spelling | Opening Write asks the child to choose `Write by Hand` or `Spell with Letters`. Either choice completes the same Daily Write Quest (rule B), uses the same Write Pool/mastery/review schedule, and earns only one completion/reward. Spelling uses a theme-colored, fixed-position QWERTY A–Z keyboard built entirely in SwiftUI; it never opens the iOS keyboard. Case is ignored, apostrophes/hyphens are structural, and typed pace is never compared with handwriting pace. Focused Replay preserves the chosen input method. | Automated pass; physical child QA pending | Complete both choices, verify exactly one Daily Write completion/reward, check all 26 letter keys plus Delete/Done in every World, assert no system keyboard, test case and punctuation, wrong-answer guided retry, Replay, relaunch recovery, VoiceOver order, and both landscape directions. |
| V05-IMP-001 | Improvement | Practice defaults | New Profiles default to 5 new and 5 review Write words instead of 3 and 3. Existing Profiles keep every saved custom value; there is no migration that overwrites parent choices. | Automated pass | Create a new Profile and see 5/5; reopen an existing Profile with custom Write limits and confirm the saved values are unchanged. |

### 2026-07-14 v0.5 notes

- Reorganized Parent tools into three category hubs while retaining every word,
  report, calendar, Profile, notification, audio, accessibility, and sync feature.
- Split the former all-in-one settings page into Practice Plan, Sound &
  Accessibility, and Notifications. Each save performs a scoped merge against
  the latest Profile settings so hidden values cannot be overwritten.
- Added a child-facing Write input chooser and a theme-matched A–Z keyboard.
  Handwriting and typed spelling share the Write learning contract, while
  attempt pace remains separated by input method.
- Raised only the defaults for newly created Profile settings to 5/5; persisted
  Profile settings remain authoritative.
- Registered and signed the newly connected iPad with Personal Team
  `6S245NCUPQ`; v0.3.2 (`2026071406`) was installed and launched successfully.
- Recovered the device-tested v0.3.2 QA fixes through PR #7, then merged them
  into v0.4.2 PR #6 before bringing the resulting `main` baseline into v0.5.
- The integrated v0.5 tree passes 619/619 Swift tests, strict format lint, a
  fresh generic iOS Simulator build, and all 8/8 critical simulator UI flows.
  Its Lobby → Write → Spell flow confirms all 26 custom keys, no native
  keyboard, first-word entry, and item advance.
- Exact v0.3.2 (`2026071406`) was reinstalled successfully on the connected
  reading iPad. Mac-side auto-launch was denied only because the iPad remained
  locked; the installed app is ready to open directly after unlock.

## v0.5.1 — 2026-07-15

Target release: `v0.5.1`

Branch: `v0.5.1`

Build: `2026071504`

Overall state: implementation is complete, and 638/638 Swift tests pass.
The full nine-flow simulator UI matrix passes on phone and tablet; physical
child/Parent acceptance remains open.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V051-UX-001 | UX improvement | Parent Home | Replace the visible `Lock` control with `Back`. Back returns to the prior child page and restores the Parent Gate for the next visit. Match the active kid World with the existing scene, panel, color, and tactile-button components. Remove the tagline and redundant labels; shorten the Progress title and count summaries. | Automated pass; device visual QA pending | Enter Parents from Kid selection, complete the gate, confirm `Back` replaces `Lock`, then return to the prior child page. Re-enter Parents and confirm the gate still appears. Inspect all eight World themes on phone and tablet in supported Parent orientations. |
| V051-UX-002 | UX improvement | Launch | Show a branded launch page for at least 1.8s, play the bundled `Tada Words` launch signature, then fade into the app. Use the official Tada Words and Pawgoo marks with responsive phone/tablet sizing and one combined accessibility label. | Automated pass; device visual/listening QA pending | Cold-launch on phone and tablet in supported orientations. Confirm both official marks, spoken brand signature, minimum duration, fade, VoiceOver label, and no interaction with hidden app content. |
| V051-BUG-001 | Bug | Write recognition | Improve exact `of` recovery without fuzzy acceptance. For `of` only, collect three render-and-recognize scales, inspect up to 10 Vision candidates, include mixed-case `oF`, cover six child-like stroke styles, and accept numeric `0` only at a target position containing `o`. Require two-scale corroboration for lower-ranked target evidence and veto a match when any scale exposes a strong complete `off`. Other targets retain the v0.5 two-pass/top-five behavior. | Automated pass; child handwriting pending | Have the child write separated and connected `of`, `Of`, `OF`, `oF`, `0f`, and `0F` twice on each target device. Reject `if`, `on`, `or`, `ot`, `off`, `00`, `90`, `0t`, `0ff`, `+0`, and `f0`; capture a privacy-safe diagnostic for any false rejection. |

### 2026-07-15 v0.5.1 notes

- Replaced Parent Home `Lock` with `Back`. The visible action returns to the
  prior child page while the route restores the Parent Gate for the next visit.
- Reused the active kid World's background scene, colors, panels, and tactile
  controls on Parent Home. Removed the tagline, redundant `Kids` label, and
  longer summaries; renamed `Progress & Performance` to `Progress`.
- Added a 1.8s minimum launch page with the official Tada Words and Pawgoo
  marks, the bundled spoken brand signature, a short fade, and one combined
  accessibility label. The production launch countdown starts only after audio
  preferences are configured, while a warm native launch color avoids a cold
  blue flash before the branded page.
- Added target-specific three-scale evidence for `of`, expanded only its Vision
  observations from five to 10 candidates, added mixed-case `oF`, and covered
  six child-like styles. Numeric `0` normalizes to `o` only at a target-aligned
  `o`, allowing `0f` and `0F` while rejecting `00`, `90`, `0t`, `0ff`, `+0`,
  and `f0`. A lower-ranked exact target must recur at two scales; any strong
  complete `off` evidence vetoes a match even when it appears after an early
  `of`. Thirty paired `ot/on/or/off/if` controls stay rejected. Other words
  retain their v0.5 two-pass/top-five behavior, with no fuzzy matching or
  global-threshold change.
- Set the release and LocalQA identity to v0.5.1 (`2026071504`). The tree passes
  638/638 Swift tests and strict format lint. The critical XCUITest matrix passes
  9/9 on iPhone 17 Pro Max and 9/9 on iPad Pro 13-inch simulators.
- Moved the corrected package to build `2026071504` after detecting that the
  parallel automation PR had reserved `2026071503`, preventing two release
  lines from sharing one LocalQA build identity.
- Verified the signed physical bundle directly as v0.5.1 (`2026071504`), LocalQA
  bundle ID `com.tadawords.app.localqa`, Team `6S245NCUPQ`; its provisioning
  profile includes the registered iPhone and both iPads. Installation and
  installed-version verification succeeded on the reading iPad. The iPhone
  became unavailable before the corrected package could install, and the iPad
  Air 13-inch (M4) paired Wi-Fi tunnel timed out. Reconnect those two devices,
  install `2026071504`, and inventory-verify before physical acceptance.

## v0.6.0 — 2026-07-15

Target release: `v0.6.0`

Branch: `agent/batch-kid-ui-v0.6.0`

Build: `2026071601`

Overall state: implementation, strict lint, and 641/641 Swift tests pass.
Exact-HEAD simulator, signed-device, and child-usability evidence remain required.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V060-UX-001 | UX improvement | Kid UI | Remove visible copy that repeats an obvious icon, target, state, or artwork across Profile, Lobby, Read, Write/Spell, Results, Worlds, Calendar, and Collection. Keep profile names, Read/Write identities, target words/slots, meaningful progress, destructive/recovery labels, and full VoiceOver meaning. | Implemented; simulator/device evidence pending | Use the copy matrix and before/after captures on iPhone 17 Pro Max and target iPad. Verify both Done controls are checkmark-first 72×72 pt actions with stable identifiers, VoiceOver label/hint, and unchanged behavior. Exercise VoiceOver, Dynamic Type, Reduce Motion, Reduced Sound, both landscape directions, error/loading/locked states, and the critical E2E matrix. |

### 2026-07-15 v0.6.0 notes

- Replaced repeated Profile, Lobby, quest, result, World, Calendar, and Collection
  explanations with existing SF Symbols, state borders, mascots, stars, rewards,
  and selection/lock badges.
- Kept the visible `Read` and `Write` identities, profile names, target words and
  letter slots, meaningful locked-world progress, destructive `Clear`, and all
  loading, permission, technical retry, and parent-recovery copy.
- Converted handwriting and Spell submission to checkmark-first controls using
  a shared 72 pt Kid action token. Both keep `Done` as the VoiceOver label,
  retain explicit hints, and expose stable `write.done` / `spell.done` hooks.
- Added a route-by-route copy disposition matrix and focused regression tests
  for idle Read copy suppression, stateful microphone feedback, submission
  accessibility contracts, stable identifiers, and the 72 pt touch target.
- Reserved version `0.6.0` and monotonic build `2026071601` across production,
  LocalQA, XcodeGen configuration, generated project settings, and release docs.

## v0.6.1 — 2026-07-17

Target release: `v0.6.1`

Branch: `agent/batch-parent-v0.6.1`

Build: `2026071701`

Overall state: Issue #15 implementation and automated simulator coverage pass;
physical link opening and human accessibility acceptance remain open.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| APPSTORE-015 | Improvement | Parent privacy/support | Expose Pawgoo's Privacy Policy and Support pages only after the Parent Gate, and explain how a parent deletes local Profile data or reviews iOS permissions without changing data behavior. | Automated pass; physical link QA pending | On iPhone and iPad, complete the Parent Gate, open App & Family, follow both links, return to the same Parent state, retry offline, and inspect VoiceOver plus large Dynamic Type. |

### 2026-07-17 v0.6.1 notes

- Added fixed HTTPS links for the Tada Words Privacy Policy and Pawgoo Support
  page inside the protected App & Family surface. Link labels, browser-opening
  hints, and stable accessibility identifiers are explicit.
- Added parent-facing instructions for deleting one child's local Profile data
  and for reviewing Camera, Photos, Microphone, Speech Recognition, and
  Notifications in iOS Settings. No account, tracking, analytics, purchase, or
  data-collection behavior changed.
- Set release and LocalQA identity to v0.6.1 (`2026071701`) across source Plists,
  `project.yml`, and the generated Xcode project.
- Strict format lint, all 643 Swift tests, and all 14 Issue Agent tests pass. The focused App & Family
  resource flow passes on iPhone 17 Pro Max and iPad Pro 13-inch simulators.
  Physical Safari opening, offline behavior, VoiceOver, and large Dynamic Type
  remain human release acceptance work.

## v0.6.7 — 2026-07-18

Target release: `v0.6.7`

Branch: `agent/batch-automation-v0.6.7`

Build: `2026071804`

Overall state: release-candidate preflight and Issue Agent scheduler changes
pass the complete automated suite; live LaunchAgent installation and exact-HEAD
runtime observation are recorded separately from PR merge acceptance.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| AUTO-020 | Feature | Release automation | Generate a deterministic release-candidate manifest only after source identity, signature, entitlement, resource, privacy, and clean-tree checks pass. | Automated pass | Run the preflight against a signed archive/export and retain its exact-HEAD manifest. |
| AUTO-038 | Policy | Versioning | While the first public App Store release is incomplete, reject any current, reserved, or proposed version above `v1.0.0`; ordinary Issue examples are not reservations. | Automated pass | Accept `v0.9.9`, `v0.10.0`, and the ceiling; reject `v1.0.1`, `v1.1.0`, and `v2.0.0`; require complete owner evidence before the post-release transition. |
| AUTO-047 | Reliability | Pickup ownership | Add `agent-reclaimed` before implementation and acquire a unique remote lease so overlapping workers cannot both implement one Issue. | Automated pass; live contention observation pending | Run overlapping polls and prove one lease winner, one safe skip, and no duplicate branch/PR. |
| AUTO-048 | Reliability | PR reconciliation | Link exact open-PR ownership and close a stale Issue only for an exact closing reference merged into current `origin/main` with no later reopen. | Automated pass; live reconciliation pending | Exercise open PR, merged PR, reopened Issue, fuzzy mention, owner branch marker, and changed PR HEAD. |
| AUTO-049 | Operations | Scheduler | Run every 900 seconds with `gpt-5.6-sol` and reasoning effort `ultra`, under one whole-worker macOS lock. | Automated pass; live LaunchAgent observation pending | Verify loaded plist interval/model/effort, overlapping ticks, empty queue no-op, and log/state retention. |
| AUTO-050 | Process | Issue-first delivery | Every implementation/change request searches and deduplicates Issues, creates bounded missing Issues, then immediately reclaims before editing. Answer, diagnosis, review, and status requests remain read-only. | Automated pass | Review repo instructions and start a fresh implementation session through the same reclaim path. |
| AUTO-051 | Reliability | Admission and blockers | Pickup order is P0→P1→P2→P3→unspecified, then dependencies/Issue number. A blocker produces a durable report, blocked state, claim removal, and verified lease release. | Automated pass; live blocked recovery pending | Prove P0 ordering, blocked release, companion-batch release, fresh reclaim requirement, active-PR serialization, and remote-branch duplicate prevention. |

### 2026-07-18 v0.6.7 notes

- Changed the LaunchAgent interval from 10 to 15 minutes and pinned unattended
  execution to Sol Ultra after a local model-catalog check and real probe.
- Replaced the PID-directory race with a whole-worker `lockf` lock. A two-runner
  test proves the second process exits before inspection while the first owns
  the lock through the simulated Codex phase.
- Added exact open/merged PR reconciliation, owner-authored remote branch
  ownership markers, fresh-main merge reachability, and reopen protection.
  Fuzzy text and title similarity never close an Issue.
- Added visible reclaim labels plus unique remote lease commits, live rechecks
  before mutation, guarded lease deletion, failed-reservation cleanup, and
  durable outcome verification before event acknowledgement.
- Added priority-first, explicit-batch-only admission. Similar `area` labels no
  longer combine unrelated Issues, and the default active implementation lane
  is one exact-HEAD batch.
- Added blocker reporting/release. The legacy blocked Audio Issue #13 was
  released from its claim and version/build reservation; its unchanged remote
  placeholder branch was removed while the blocker evidence remained.
- Added a repository-owned pre-App-Store version policy and stopped treating
  version examples in Issue prose as active reservations.
- The full exact-tree gate passes: strict Swift format, 646/646 Swift tests,
  37/37 Issue Agent tests, and 11/11 release-preflight tests.
## v0.7.0 — 2026-07-18

Target release: `v0.7.0`

Branch: `codex/batch-family-sync-v0.7.0`

Build: `2026071806`

Overall state: the cross-device Family Sync source contract, strict format
gate, 814/814 Swift tests, 14/14 Issue Agent tests, and the source-batch
simulator matrices pass. Production CloudKit schema, exact committed-HEAD
simulator reruns, signed iPhone/iPad private/share flows, destructive test-only
erasure, background delivery, and human accessibility/recovery review remain
release gates.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V070-FEAT-001 | Feature | Cross-device sync | Keep every Quest local-first while synchronizing parent-approved Profile facts, Read/Write pools, independent settings groups, immutable learning events, derived progress, daily completion/reward facts, and a bounded Profile photo through private/shared CloudKit. | Source and deterministic simulator E2E pass; production acceptance pending | Rerun the six-flow suite on the exact committed HEAD, then complete same-Apple-ID private sync and different-Apple-ID share acceptance on signed iPhone and iPad builds. |
| V070-PRIV-001 | Privacy | Terminal deletion | Persist a privacy-minimal deletion ledger before erasing owner Profile records/assets/share/zone; make participant leave and revocation terminal; block stale-device resurrection and purge Profile-scoped transport/photo bytes. | Source deletion/privacy harnesses pass | On test-only Profiles, delete while another device is offline, verify local purge after reconnect, and inspect the real container to prove that only the minimal ledger remains. |
| V070-RECOVERY-001 | Reliability | Durable sync | Survive process death around outbox, inbox, apply, acknowledgement, server-record conflict, quarantine, account change, and retry state without losing local work or duplicating completion/reward facts. | Source harnesses and simulator restart/status flows pass | Force-quit both signed devices at each retry boundary, reconnect in both orders, and verify Parent status before and after restart. |
| V070-ACCESS-001 | Feature | Family access | Use Apple's production sharing controller for existing-share management, route owners to private and participants to shared storage, fail closed for terminal/malformed bindings, and reconcile save/stop events through the normal notification path. | Source implementation and routing/presentation tests pass | As owner and participant, invite, accept, remove/leave, and revoke on signed devices; prove no revoked route creates a private fallback. |
| V070-BUG-001 | P0 bug | Upgrade migration | Preserve Daily Quest history written by v0.6.x, whose synthesized `QuestStars` Codable shape was `{ "earned": [...] }`, while v0.7.0 writes the canonical deterministic array form. Never delete or reset an unreadable snapshot. | Fixed with dual-format decoding and a schema-1 completion/reward migration regression; physical reinstall confirmation pending | Upgrade an unchanged v0.6.x LocalQA container in place, verify the app opens, and confirm plans, completions, rewards, calendar, and stars remain intact. |

### 2026-07-18 v0.7.0 notes

- Added one versioned private and one shared `CKSyncEngine` state with durable,
  exact-operation outbox/inbox persistence, account-generation isolation,
  checksummed bounded envelopes, exact acknowledgement, quarantine, and
  corrected-record recovery.
- Made conflict resolution deterministic: immutable attempts/corrections use
  stable identities, mutable Pool/settings records use logical revisions,
  same-revision different-byte conflicts fail closed, and progress/rewards are
  rebuilt from canonical facts.
- Added bounded 512 px / 256 KiB prepared Profile photos as validated `CKAsset`
  uploads with durable staging, acknowledgement cleanup, identity checks, and
  corrupt-asset quarantine. Voiceprints, raw/enrollment audio, notifications,
  handwriting residue, picture/audio caches, OCR, and sound caches stay local.
- Implemented ledger-before-purge terminal deletion, privacy-minimal retained
  fields, owner zone/share/asset erasure, participant leave, revocation,
  restart idempotence, stale-device upload barriers, and Profile-scoped purge
  of inbox/quarantine/system fields/locks/photo staging.
- Added the Parent-authorized production Apple access-management UI. Existing
  owner and participant routes use their persisted private/shared binding;
  revoked, deleted, and malformed routes fail closed. Save/stop-sharing
  delegate events reuse the idempotent notification reconciliation path.
- Added privacy-safe durable Parent status for pending count, retry state, last
  success, iCloud/account recovery, compatibility/corruption/conflict attention,
  and restart-consistent presentation. Diagnostics contain no child name,
  word, photo, recording, voiceprint, or repository payload.
- Account confirmation now reports a changed CloudKit account generation so
  re-enabling Family Sync after switching accounts invalidates the old
  acknowledgements and seeds the newly confirmed account. Reauthorizing the
  same account remains idempotent.
- Owner access management now always enters the transport's tested existing-
  share recovery path before presenting Apple's controller. Confirmed-missing
  shares can be rebuilt, transient failures are propagated, and participants
  can never create a private owner share.
- Added a machine-readable data manifest and five-layer evidence matrix. Only
  19 fields directly observed by the six simulator flows receive simulator
  evidence; unobserved simulator rows and every physical/human row remain
  pending.
- The source batch passes Family Sync 6/6 on iPhone 17 Pro Max and
  6/6 on iPad Pro 13-inch (M5), plus Critical Flow 10/10 on each simulator,
  all on iOS 26.5. Exact committed-HEAD reruns remain mandatory before merge.
- A physical in-place upgrade exposed a fail-closed legacy decoding gap before
  any saved data was reset. `QuestStars` now accepts both the v0.6.x keyed
  representation and the canonical v0.7.0 array, while all new writes remain
  deterministic. The regression fixture includes a real plan/completion/reward
  dependency chain, which the earlier empty-completion migration test missed.

## v0.7.2 — 2026-07-19

Target release: `v0.7.2`

Branch: `codex/p0-saved-data-recovery`

Build: `2026071902`

Overall state: P0 in-place data recovery. A physical iPhone showed the generic
“Saved data couldn’t open” screen after a v0.6.7 LocalQA package replaced a
Family Sync build. Two read-only exports produced identical checksum manifests;
the JSON was valid, but Word Pool, Learning Records, and Daily Quests were
already at forward schemas 2, 4, and 3 while v0.6.7 accepted only schema 1.

- Brought the forward Family Sync readers and their canonical data contracts
  onto the latest merged automation and offline picture-hint baseline. No
  snapshot was downgraded, reset, or manually edited.
- Added an application-level schema preflight before device identity creation,
  transaction replay, deletion recovery, or onboarding writes. A future schema
  now yields privacy-safe “Update Tada Words” guidance naming only the store and
  version boundary.
- Added retry and no-side-effect regression coverage for newer Word Pool,
  Learning Record, and Daily Quest schemas, plus current 2/4/3 bootstrap
  coverage and a bundled reader-policy drift test.
- Added a mandatory data-preserving LocalQA install wrapper. It performs a
  read-only device-container copy and blocks an older target reader before
  `devicectl install` can run.
- The copied real-device fixture loads with all 488 canonical attempts, 201
  word entries, two profiles, and quest history preserved. A deterministic
  derived-progress refresh changed only the rebuildable `progress` projection;
  canonical facts and every other snapshot remained unchanged.
- The exact committed-HEAD gate passes strict format, 821/821 Swift tests,
  40/40 Issue Agent tests, and 11/11 release-preflight tests. Exact committed-
  HEAD simulator and data-preserving physical-device gates are recorded on the
  P0 PR before merge.

## v0.7.3 — 2026-07-19

Target release: `v0.7.3`

Branch: `agent/batch-third-party-notices-v0.7.3`

Build: `2026071903`

Overall state: Parent-gated, offline third-party attribution plus a versioned
content-rights inventory and exact source/archive verifier for the bundled
picture-hint implementation. Cartesia entitlement evidence and Pawgoo ownership
attestation remain separate human blockers under #32 and #33.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V073-COMP-001 | Compliance | Parent resources | Keep the exact Twemoji attribution, pinned source, unmodified status, and CC BY 4.0 license accessible offline behind the Parent Gate. | Source, archive, and focused iPhone/iPad simulator UI tests pass | Keep the release inventory synchronized with the signed release archive and complete human VoiceOver review. |

### 2026-07-19 v0.7.3 notes

- Added a Third-Party Notices destination under Parent Home → App & Family.
- States that all 74 bundled picture-hint graphics are unmodified, identifies
  `jdecked/twemoji` 17.0.3, and exposes the exact copyright attribution plus
  source and Creative Commons Attribution 4.0 International links.
- Keeps every notice string available offline and every external link behind
  the Parent Gate; no child-facing route was added.
- Added exact-content, route/back-stack, and focused UI regression coverage.
- The focused flow launches at the largest accessibility text size, verifies
  every required notice paragraph and both resource controls, retains settled
  visual evidence, and returns to App & Family through the shared Back control.
- The focused Parent flow passes 1/1 on iPhone 17 Pro Max and 1/1 on iPad Pro
  13-inch (M5), iOS 26.5.
- The complete pre-commit gate passes strict format, 822/822 Swift tests,
  40/40 Issue Agent tests, and 11/11 release-preflight tests.
- Added `Docs/APP_STORE_CONTENT_RIGHTS.md` and a repeatable source/archive
  verifier. The unsigned v0.7.3 Release archive matches 1,008 M4A files, 74
  Twemoji PNGs, five expected JSON files, and all test/resource exclusions.

## v0.7.4 — 2026-07-19

Target release: `v0.7.4`

Branch: `codex/pr29-privacy-v074-refresh`

Build: `2026071904`

Overall state: the App Store privacy inventory is refreshed against the merged
v0.7.3 source. The App Store answer set remains a conditional draft pending
production CloudKit, Keychain removal, public-policy, operator-attestation, and
exact signed-build gates.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| APPSTORE-017 | Documentation | Privacy inventory | Keep one versioned, source-backed inventory for on-device processing, Apple services, Pawgoo-accessible support data, user-directed exports, and every configured/dormant non-Apple network path. Never publish an answer that depends on an unverified operating practice. | Refreshed source audit and focused regression pass | Re-run the inventory, dependency/domain scan, and iPhone/iPad traffic observation against the exact signed release candidate; obtain every listed owner attestation |
| APPSTORE-017-WEB | Blocker | Pawgoo privacy/support | Align the live pages with bundled offline hints, the qualified deletion guarantee, Keychain app-removal reality, and the complete classified Family Sync scope. | Mismatch documented; public site unchanged | Publish reviewed wording, record the deployed asset/commit, and compare both live pages with the exact shipping behavior |

### 2026-07-19 v0.7.4 notes

- Replaced the stale v0.6.3 audit, which still described jsDelivr hints,
  missing Parent links, an undecided Family Sync release, and authoritative
  transported progress.
- Recorded that all 74 Twemoji picture hints are bundled and that the shipping
  configuration has no teacher-audio endpoint, advertising, analytics,
  crash-reporting, tracking SDK, or external Swift dependency.
- Added the missing `UserDefaults` required-reason declaration (`CA92.1`) and
  a source-manifest contract test after independent App Store review found the
  production handwriting-tool preference was not covered by the prior
  two-category manifest.
- Classified the current Family Sync payload as synchronized canonical facts,
  locally rebuilt views, and device-only sensitive/recovery state. Added a
  regression test that prevents voiceprint fields from silently entering the
  synchronized class.
- Replaced the Profile sync payload with a dedicated wire DTO that omits
  `voiceprintStatus` entirely. Repository export/apply/identity validation and
  CKAsset photo staging now share that DTO; legacy payloads remain readable and
  retain their exact photo checksum, while remote sentinels cannot overwrite a
  device's Keychain-derived enrollment. A recursive contract now inspects the
  actual repository output for every record kind, nested object, array element,
  raw wrapper, and associated enum case. Pre-1.0 signed multi-device acceptance
  requires all devices on the same build; old-binary/new-photo mixed-version
  compatibility is not claimed.
- Classified every common sync-envelope field, including the random per-install
  logical-revision UUID, and replaced the record-kind inference with explicit
  allowlists plus an encoded-envelope contract test.
- Inventoried Parent CSV and privacy-safe sync-diagnostic share sheets, local
  OS diagnostics, APNs-triggered CloudKit reconciliation, bounded Profile photo
  `CKAsset`, terminal deletion ledger, and current Parent Privacy/Support/data
  controls.
- Re-fetched the live Pawgoo Privacy and Support pages and documented outdated
  hint-download, deletion, Keychain removal, and underspecified Family Sync
  language. No public-site or App Store Connect state changed.
- Recorded that the current app cannot delete its only remaining Profile and
  has no complete Delete All App Data path; #19 must close that privacy gap
  before the app or public policy claims complete in-app erasure.
- Opened #54 to own exact-RC alignment and deployment evidence for the live
  Pawgoo Privacy and Support pages; this batch did not mutate the public site.
- Kept **No data collected** conditional on production CloudKit acceptance,
  exact signed-build traffic/dependency evidence, absent remote audio endpoint,
  Pawgoo CloudKit non-access, support-mail practices, and corrected public copy.
- The complete pre-commit gate passes strict format, 834/834 Swift tests,
  40/40 Issue Agent tests, and 11/11 release-preflight tests.

## v0.7.5 — 2026-07-19

Target release: `v0.7.5`

Branch: `codex/pr36-appstore-v075-refresh`

Build: `2026071905`

Overall state: the internal App Store submission pack now consumes the merged
privacy and content-rights inventories and maps metadata claims to real source
and test paths. It remains blocked from App Store Connect until the exact signed
release, human decisions, production CloudKit, final-Profile/delete-all,
Keychain lifecycle, public-copy, content-rights, and Parents-gated permission
gates pass.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| APPSTORE-018 | Documentation | Submission metadata | Keep one versioned metadata, review-notes, screenshot, claim, and exact-RC preflight pack within Apple field limits and synchronized with the merged privacy/content-rights evidence. | v0.7.5 source candidate and automated contract coverage added | Recount final localized fields, validate exact signed iPhone/iPad screenshots and reviewer paths, then enter only the accepted values through the human-gated submission workflow |
| APPSTORE-018-RIGHTS | Blocker | Copyright/content rights | Treat `2026 Pawgoo LLC` as provisional and do not make the App Store content-rights representation until the voice entitlement and Pawgoo rights chain are documented. | Merged inventory identifies every shipped content class; #32 and #33 remain open | Preserve the account/tier evidence and obtain an authorized Pawgoo authorship/rights-chain attestation for every selected storefront |
| APPSTORE-018-DATA | Blocker | Privacy/public claims | Keep core practice/no-Pawgoo-account separate from parent-opted-in Family Sync, which needs an available iCloud account. Do not claim complete deletion while the final Profile cannot be deleted or a full reset performed. | Source boundaries and caveats are in the metadata pack; #19, #28, and #54 remain open | Pass production destructive sync and final-Profile/delete-all acceptance, choose/test the Keychain lifecycle, and deploy/verify matching Pawgoo Privacy and Support copy |
| APPSTORE-018-KIDS | Blocker | Permission requests | Do not direct an App Reviewer to grant Speech or Microphone authorization from the child-facing Read screen. Tada Words adopts a conservative parent-owned privacy policy for this setup; Apple does not explicitly require a parental gate before every OS permission prompt. | Current source can trigger both system prompts from Read; metadata and review steps are blocked by #55 | Move setup behind Parents, cover deny/retry/already-authorized states, and verify the exact signed flow on iPhone and iPad before replacing the reviewer placeholder |

### 2026-07-19 v0.7.5 notes

- Reserved version `0.7.5` and build `2026071905` across both source Plists,
  `project.yml`, and the generated Xcode project.
- Added `Docs/APP_STORE_SUBMISSION_PACK_v0.7.5.md` with exact English metadata,
  review notes, fictional screenshot fixtures, real source/test links, and an
  explicit exact-RC preflight. The file remains marked internal and is not an
  authorization to upload or submit.
- Removed misleading keyword claims for phonics and flashcards; the 93-byte
  keyword field now describes sight-word, reading, spelling, handwriting, word-
  list, and early-literacy practice.
- Recorded that current teacher audio is bundled or uses offline Apple speech;
  neither shipping plist configures a runtime teacher-audio endpoint.
- Replaced shared-device marketing language with Profile-specific learner
  wording. Core practice needs no Pawgoo account, while Family Sync separately
  requires parent opt-in and an available iCloud account.
- Kept Parent Profile controls qualified: the sole remaining Profile cannot be
  deleted and no complete Delete All App Data path exists. Issue #19 remains the
  behavior and destructive-proof gate.
- Integrated the merged privacy and content-rights inventories. Issue #54 owns
  the live Pawgoo copy; #32 and #33 own voice entitlement and Pawgoo ownership
  evidence; the displayed Pawgoo copyright remains provisional.
- Blocked current Read permission instructions under #55 because the
  child-facing action can trigger Speech and Microphone system authorization.
  The final reviewer path must begin behind the Parent Gate and pass exact-
  device verification before paste.
- This batch does not upload to App Store Connect, change the Pawgoo website,
  mutate CloudKit, or claim simulator/device/human acceptance.
- The complete pre-commit gate passes strict format, 837/837 Swift tests,
  40/40 Issue Agent tests, and 11/11 release-preflight tests. The focused
  metadata limits/local-link/stale-claim contract passes 3/3, and the source
  content inventory independently verifies the current version, build, audio,
  picture, JSON, font, attribution, and absent-endpoint boundaries.

## v0.7.6 — 2026-07-19

Target release: `v0.7.6`

Branch: `codex/profile-erasure-lifecycle-v0.7.6`

Build: `2026071906`

Overall state: source implementation and the pre-commit repository gate are
complete for the P0, privacy-safe Profile erasure lifecycle tracked by #57.
Production CloudKit, real-account erasure, exact committed-HEAD simulator and
signed cross-device acceptance remain separate gates under #19, #22, and #23.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V076-PRIV-001 | P0 privacy | Profile erasure | Persist and show truthful requested, deleting, waiting/retry, needs-attention, and complete states after a Profile is locally removed. Completion requires an exact tombstone acknowledgement after the owner or participant cleanup route finishes. | Source complete; live acceptance open | Pre-commit: 998/998 Swift, 40/40 Issue Agent, and 11/11 release-preflight tests. Still required: exact committed-HEAD simulator matrix, LocalQA iPhone/iPad regression, and Production CloudKit destructive proof. |

### 2026-07-19 v0.7.6 notes

- Reserved version `0.7.6` and build `2026071906` for the reclaimed #57 batch.
- Kept local deletion immediate and child flows nonblocking; the durable
  lifecycle is written with the tombstone before any Profile payload purge.
- Classified the lifecycle as device-local, privacy-minimal recovery evidence.
  It must never contain or export a nickname, word, photo, learning payload,
  Apple Account identifier, or share URL.
- A transport send is not completion. Only the exact acknowledged tombstone
  revision may complete the lifecycle after every required owner or participant
  cleanup step succeeds.
- Account changes fail closed: a cleanup belonging to the prior account cannot
  be acknowledged by running against a newly confirmed account.
- Profile deletion holds one shared mutation lease from durable tombstone write
  through every local purge and the commit marker. Sync reads wait for that
  lease, and an uncommitted tombstone cannot be exported after a local failure.
- CloudKit metadata rejects duplicate Profile routes, reused zones, missing
  roots, missing account provenance, and mismatched owner/participant routes
  without rewriting the original bytes. Item records must be parented to the
  exact persisted root, so a child of a rejected alternate root cannot apply.
- Owner-ledger recovery commits its minimal inbox receipt and terminal binding
  atomically after per-zone deletion proof and rechecks the exact Apple Account
  provenance inside the same metadata transaction.
- Remote owner root/zone deletion first persists the exact privacy-minimal
  control-zone tombstone, then erases the payload zone, purges local sources,
  and terminalizes. Every destructive or receipt-consumption boundary rechecks
  the live Apple Account and CKSyncEngine generation.
- Receipt-triggered child and Parent refreshes use monotonic generations and
  cancellation, so an older suspended refresh cannot republish a Profile or
  Kid after a newer deletion has won.
- Production fresh installs use a random default Profile identity and clear
  only Tada Words' device-local voiceprint Keychain service before creating any
  local marker. Existing installs preserve enrollment, and reset failures fail
  bootstrap closed for retry.
- Parent-visible lifecycle and exported diagnostics use anonymous aggregates;
  they never expose Profile, Apple Account, share, nickname, word, photo, or
  voice data.
- The pre-commit repository gate passes 998 Swift tests, 40 Issue Agent tests,
  and 11 release-preflight tests. Simulator and physical acceptance evidence
  will be recorded only after the exact committed HEAD passes.

## v0.7.7 — 2026-07-19

Target release: `v0.7.7`

Branch: `codex/apns-release-preflight-v0.7.7`

Build: `2026071907`

Overall state: issue #56 is implemented at the source/tooling layer. The
canonical release policy now accepts a Development- or Production-signed
archive only as intermediate evidence and requires the exact exported app or
IPA to carry Production APNs and CloudKit entitlements. No Apple resource,
certificate, provisioning profile, archive, export, CloudKit schema, or App
Store Connect record is created or changed by this batch.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V077-REL-001 | P0 release | APNs preflight | Bind push entitlement evidence to the exact signed archive and export without accepting LocalQA, source settings, screenshots, or an archive alone as Production proof. | Source/tooling complete; signed export open | Focused preflight: 16/16. Still required: full exact-HEAD repository and simulator gates, signed LocalQA identity/install/launch on iPhone and iPad, and an eventual PawGoo Production archive/export manifest. |

### 2026-07-19 v0.7.7 notes

- Reserved version `0.7.7` and build `2026071907` for reclaimed issue #56.
- Added the literal source contract
  `aps-environment = $(APS_ENVIRONMENT)` to the canonical policy.
- Added `aps-environment=production` as a required exported-app entitlement.
  Missing, Development, or any other exported value fails closed.
- Kept an archive-specific override for lowercase `development` or
  `production`; this never relaxes the exported app or IPA requirement.
- Added canonical-policy tests for the exact source expression, valid
  Production export, missing value, Development export, Development archive,
  LocalQA rejection, and unexpected extra entitlements.
- Documented that the manifest preserves archive and export paths, hashes, and
  entitlement dictionaries separately. Only the exact export is Production
  push evidence.
- The focused release-preflight suite passes 16/16. A real signed archive and
  exported app do not yet exist, so this batch makes no Production-readiness
  claim beyond the source/tooling gate.

## v0.7.8 — 2026-07-20

Target release: `v0.7.8`

Branch: `codex/issue55-parent-speech-permission-v0.7.8`

Build: `2026071908`

Overall state: source implementation separates the child check-only Speech and
Microphone boundary from the Parents-only permission request capability. Exact
signed first-install, denied, authorized, restricted, and revoked acceptance on
one iPhone and one iPad remains required before #55 or the App Store gate can
close.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| APPSTORE-019-KIDS | P1 privacy | Permission requests | Child launch, Profile switch, Read entry, replay, relaunch, and debug demo/deep-link routes must never trigger Speech Recognition or Microphone system prompts. Parents needs a clear setup route with separate status for both permissions. | Source implemented; exact-device gate open | Deterministic negative route, status, authorized-compatibility, and fail-closed tests; then exact signed first-install, denied, authorized, and revoked verification on one iPhone and one iPad |

### 2026-07-20 v0.7.8 notes

- Reserved existing version `0.7.8` and build `2026071908`; no competing branch
  or version was created.
- Removed all requesting capability from `TadaWordsFeatures`. Child Read can
  only check existing authorization and shows an age-appropriate Ask a Parent
  state without counting the permission failure as a learning attempt.
- Added Parents → App & Family → Speech & Microphone with independent Speech
  Recognition and Microphone status, explicit setup, already-authorized
  compatibility, and iOS Settings guidance for denied, restricted, or revoked
  access.
- Kept Voice setup as a second adult-owned permission entry point. The Apple
  controller requests only each still-undetermined permission and never
  re-requests a denied or restricted status.
- Added `Docs/SYSTEM_PERMISSION_INVENTORY_v0.7.8.md`, enumerating Speech,
  Microphone, Camera, Photos, Notifications, device-owner authentication, and
  non-prompting APNs/CloudKit service ownership.
- Source/unit/documentation gates do not claim simulator, signed-device, or
  human acceptance. Those remain serialized release evidence under #55/#22.
- The pre-commit repository gate passes 1,016 Swift tests, 40 Issue Agent tests,
  and 16 release-preflight tests after integrating the v0.7.7 Production APNs
  gate. Exact committed-HEAD verification is recorded separately after the
  implementation commit.
## v0.7.9 — 2026-07-19

Target release: `v0.7.9`

Branch: `codex/apns-registration-observability-v0.7.9`

Build: `2026071909`

Overall state: source implementation and the repository gate are complete for
the privacy-safe APNs registration observability tracked by #64. Exact signed
iPhone/iPad registration evidence and real background convergence remain
separate gates under #60 and #62.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V079-SYNC-001 | P0 observability | Family Sync push registration | Distinguish not-requested, pending, registered, and failed APNs registration without retaining or exporting the opaque device token. | Source complete; live acceptance open | 1042/1042 Swift, 40/40 Issue Agent, and 16/16 release-preflight tests pass on the combined source candidate. Still required: exact signed iPhone and iPad callbacks under #60; real background convergence under #62. |

### 2026-07-19 v0.7.9 notes

- Reserved version `0.7.9` and build `2026071909` for the reclaimed #64 batch.
- Added the UIKit success and failure delegate callbacks. The success callback
  has no local token identifier, and no device-token bytes enter the Domain,
  Parent UI, diagnostics, logs, persistence, hashing, or export paths.
- Kept only one process-local state value and one unread stream value per live
  observer. Relaunch begins at not-requested and retries return to pending.
- Mapped Apple failures into configuration, connectivity, or system categories
  without exporting the original domain, code, description, device identity,
  Apple Account detail, Profile content, or child data.
- Added Parent-visible registration state and schema-2 Family Sync diagnostics
  with the coarse state, optional category, and update timestamp.
- Late callbacks after opt-out cannot replace not-requested state. Registration
  failure never blocks local practice or claims a CloudKit convergence failure.
- Notification-presentation authorization is not used as evidence for silent
  CloudKit push registration.
- The combined Speech/Microphone and APNs integration focus passes 110/110.
  The complete combined source gate passes 1,042 Swift tests, 40 Issue Agent
  tests, and 16 release-preflight tests.

## v0.7.10 — 2026-07-19

Target release: `v0.7.10`

Branch: `codex/second-device-profile-adoption-v0.7.10`

Build: `2026071910`

Overall state: issue #66 source implementation and deterministic independent-
UUID coverage are complete. Exact signed iPhone plus clean iPad production-
CloudKit acceptance remains part of the later #62 convergence gate; this batch
does not install devices, mutate Apple portals, or merge itself.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V0710-SYNC-001 | P0 bug | Second-device onboarding | Let a parent discover and adopt an existing synchronized kid Profile before any random local Profile is committed. Preserve the exact UUID and synchronized fields; never merge by nickname, age, avatar, photo, or similarity. | Source complete; signed production acceptance open | Independent-UUID unit/integration and simulator UI coverage, full repository gate, then exact-HEAD one-iPhone plus clean-iPad CloudKit acceptance under #62 |

### 2026-07-19 v0.7.10 notes

- Reserved version `0.7.10` and build `2026071910` for the reclaimed #66 batch,
  leaving the independently reserved lower release slots untouched.
- Added an explicit transport bootstrap policy. Production CloudKit now leaves
  a genuinely fresh Profile repository empty until a parent chooses to find an
  existing kid or explicitly creates a separate new kid; device-only installs
  retain their local seed behavior.
- Added a Parent-owned first-run choice, privacy confirmation, retryable iCloud
  discovery, exact Profile selection for one or many children, and an explicit
  offline new-child route.
- Adoption persists only the exact selected Profile UUID as this device's last
  selection and completes onboarding without rewriting the Profile. Voiceprint
  enrollment remains device-local.
- Discovery intent is durable across a pre-adoption quit or restart, so an
  already downloaded remote Profile never becomes an editable local new-kid
  seed. Completing either exact adoption or explicit creation clears that
  intent; schema-v1 onboarding state remains readable under the v2 policy.
- Explicit creation durably reserves one exact pending Profile UUID before
  settings, Profile, child-session, or completion-marker writes. A retry after
  interruption reuses that UUID, so it cannot overwrite a discovered remote
  Profile or create a second local Profile. Focused tests interrupt and resume
  at every write boundary.
- A discovery retry or relaunch continues the already enabled Family Sync
  session with `synchronize()` instead of re-enabling it, preserving the
  production CKSyncEngine cursor and inbox state. The simulator fixture tracks
  acknowledgement with an independent durable cursor marker rather than
  inferring it from local Profile presence.
- Temporary iCloud unavailability during account confirmation is presented as
  an offline retry state; a missing or restricted iCloud account remains a
  distinct unavailable state. Neither path creates a Profile implicitly.
- Same-nickname Profiles remain separate. No nickname, age, avatar, photo, or
  fuzzy identity rule exists in the adoption path.
- New Profile creation persists isolated default practice settings before the
  Profile becomes visible and rolls those settings back if Profile persistence
  fails.
- Added deterministic tests for clean bootstrap/relaunch, one and multiple
  remote Profiles, same nicknames, delayed connectivity, no iCloud account,
  explicit offline creation, exact selection, and an independent simulator
  UUID that differs from the bundled simulator seed.
- The complete pre-commit gate passes strict format, 1012/1012 Swift tests,
  40/40 Issue Agent tests, and 11/11 release-preflight tests.
- The two focused independent-UUID second-device XCUITests pass 2/2 on both the
  iPhone 17 Pro and iPad Pro 11-inch (M5) simulators: exact adoption without
  a local seed, plus a quit/relaunch between discovery and adoption without a
  locally seeded duplicate.
- A generic iOS Simulator app build also succeeds. This is source and simulator
  evidence only; it is not a substitute for the exact signed Production build
  and one-iPhone plus clean-iPad CloudKit acceptance retained under #62.

### 2026-07-20 v0.7.10 reliability follow-up

- A CloudKit callback whose metadata, inbox, quarantine, or outgoing-system-
  fields write fails now leaves a generation-scoped recovery fence. The next
  fetch or direct send cancels the failed engines and reloads the last durable
  private/shared cursor in the same process, so retry no longer requires a
  force-quit. Late callbacks from the discarded generation remain ignored.
- Immutable conflict disposition now survives the 200-entry diagnostic cap.
  Direct quarantine, receipt quarantine, and atomic conflict conversion share
  one fail-closed upsert rule, so a later compatibility callback cannot unlock
  either a visible or compacted conflict after restart.
- Adoption and explicit creation read the final Profile list before committing
  the onboarding completion marker. A failed final read therefore keeps the
  flow retryable and reuses the exact reserved Profile UUID instead of leaving
  a completed marker with no usable result.
- A foreground iCloud-account revalidation now invalidates an in-flight Find
  at the final repository and presentation boundaries. A result fetched from
  account A is converted back to the durable reset state, Family Sync is opted
  out, and only a fresh parent retry may expose account B candidates.
- Added a deterministic account-switch race test that pauses Find after account
  A has populated canonical repositories, completes foreground revalidation to
  account B, and proves the stale result is rejected before a clean retry
  returns only account B's exact Profile UUID.
- Added red-to-green coverage for generic durability recovery, visible and
  compacted conflict-lock downgrade attempts, and final-read failures in both
  adoption and creation. The exact working-tree gate passes strict formatting,
  1037/1037 Swift tests, 40/40 Issue Agent tests, and 11/11 release-preflight
  tests. New exact-HEAD signed simulator evidence is still required after this
  follow-up commit.
- App Store follow-through remains explicit: #78 owns versioned migration of
  the new compact conflict semantics, #79 owns concurrent public transport
  recovery serialization, and #80 owns a bounded fail-closed conflict index.
  These are P1 release gates and do not expand the normal single-coordinator
  iPhone-plus-iPad P0 family-play path.

## v0.7.11 — 2026-07-20

Target release: `v0.7.11`

Branch: `codex/auto-merge-exact-head-v0.7.11`

Build: `2026072011`

Overall state: Issue #85 changes delivery policy and Issue Agent contracts; app
runtime logic and persistent schemas are unchanged. PR #72 is merged and this
batch is rebased directly onto the resulting `main`. Because the required
release increment changes app/LocalQA version/build metadata and the generated
Xcode project, exact-HEAD simulator and signed LocalQA iPhone/iPad gates still
apply. Apple Portal state, signing assets, CloudKit, and child data remain out
of scope.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V0711-DELIVERY-001 | P1 automation | Delivery | Replace the mandatory owner `/merge` comment with standing exact-HEAD authorization while retaining every evidence, blocker, high-risk, and post-merge gate. Keep `/merge` optional and provide a verified rollback to the prior comment policy. | Guarded-merge hardening in progress; packaged-artifact verification pending | Per-PR base OID plus canonical protection/closing-reference digests, strict server-enforced exact-head status, repository-wide merge lease, fsync-backed pending-intent recovery, no resend after an uncertain request, Issue Agent focused/full tests, repository check, exact-HEAD iPhone/iPad simulator build, and signed LocalQA iPhone/M4 iPad identity/install/launch evidence |

### 2026-07-20 v0.7.11 notes

- Reserved version `0.7.11` and build `2026072011` for the reclaimed Issue #85
  delivery-policy batch.
- A ready, non-draft, unblocked agent PR now produces a deterministic automatic
  merge candidate keyed by its full HEAD, per-PR base OID, PR-body SHA-256,
  paginated canonical closing-reference digest, and verified branch-protection
  digest without requiring a GitHub comment;
  stacked/non-`main` PRs are excluded.
- New commits produce a new candidate and invalidate previous checks, artifacts,
  device evidence, reviews, and readiness.
- A base change, PR-body edit, or canonical closing-reference change also
  invalidates the candidate at the same commit. The worker paginates GitHub's
  sidebar-aware GraphQL connection, rejects cross-repository closure, and keeps
  `Refs`-only PRs valid.
- The optional owner `/merge <sha>` command remains supported and is subject to
  the same current-HEAD preflight.
- Merge mutation is centralized in a guarded core command. It requires strict
  server-side up-to-date protection and the exact-head status, acquires a
  repository-wide remote lease for the single-writer metadata boundary,
  persists fsync-backed preparation and sent-or-unknown state, forbids
  admin/update/rebase bypasses, and sends the full HEAD as GitHub's merge
  compare-and-swap value. An uncertain request is reconciliation-only and is
  never resent.
- Durable acknowledgement after merge now requires the exact tested HEAD, a
  merge commit reachable from fresh `origin/main`, the intended base as its
  first parent, an identical merged tree, and closure of every canonical linked
  Issue through that PR. Pending intents survive process death without silent
  capacity truncation and are replayed even when the PR is no longer returned
  by the open-PR listing.
- Canonical closing-reference reads reject GraphQL partial errors, malformed
  nodes, and malformed pagination. Durable acknowledgement fsyncs an outstanding
  lease-cleanup record before releasing the exact unique remote lease; the next
  poll recovers unfinished cleanup before repository inspection after a crash.
- GitHub has no compare-and-swap for PR metadata. Automated writers must honor
  the merge-critical lease; owner edits during the short critical section are a
  documented trusted-operator boundary rather than an atomic GitHub guarantee.
- Destructive data work, irreversible provider/account mutations, credentials,
  authentication, ambiguous product choices, and mismatched target environments
  remain explicit human gates.
- Rollback reverts this policy batch and reinstalls the verified Issue Agent;
  logs, state, worktrees, branches, labels, and audit evidence stay preserved.
- App behavior is unchanged, but the version/build and generated package
  metadata alter the built artifact. Exact-HEAD simulator validation and signed
  LocalQA iPhone and iPad evidence is pending in the serialized device lane.

## v0.7.12 — 2026-07-20

Target release: `v0.7.12`

Branch: `codex/pawgoo-formal-identity-v0.7.12`

Build: `2026072012`

Overall state: Issue #68 moves only the normal Debug/Release identity to the
PawGoo LLC Team. The CloudKit container and every persisted Family Sync
identifier stay unchanged. LocalQA keeps its existing bundle, team flexibility,
empty entitlements, installed data, and physical-device workflow.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V0712-IDENTITY-001 | P0 release identity | Release/Persistence | Use `app.tadawords.app` and PawGoo `7R78Q4HP86` for the normal app without deriving or replacing LocalQA identities. | Implementation in progress on the reserved branch | Static identity contract, generated build-setting matrix, focused verifier tests, full repository gate, exact-HEAD iPhone/iPad simulator evidence, and exact PawGoo Development signed-artifact verification |

### 2026-07-20 v0.7.12 notes

- Reserved version `0.7.12` and build `2026072012` for reclaimed P0 Issue #68.
- Normal app Debug/Release uses bundle `app.tadawords.app`; its normal UI-test
  target uses `app.tadawords.app.uitests`. Both are pinned to PawGoo Team
  `7R78Q4HP86`.
- LocalQA remains `com.tadawords.app.localqa`; LocalQA UI tests remain
  `com.tadawords.app.uitests`; DeviceTests remain
  `com.tadawords.app.devicetests`. These configurations do not inherit the
  PawGoo team or APNs setting.
- The normal app retains APNs and the sole CloudKit container
  `iCloud.com.tadawords.app`, while the unused KVS source entitlement is
  removed. CloudKit zone/root/subscription identifiers and the device-local
  voiceprint service are unchanged.
- The new normal bundle creates a new local sandbox, permission state, and
  default Keychain group. This batch does not install it; #60 owns old-normal
  inventory and first normal-app installation. LocalQA data is untouched.
- The pre-commit source gate passes 1,119/1,119 Swift tests, 91/91 Issue Agent
  tests, and 54/54 release/identity-verifier tests. The Development verifier
  now binds Apple CMS trust and signer pinning, the PawGoo code-signing leaf,
  the profile authorization envelope, exact approved device coverage,
  iPhoneOS-only arm64 metadata, and a stable app-tree digest. Exact committed-
  HEAD simulator and signed-artifact evidence remains pending.

## v0.7.17 — 2026-07-21

Target release: `v0.7.17`

Branch: `codex/family-sync-status-refresh-v0.7.17`

Build: `2026072117`

Overall state: Issue #101 fixes a physical-device Family Sync status race.
CloudKit had converged on both approved devices, but the Parent UI retained a
transient `.syncing` snapshot when it opened during an existing reconciliation.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V0717-BUG-001 | P0 bug | Parent/Family Sync | Readers that arrive during an in-flight reconciliation must receive its final parent-visible status instead of a transient `.syncing` snapshot. | Source pass | Coordinator concurrency regressions, full source suite, exact-HEAD build, then one physical iPhone plus one physical iPad without reinstalling or resetting data |

### 2026-07-21 v0.7.17 notes

- Reserved version `0.7.17` and build `2026072117` for reclaimed Issue #101.
- The actor now queues concurrent status and synchronization callers while a
  reconciliation is active, then resumes all of them with the same settled
  status after every required immediate pass completes.
- No polling, profile mutation, preference change, uninstall, or data reset is
  involved in the repair.
- Physical evidence before the fix showed both devices at 278 acknowledged of
  278 local manifests, zero outbox and pending records, an idle durable
  condition, and no error while both screens still displayed “Syncing…”.
- Focused concurrency tests and the complete 1129-test Swift suite pass.
  Exact-HEAD build and signed-device acceptance remain pending.

## v0.7.18 — 2026-07-21

Target release: `v0.7.18`

Branch: `codex/family-sync-background-and-default-consent-v0.7.18`

Overall state: Family Sync now registers for remote notifications whenever a
parent turns it on after launch. First-run parents on iCloud-capable devices
see Family Sync enabled by default, can turn it off before profile creation,
and must explicitly keep it on before using iCloud profile discovery.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V0718-SYNC-001 | P0 bug | Parent/Family Sync | Enabling Family Sync in Parents must register APNs immediately rather than waiting for a relaunch; background devices may then receive a CloudKit change wake-up. | Source pass; signed-device pass blocked by locked login keychain | Exact signed iPhone and iPad: enable Family Sync, mutate a Profile on the other device while the receiver is backgrounded, then verify automatic convergence without opening Family Sync. |
| V0718-ONBOARDING-001 | P1 improvement | First-run parent agreement | Present Family Sync as the iCloud-capable default, with plain-language disclosure and an on-screen opt-out before any new Profile is queued. | Source pass; signed-device pass blocked by locked login keychain | Fresh-install parent path: verify default-on, explicit off, new Profile creation, and disabled Find-my-kid while opted out. |

### 2026-07-21 v0.7.18 notes

- Turning Family Sync on or off in Parents now respectively requests or
  unregisters remote-notification delivery in the same session.
- The first-run agreement defaults the iCloud-capable option to on; its
  completion writes the chosen preference before it creates a Profile, so an
  opt-out never queues that first mutation for Family Sync.
- “Find my kid” remains an iCloud-only action and is unavailable when the
  parent has explicitly opted out; creating a local Profile remains available.
- Focused first-run, notification-registration, Parent presentation, and the
  complete 233-test Family Sync regression suite pass. Signed v0.7.18 app
  artifacts are now installed in place on the approved iPhone and iPad;
  neither device data container was reset, replaced, or uninstalled.

## v0.7.13 — 2026-07-20

Target release: `v0.7.13`

Branch: `codex/quest-session-regressions-v0.7.13`

Build: `2026072013`

Overall state: Issues #91, #92, and #93 repair three daily-practice regressions
without deleting or replacing child learning history. Source regression tests
pass; exact-HEAD simulator and physical-device acceptance remain separate.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V0713-BUG-001 | P1 bug | Kid UI | Fit Spell chrome, prompt, slots, and the complete keyboard inside a constrained-height landscape iPhone while retaining 44-point controls and the regular iPad scale. | Automated pass | Layout-policy tests plus exact-HEAD landscape iPhone and iPad simulator captures; physical tap-through pending |
| V0713-BUG-002 | P1 bug | Write session | An explicit Spell selection after a completed Handwriting item must override stale recovered input-mode evidence while preserving the completed prefix. | Automated pass | Model regression covering Handwriting completion, exit, explicit Spell selection, and item-two recovery; simulator flow pending |
| V0713-BUG-003 | P1 bug | Parent/Persistence | Raising either New or Review cap must monotonically append eligible words to today’s canonical plan without changing its ID, completion, reward, or attempt history. Repeated refresh is idempotent and lower caps never delete history. | Automated pass | Local JSON completion/expansion/restart tests for both limits plus Parent-to-child simulator flow pending |

### 2026-07-20 v0.7.13 notes

- Reserved version `0.7.13` and build `2026072013` for reclaimed Issues #91,
  #92, and #93.
- Spell uses constrained-height metrics below 560 points: chrome, prompt,
  response slots, keyboard spacing, and submission controls compact together;
  every interactive control remains at least 44 points and regular-height iPad
  values are unchanged.
- The Write chooser now marks its selection as explicit. Persisted attempt
  context remains authoritative for generic crash/relaunch recovery, but cannot
  override a new child selection.
- Daily plan reconciliation is a serialized, monotonic repository mutation.
  It preserves the stable plan ID and appends only the delta allowed by a
  raised cap. Existing completion and reward references survive unchanged;
  lowering caps and repeated reconciliation are no-ops.
- Focused model, content-repository, and layout suites pass. Full source,
  automation, simulator, and signed-device gates are recorded separately.
