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
| V03-IMP-005 | Improvement | Picture hints | After a Pool import, asynchronously prefetch a privately cached hint for catalogued concrete words. On the first genuine Write mismatch, show a tappable picture icon. Function and abstract words such as `the`, `come`, and `kind` receive no image or network request. | Automated pass | Add `dog` and `the`, verify only the fixed dog asset is requested, force one Write mismatch, and test offline/cache fallback. |
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
| V03-FEAT-001 | Feature | Cross-device sync | Sync Profiles, Read/Write pools, Profile settings, immutable attempts/corrections, event-derived progress, calendar completions, and rewards through parent-opted-in CloudKit while every Quest remains fully local-first. Voiceprints stay per-device; picture and canonical teacher-audio caches re-download. | Design complete; implementation and live acceptance incomplete | Pass restartable outbox and order-independent convergence tests, then validate one-Apple-ID private sync and two-Apple-ID `CKShare` sync on paid-Team Release builds. Delete a Profile while another device is offline and prove the tombstone prevents resurrection while non-tombstone CloudKit data is erased. See `Docs/ADR-0001-CROSS-DEVICE-FAMILY-SYNC.md`. |

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
- Audited the existing local-first/CloudKit foundation and recorded the cross-device Profile + Progress Sync contract in `Docs/ADR-0001-CROSS-DEVICE-FAMILY-SYNC.md`. The design keeps parent opt-in, makes voiceprints device-local and caches re-downloadable, and identifies durable outbox, event-derived progress, business-key convergence, unconditional tombstones, CloudKit erasure, and paid-Team two-device acceptance as remaining work.
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

Build: `2026071501`

Overall state: implementation is complete, and 635/635 Swift tests pass.
The full nine-flow simulator UI matrix passes on phone and tablet; physical
child/Parent acceptance remains open.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V051-UX-001 | UX improvement | Parent Home | Replace the visible `Lock` control with `Back`. Back returns to the prior child page and restores the Parent Gate for the next visit. Match the active kid World with the existing scene, panel, color, and tactile-button components. Remove the tagline and redundant labels; shorten the Progress title and count summaries. | Automated pass; device visual QA pending | Enter Parents from Kid selection, complete the gate, confirm `Back` replaces `Lock`, then return to the prior child page. Re-enter Parents and confirm the gate still appears. Inspect all eight World themes on phone and tablet in supported Parent orientations. |
| V051-UX-002 | UX improvement | Launch | Show a branded launch page for at least 0.9s, play the bundled `Tada Words` launch signature, then fade into the app. Use the official Tada Words and Pawgoo marks with responsive phone/tablet sizing and one combined accessibility label. | Automated pass; device visual/listening QA pending | Cold-launch on phone and tablet in supported orientations. Confirm both official marks, spoken brand signature, minimum duration, fade, VoiceOver label, and no interaction with hidden app content. |
| V051-BUG-001 | Bug | Write recognition | Improve exact `of` recovery without fuzzy acceptance. For `of` only, collect three render-and-recognize scales, inspect up to 10 Vision candidates, include mixed-case `oF`, cover six child-like stroke styles, require two-scale corroboration for lower-ranked target evidence, and veto a match when any scale exposes a strong complete `off`. Other targets retain the v0.5 two-pass/top-five behavior. | Automated pass; child handwriting pending | Have the child write separated and connected `of`, `Of`, `OF`, and `oF` twice on each target device. Reject `if`, `on`, `or`, `ot`, `off`, and literal `90`; capture a privacy-safe diagnostic for any false rejection. |

### 2026-07-15 v0.5.1 notes

- Replaced Parent Home `Lock` with `Back`. The visible action returns to the
  prior child page while the route restores the Parent Gate for the next visit.
- Reused the active kid World's background scene, colors, panels, and tactile
  controls on Parent Home. Removed the tagline, redundant `Kids` label, and
  longer summaries; renamed `Progress & Performance` to `Progress`.
- Added a 0.9s minimum launch page with the official Tada Words and Pawgoo
  marks, the bundled spoken brand signature, a short fade, and one combined
  accessibility label. The production launch countdown starts only after audio
  preferences are configured, while a warm native launch color avoids a cold
  blue flash before the branded page.
- Added target-specific three-scale evidence for `of`, expanded only its Vision
  observations from five to 10 candidates, added mixed-case `oF`, and covered
  six child-like styles. A lower-ranked exact target must recur at two scales;
  any strong complete `off` evidence vetoes a match even when it appears after
  an early `of`. Thirty paired `ot/on/or/off/if` controls stay rejected. Other
  words retain their v0.5 two-pass/top-five behavior, with no fuzzy matching or
  global-threshold change.
- Set the release and LocalQA identity to v0.5.1 (`2026071501`). The tree passes
  635/635 Swift tests and strict format lint. The critical XCUITest matrix passes
  9/9 on iPhone 17 Pro Max and 9/9 on iPad Pro 13-inch simulators.
- Verified the signed physical bundle directly as v0.5.1 (`2026071501`), LocalQA
  bundle ID `com.tadawords.app.localqa`, Team `6S245NCUPQ`; its provisioning
  profile includes the registered iPhone and both iPads. Installation and
  installed-version verification succeeded on the iPhone 17 Pro Max and reading
  iPad. Both are locked, so automated launch and physical acceptance remain.
  The iPad Air 13-inch (M4) stayed paired but its Wi-Fi device tunnel timed out
  twice; wake/unlock or reconnect it before retrying the same verified package.
