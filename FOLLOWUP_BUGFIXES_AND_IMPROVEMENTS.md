<!-- TADA_BILINGUAL_DOC: English is the default reading language. The original source text is preserved for verification. -->
<a id="english-default"></a>

> **Languages / 语言：** **English (default) / 英文（默认）** · [简体中文](#简体中文版)

# Tada Words — Follow-up Bug Fixes & Improvements

This is the single source of truth for work discovered after the original V1
design. Product/design documents describe the current intended behavior; this
log records why it changed, which version contains it, and how it was verified.

## v0.7.43 — 2026-07-25

Target release: `v0.7.43`

Branch: `codex/qa-artifacts-cleanup-v0.7.29`

Build: `2026072417`

Overall state: Issue #114 removes obsolete tracked QA screenshot and result
directories while retaining the root-level audit records. Source, simulator, and
signed-device gates must be collected again for this exact package metadata.

- Removed every tracked child directory below `QAArtifacts/`.
- Retained the two root-level audit Markdown files.
- Replaced stale screenshot links with durable historical descriptions.
- Added a contract test that prevents future child directories under
  `QAArtifacts/`.

## v0.7.33 — App Store release alignment

- Standardized the product age range to 3–8 across profile creation, child
  creation, Parent profile editing, release metadata, and public-site inputs.
- Kept legacy snapshot decoding compatible while preventing new create/edit
  writes from setting ages outside the supported product range.
- Reconciled the release pack with the bundled offline Twemoji implementation,
  parent-opted-in Family Sync boundary, and Apple's single Kids Category band
  limitation.
- Reserved version `0.7.33`, build `2026072407`.

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
- Historical iPhone Moonpetal and iPad Dino captures confirmed that lower story
  art remained clear of foreground Quest cards after the ambient motion cycle.
  The temporary screenshot files were removed in the v0.7.43 repository cleanup.
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

## v0.7.32 — 2026-07-24

Target release: `v0.7.32`

Branch: `codex/privacy-support-alignment-v0.7.32`

Build: `2026072406`

Overall state: Issue #76's owner-approved conservative App Store 1.0 fallback
removes every production enrollment and speaker-matching entry point while
retaining only the existing Profile-deletion and proven-fresh-install cleanup
paths for a dormant pre-release Keychain template.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V0732-PRIVACY-001 | P0 release scope | Voiceprint/COPPA | Do not ship voiceprint enrollment or speaker matching in App Store 1.0 without a qualified written treatment; preserve deletion of any dormant pre-release template. | Automated pass; exact-artifact acceptance pending | Source contracts, complete regression gate, exact-HEAD iPhone and iPad simulator UI checks, signed in-place iPhone acceptance without deleting app data, and retained lifecycle cleanup tests |

### 2026-07-24 v0.7.32 notes

- Production composition no longer constructs an enrollment service or injects
  a speaker verifier into Read Practice.
- Parent Profile cards do not expose voice setup while the release policy is
  disabled, and view-model guards fail closed if legacy code attempts to
  navigate or begin enrollment.
- Microphone permission copy now covers spoken Read Practice only.
- Existing templates are not silently erased during update. The production
  repository remains composed only so Profile deletion and proven-fresh-install
  bootstrap can perform the previously verified scoped cleanup.
- This is a release-scope fallback, not a legal conclusion. Issue #76 remains
  open for qualified treatment of transient Read speech, Profile/photo data,
  persistent identifiers, and optional CloudKit Family Sync.

## v0.7.30 — 2026-07-23

Target release: `v0.7.30`

Branch: `codex/voiceprint-lifecycle-proof-v0.7.30`

### Voiceprint Keychain lifecycle proof

- Added signed physical-device tests that exercise the production
  `KeychainDeviceVoiceprintRepository` through Apple's Security framework.
- The tests use UUID-scoped test services, not the production voiceprint
  service, and require no uninstall or app-data reset.
- Coverage proves retained items survive repository recreation until the
  scoped fresh-install reset, which removes every item in that service while
  preserving a neighboring service.
- Coverage also verifies `WhenUnlockedThisDeviceOnly`, non-synchronizing
  attributes and idempotent empty-service reset.
- Added a durable lifecycle record and aligned the internal privacy and
  submission-pack wording. Deployment of matching Pawgoo Privacy/Support copy
  remains #54.

## v0.7.27 — 2026-07-21

Target release: `v0.7.27`

Branch: `codex/appstore-decisions-v0.7.27`

Overall state: the App Store 1.0 distribution contract is explicit and
consistent across the release-decision record, submission pack, privacy plan,
review notes, and exact-RC checklist.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V0722-RELEASE-001 | P1 decision | App Store | Use Made for Kids, Free/no IAP or ads, United States-only availability, and manual release everywhere. | Product and in-app Profile ages are 3–8; the owner selected Apple's `6–8` primary band because App Store Connect has no combined 3–8 value | Exact source tests, generated-project identity, PR merge, and later #65 App Store Connect entry against the accepted RC. |

### 2026-07-21 v0.7.27 notes

- The product and in-app Profile range is ages 3–8. The owner selected Apple's
  `6–8` primary band because App Store Connect has no combined 3–8 value; the
  post-approval lock-in remains irreversible.
- The first public release is Free, has no IAP/subscription/advertising/paid
  unlock, and is available only in the United States without pre-order.
- The approved release option is manual. App Review approval must leave the
  version in Pending Developer Release until #26 authorizes the final release.
- The account-level EU DSA trader declaration remains #23 scope even though no
  EU storefront is included in 1.0.
- This documentation and release-identity batch does not enter App Store
  Connect values, submit a build, or change runtime/data behavior.

## v0.7.19 — 2026-07-21

Target release: `v0.7.19`

Branch: `codex/profile-chooser-grid-v0.7.19`

Overall state: the compact iPhone Profile chooser uses a bounded vertical grid
instead of an unbounded horizontal strip. The first row contains at most three
existing Profiles plus `New Kid`; every later row contains at most three
Profiles and remains within the landscape safe area.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V0719-UI-001 | P1 bug | Kid/Profile chooser | Keep more than three Profiles inside the iPhone landscape bounds while retaining `New Kid` in the first row. | Automated pass | Layout-policy coverage for 0 through 20 Profiles, focused Swift tests, and exact iPhone landscape visual/tap verification with four Profiles. |

### 2026-07-21 v0.7.19 notes

- Compact cards use a bounded width that fits three Profiles plus `New Kid`
  inside the existing 760-point content envelope.
- The fourth existing Profile starts a vertically scrollable second row;
  subsequent rows never contain more than three Profiles.
- Every compact row shares the same leading edge, so partial overflow rows do
  not drift toward the center of the iPhone screen.
- Standard-height and iPad layouts keep their existing adaptive grid.

## v0.7.18 — 2026-07-21

Target release: `v0.7.18`

Branch: `codex/family-sync-background-and-default-consent-v0.7.18`

Overall state: Family Sync now registers for remote notifications whenever a
parent turns it on after launch. First-run parents on iCloud-capable devices
see Family Sync enabled by default, can turn it off before profile creation,
and must explicitly keep it on before using iCloud profile discovery.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V0718-SYNC-001 | P0 bug | Parent/Family Sync | Enabling Family Sync in Parents must register APNs immediately rather than waiting for a relaunch; background devices may then receive a CloudKit change wake-up. | Automated pass; signed iPhone-to-iPad propagation observed | On the normal `app.tadawords.app` build, iPhone creation of `Push Pebble 0721` converged to the untouched iPad without opening Family Sync; both device snapshots contained exactly one matching Profile and four Profiles total. |
| V0718-ONBOARDING-001 | P1 improvement | First-run parent agreement | Present Family Sync as the iCloud-capable default, with plain-language disclosure and an on-screen opt-out before any new Profile is queued. | Automated pass; clean-device physical acceptance pending | Fresh-install parent path: verify default-on, explicit off, new Profile creation, and disabled Find-my-kid while opted out. The existing family-data devices were intentionally not uninstalled or reset for this test. |

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
- In the normal PawGoo app, creating `Push Pebble 0721` on the iPhone produced
  one matching Profile on the untouched iPad without visiting Family Sync.
  Read-only device-container snapshots showed four Profiles on each device and
  exactly one record with that display name on each side.

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

## v0.7.21 — 2026-07-21

Target release: `v0.7.21`

Branch: `codex/atomic-profile-visibility-v0.7.21`

Build: `2026072121`

Overall state: an accepted remote Family Sync Profile batch is visible as one
committed generation across every canonical repository and compound UI reader.
An interrupted apply retains the exact accepted payload for replay and fails
closed without publishing a partial child, Parent, or notification snapshot.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V0721-SYNC-001 | P0 bug | Family Sync/apply | Prevent any accepted cross-repository Profile generation from appearing half new and half old; preserve exact replay and deletion finality. | Automated pass | Failure injection after every apply boundary, exact receipt/replay assertions, complete source gate, exact-HEAD simulator Family Sync matrix, and signed iPhone plus iPad smoke without deleting app data. |

### 2026-07-21 v0.7.21 notes

- One process-wide committed-generation gate now serializes accepted Profile
  applies with canonical repository reads and compound child, Parent, and
  notification snapshots.
- A partial accepted apply marks the affected Profile recovery-required. Public
  reads fail closed until the durable transaction replays its exact bytes;
  coordinator reconciliation performs replay before fingerprint or winner
  calculation.
- Apply receipts remain absent during interruption, appear once after the full
  commit, and do not change during a no-op recovery pass.
- Remote Profile deletion replays through tombstone, local-data erasure, and
  durable commit without allowing stale Profile data to reappear.
- The release keeps the existing PawGoo bundle identity, CloudKit container,
  and in-place data contracts. Simulator and signed-device evidence remains
  exact-HEAD and is recorded separately from source tests.

## v0.7.28 — 2026-07-24

Target release: `v0.7.28`

Branch: `codex/camera-ocr-editor-v0.7.15`

Build: `2026072402`

Overall state: Issue #96 adds an on-device crop-and-mask editor between camera
capture and OCR review while retaining v0.7.21 atomic Family Sync visibility
and all existing parent-approved word-pool rules.

| ID | Type | Area | Follow-up requirement | Current state | Required acceptance evidence |
|---|---|---|---|---|---|
| V0720-UX-001 | P1 improvement | Parent/Camera OCR | Let a parent crop a photographed word sheet and cover unrelated content before OCR, with undo, reset, retake, cancel, and an explicit Use Photo handoff. | Automated pass | Editor model/rendering tests, exact-HEAD iPhone and iPad simulator flows, signed LocalQA identity verification, and a data-preserving physical iPhone camera flow through OCR review |

### 2026-07-24 v0.7.28 notes

- The editor normalizes image orientation, preserves source resolution, and
  applies black masks only inside the selected crop before OCR.
- Camera and edited images remain device-local and are not persisted. Cancel
  leaves the word pool unchanged; OCR results still require parent review and
  explicit addition.
- Crop and Mask use white text when inactive against the editor's black
  background, while the active tool retains a white segment with black text.
- The physical iPad and Apple Pencil lane is waived for this merge only by the
  owner; iPad simulator coverage remains required. One physical iPhone camera
  flow is still a mandatory release gate.

<!-- TADA_BILINGUAL_ZH_START -->

---

<a id="简体中文版"></a>

> **翻译说明：** 英文为默认阅读语言；本文同时保留原始语言文本。如中英文内容存在差异，请以原始语言文本为准。

# Tada Words — 后续错误修复和改进

这是在原始 V1 设计之后发现的唯一唯一事实来源作品。产品/设计文档描述了当前的预期行为；该日志记录了更改的原因、包含该更改的版本以及验证方式。

## 版本控制工作流程

- `main` 包含最新接受的基线。
- 每个产品迭代都使用语义版本分支，例如`v0.2`、`v0.3`。
- 日常工作按当地日期分组如下 (`America/Los_Angeles`)。
- 仅修复后续版本使用补丁版本，例如`v0.2.1`。
- 仅在自动检查、全新LocalQA安装后才标记版本，
并且列出的物理设备检查通过。
- Replay，屏幕截图、模拟器结果和自动化测试可能支持
项目，但儿童语音/手写和可听韵律需要人工设备 QA。

## 状态词汇

- `Planned`：已接受，尚未实施。
- `In progress`：实施正在进行中。
- `Automated pass`：有针对性的自动检查通过；设备 QA 仍然存在。
- `Device QA pending`：包含在设备构建中并等待人工检查。
- `Accepted`：经过物理验证并包含在可接受的版本中。

## v0.2 — 2026-07-12

目标发布：`v0.2.0`

Branch: `v0.2`
总体状态：在合并提交 `7728f28` 时由 PR #1 合并到 `main`；物理设备的接受仍然开放。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V02-BUG-001 | Bug | 导航 | 正常点击`Parents` 必须打开数学Parent Gate。 | 自动通行证 | 点击iPhone 和iPad；门打开一次。 |
| V02-BUG-002 | Bug | 结果 | Replay 图标必须是再次启动相同模式的真实按钮。 |自动通行证|完成两种模式，点击Replay，验证`Practice Again`启动并不会授予重复的永久奖励。 |
| V02-BUG-003 | Bug | Read 识别 | 录音不得永远失败或在没有可用的儿童语音的情况下立即成功。权限、语音活动、端点和 Apple 回调竞争必须正常失败。 | 自动通过 | 静音、背景音频、短视单词、正常儿童声音以及在物理设备上重试两次。 |
| V02-IMP-001 | 改进 | Read | 新的Profile/新词在第一次独立响应之前不得听到目标。 | 自动传球 | 输入新的Profile Read 并确认保持安静，直到孩子行动。 |
| V02-IMP-002 | 改进 | 奖励 | 必须达到三颗星：允许立即独立恢复，校准可以赢得配速，慢速一方获得 25% 的宽限。 Guardian 准确性仍然严格。 | 自动通过 | 运行第一次尝试、一次恢复、校准、慢速、太快和帮助案例。 |
| V02-IMP-003 | 改进 | 启动 | 启动为 Profile-优先。没有Profile打开`New Kid`；返回的启动会突出显示最后一个有效的 Profile 以进行子确认。首次运行设置中不会出现任何单词条目。 | 自动通过| 全新安装、一个Profile、多个配置文件、最后删除Profile 和重新启动检查。 |
| V02-IMP-004 | 改进 | 父词 | 用 Read/Write 选项卡、单字返回添加、最新第一实时队列、本地相机/照片 OCR 预览、同池重复数据删除、单个/批量删除、确认和撤消替换旧的快速添加。 | 自动传递 | 键入/返回、来自两个来源的多字 OCR、重复导入、批量排序、单个删除、批量删除/撤消 iPhone 和 iPad。 |
| V02-IMP-005 | 改进 | 单词来源 | V1 不得添加等级/目录/智能填充单词。每个池条目均来自家长输入或OCR;尺寸过小的泳池仍然尺寸过小。 |自动通行证|空的和尺寸过小的池在启动和任务准备过程中保持不变。 |
| V02-IMP-006 | 改进 | Write 音频 | Write 参考发音较慢，并保持最终辅音可听，包括 `at` 中的 `t`。 | 自动传递 | 在目标手机/平板电脑上收听 `at`、`cat`、`look`、`go` 和 `I`。 |
| V02-IMP-007 | 改进 | Read 帮助 | 仅在两次有效的错误读数后，才显示 `Hear it` 和 `See it`。 `Hear it`是儿童触发的标准发音； `See it` 在已知单词旁边显示了本地图片。未知的单词一定不能收到猜测的图片。 |自动通行证|确认0/1错时隐藏，2错时可见，技术重试未解锁，`dog`显示狗，未知单词失败关闭。 |
| V02-IMP-008 | 改进 | 语音 | 更喜欢可用的年轻美式英语女性系统语音，具有确定性的自然语音后备。 | 自动传递 | 在目标设备上监听；确认没有丢失/下载的语音导致静音。 |
| V02-IMP-009 | 改进 | 声波标志 | Launch 是一个自然的短语，`Ta-dá↗ woooords↘!`（所有者近似：`它达，沃尔子`）：`da` 略微上升，直接通向明显加长、下降的 `wor`，没有故意的逗号停顿或机器人的话语接缝。 |已实施；设备监听待处理 | 通过语音开/关和三个世界主题，根据所有者参考进行冷启动监听检查。 |
| V02-IMP-010 | 改进 | 公主主题 | Moonpetal 添加了原始的彩虹/独角兽细节和更乐观、多样化的类似游戏的乐谱，而不涵盖学习控制或泄漏到其他主题。 | 自动通过 | 两个横向方向的目视检查，Reduce Motion，音乐闪避和录音淡出。 |
| V02-IMP-011 | 改进 | 外观 | 在当地某一天完成 Read 和 Write 今日任务可在第二天解锁一个不劳而获的主题和图标。 Replay 和部分天数不计算在内；延迟启动可以幂等地赶上。 |自动通行证|当日锁定、次日解锁、部分日、重播、重复完成、跨月、重启、每Profile隔离。 |
| V02-IMP-012 | 改进 | 我的收藏 | Kid 获得一个单独的屏幕来查看和选择获得的主题和图标。锁定的项目仅供预览；保留原始照片头像数据。 | 自动通过 | 选择、重启、切换 Profile、选择照片/图标/主题，并验证持久性/隔离。 |
| V02-IMP-013 | 改进 | Read 匹配 | 稍微放宽普通话-L1 接近形式的发音等效性，例如将目标 `come` 识别为 `kum/cum`，而不接受不同的单词，例如 `some`、`home`、`came`、`cat/cap`，或绕过音频/说话人置信门。 | 自动通过 | 精心策划的正面/负面政策测试以及针对 `come` 和其他代表性词语的目标儿童设备试验。 |
| V02-IMP-014 | 改进 | 大厅 | 从右上角标题中删除非交互式当前主题文本药丸，因为它看起来可以点击。主题标识保留在场景和“我的收藏”选择中。 | 自动通过 | 验证标头在 iPhone/iPad 景观上保持平衡，并且不包含死角控制。 |
| V02-IMP-015 | 改进 | 世界 | 将原来的三个世界扩展到八个，包含五个独立的原创主题：恐龙探索、消防站英雄、砖砌城市、霜光世界和过山车嘉年华。每个都需要自己的调色板、边缘安全场景、吉祥物、奖励和音乐特性。 | 自动通行证 | 在手机/平板电脑上预览全部八个，横向、Quest 调光、Reduce Motion、音乐闪避和次日解锁顺序。 |
| V02-IMP-016 | 改进 | 宝藏 | 每个世界都有 25 个相关的、视觉上不同的宝藏图标。上锁的宝藏保留了带有锁徽章的灰色艺术品，而不是成为通用锁。 | 自动通行证 | 检查 200 个目录条目、每个世界的唯一性、符号可用性、锁定/赢得/当前状态以及紧凑网格。 |
| V02-IMP-017 | 改进 | Profile 头像 | 可以选择收集的宝藏作为子头像；上锁的宝藏不能。在宝藏、获得的动物图标和原始照片之间切换会保留源照片和同步元数据。 |自动传递|选择/重启/切换Profile/同步，拒绝锁定的宝藏，并确认所有面向儿童的头像表面匹配。 |
| V02-IMP-018 | 改进 | 吉祥物 | 将共享的两点线占位符面孔替换为友好的、世界特定的、姿势感知的表情，用于休息、欢呼、鼓励和救援状态。 |自动通行证|检查所有八个吉祥物和四个姿势，Reduce Motion开/关；情感在紧凑的尺寸中保持友好和清晰。 |
| V02-IMP-019 | 改进 | Write 控制 | `Clear` 立即删除所有写入内容，无需确认。单个`?`图标立即显示单词并记录指导；没有保留任何帮助文本或三项选择表。 |自动通过|测试非空/空清除，VoiceOver反馈，一键显示，重复显示，计时器行为和指导评分。 |
| V02-IMP-020 | 改进 | Write 工具 | 添加铅笔、蜡笔、粉笔和画笔工具以及 12 种独立可选的基本颜色，具有持久的独特笔画风格和柔和的每笔画移动声音。将 Undo 替换为本地橡皮擦，其路径为活动笔宽度的 2.5 倍；保留一键清除。 |自动传递|用手指和铅笔绘制/切换工具/颜色/擦除部分笔划；验证旧笔画保留样式/颜色、识别输入、声音节流、降低声音策略、紧凑布局和无提示音频掩蔽。 |
| V02-IMP-021 | 改进 | Read 呈现 | Read 单词每次尝试都使用从活动世界调色板中选择的稳定、高对比度颜色，单词之间有足够的变化，并且没有重绘闪烁。 | 自动传递| 验证所有八个世界调色板、确定性重画/旋转、WCAG 对比度以及任务中的可见变化。 |
| V02-IMP-022 | 改进 | 家长导航 | 将面向儿童的条目重命名为 `Parents`。家长设置/管理路线支持iPhone/iPad上的纵向和横向；所有子路线仅保持景观，并在出口处立即恢复景观。 | 自动通过 | 策略测试和 iPad 模拟器窗口形状通过。在物理设备上旋转每条父路线，通过Parent Gate返回，并确认Profile/大厅/任务/徽章在两个横向方向上保持横向； iPhone 原始模拟器帧缓冲区捕获不是验收证据。 |
| V02-IMP-023 | 改进 | 儿童视觉风格 | 完善面向儿童的排版、缩微、形状和装饰节奏，让学前儿童感觉更可爱、更有吸引力，同时保留大触摸目标、阅读对比度和独特的世界身份。 | 自动通行证 | 新手机/平板电脑 Profile、大厅、Read 和结果捕获通行证。完成Dynamic Type、VoiceOver，以及在物理设备上的简短目标儿童导航/吸引力观察。 |
| V02-IMP-024 | 改进 | 大厅 | 将前 `Collection — See your world treasures` 条移至右上方标题中，作为紧凑的 `Badge` 按钮，打开相同的赢得化妆品屏幕。 |自动传递|iPhone横向捕获显示四项标题适合并且底部条消失了；物理点击手机/平板电脑上的徽章以确认导航。 |

## 每日笔记

### 2026-07-12

- 根据已接受的 `main` 基线 `ca76fcf` 创建`v0.2`。
- 物理iPhone首次通过反馈定义`V02-BUG-001`通过
`V02-IMP-005`。
- 添加了语音、提示、语音、主题/音频和次日外观要求。
- 将声音徽标从三个排队的语音片段重新设计为一个 SSML
与所有者参考文献 `tā-'dá, wòrds!` 相匹配的短语。
- 为 Read 添加了保守的普通话-L1 发音等效调整。
- 从大厅标题中删除了误导性的非交互式主题标签。
- 将世界目录从三个扩展到八个，而不改变第一个
三个解锁位置，并添加了独特的程序场景/音乐。
- 每个世界添加了 25 个稳定的宝藏图标、锁定图标预览并收集
珍藏头像选择，同时保留源照片。
- 将占位吉祥物面孔替换为姿势感知表情。
- 简化了Write清除和帮助，然后添加了四工具书写/橡皮擦设计。
- 添加了 12 种独立的笔颜色和主题感知的 Read 单词颜色变化。
- 重命名了父条目，将纵向支持范围限定为父路由，并保留
每个孩子的路线仅限横向。
- 将收藏从大厅主体移至紧凑的右上方`Badge`入口。
- 开启了专注学前班视觉风格的细化通行证；新鲜的屏幕截图和
在接受之前仍需要对目标儿童进行观察。
- 完成了全分支机构的 Swift 套件：479/479 通过，零失败
在添加重点第一阶段演示测试之前。
- 成功为 iPhone 17 Pro Max 和 iPad Pro 13 英寸构建了 LocalQA 应用程序
(M5) 模拟器。新签名的物理设备安装仍然开放。

### 2026-07-13

- 在定向政策覆盖后，将`V02-IMP-022`提升为自动通行证
iPad模拟器父/子窗口形状证据。 iPhone 原始帧缓冲区方向仍然不确定，因此仍然需要实际设备旋转。
- 在 iPhone 景观捕捉后将 `V02-IMP-024` 提升为自动通行证
显示了四项标题配件，没有以前的底部收集条。仍然需要物理徽章直通。
- 第一阶段视觉效果获得批准后，晋升为`V02-IMP-023` 至自动通过
细化：静态强调记住的Profile； iPhone 大厅在 72 点触摸框架内使用 48 点图标底座，而 iPad 保留标签；大厅/Read/结果吉祥物、iPadRead卡片和单词以及结果奖励/重播重点通过集中式儿童规模代币变得更大。
- 审查了 iPhone 17 Pro Max 上的最新 Profile、大厅、Read 和结果捕获
和 iPad Pro 13 英寸 (M5)。没有观察到剪切、重叠或世界身份泄漏；身体Dynamic Type、VoiceOver和目标儿童吸引力仍然存在。
- 完成后细化分支范围套件：480/480 通过零
失败，并且两个LocalQA模拟器构建都通过了。
- 将启动语音目标更新为连续的`Ta-dá↗ woooords↘!`
短语：`da`上升并直接连接成更长的、下降的`wor`，匹配`它达，沃尔子`；设备监听批准仍然开放。

## 设备验收记录

在最终`v0.2.0`候选人就任后填写。

| 日期 | 设备 | 版本/版本 | 测试仪 | 结果 | 注释/证据 |
|---|---|---|---|---|---|
| 待定 | iPhone 17 Pro Max | `v0.2.0` 候选人 | 家长+子女 | 待定 | 以上完整清单。 |
| 待定 | iPad Pro 13 英寸 (M5) | `v0.2.0` 候选者 | 家长+儿童 | 待定 | 以上完整清单。 |

## v0.3 — 2026-07-13

目标发布：`v0.3.0`

Branch: `v0.3`
Baseline: `main` 和 `7728f28`，合并了 v0.2 至 PR #1。
总体状态：在合并提交 `cc42e17` 时由 PR #2 合并到 `main`；人类物理设备的接受度仍然开放。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V03-BUG-001 | Bug | OCR 导入 | `Add all N to Read/Write` 在识别后必须保持可点击状态，并且在保存时必须显示进度或可操作的错误。 | 自动传递| 识别照片，关闭键盘，点击一次粘性“添加全部”操作，并验证池更改一次。 |
| V03-BUG-002 | Bug | 语音设置 | 语音设置必须记录可用的注册示例，而不是显示一般错误或禁用“完成”。在读取输入格式之前配置音频会话，并在样本被拒绝时保留接受的进度。 | 自动通过 | 在物理设备上完成设置，包括一个拒绝的样本、中断、重试和最终保存。 |
| V03-BUG-003 | Bug | Write 画布 | 短点、后面的字母和连接的笔画必须保留在绘图中。写入声音必须使用缓存、节流播放，不得出现卡顿。 |自动传递|Write`i`，一个三个字母的单词，并与每个工具连接`vv`/`w`；聆听间隙、削波或重复的启动噪音。 |
| V03-BUG-004 | Bug | Parent Gate | 错误的完整答案必须自动清除，且不会使其错误反馈闪烁并消失。保持消息可见，直到家长开始下一个答案。 | 自动通过 | 输入错误答案，观察清除的字段和持久消息，然后键入下一个数字并确认消息消失。 |
| V03-BUG-005 | Bug | 任务转换 | 前进到下一个单词不得重建根任务 shell 或更改其转换标识。 | 自动传递 | 逐帧记录多字 Write Quest 并确认画布坐标空间在每次前进期间保持固定。 |
| V03-BUG-006 | Bug | 任务反馈 | Read `You got it!` 和 Write 完成反馈必须驳回一次并提前；旧的延迟回调绝不能覆盖或推进较新的单词。 | 自动通过 | 关键 XCUITest 在每种模式下完成两个连续的单词，并确认两张瞬态卡消失。 |
| V03-BUG-007 | Bug | 家长互动 | 键盘关闭不得吞并添加全部、排序或删除点击。每个确认的删除都会保留“撤消”，而只有父会话中的第一个删除才会要求确认。 | 自动传递 | 关键 XCUITest 执行两次删除、撤消曝光、照片选择器关闭、OCR 添加全部、池刷新和 A-Z 排序。 |
| V03-BUG-008 | Bug | Write 识别 | 短词 `of` 必须在 Vision 返回排名较低的候选者中的准确拼写、拆分字母、改变大小写或混淆手写的 `o` 与 `0` 时通过；不相关的邻居必须继续被拒绝。 | 自动通行证；儿童笔迹保持开放|通过真实解析器验证`of`、`Of`、`OF`、`O`+`F`和安全`0f`规范化；拒绝`if`、`on`、`or`、`ot`和`off`，然后让孩子重复目标iPhone。 |
| V03-IMP-001 | 改进 | OCR 审核 | 选择多张图库照片或在一次导入中拍摄额外的相机照片。从 1 开始对识别的单词进行编号，强制每个图像最多包含 500 个单词，进行重复数据删除，并按源顺序、A-Z 或练习频率进行排序。在长时间查看期间保持顶部/后退和底部跳跃控件可用。 | 自动传递| 导入多张照片、触发每张图像 500 字错误、编辑编号行、更改所有排序顺序以及使用两个滚动控件。 |
| V03-IMP-002 | 改进 | 父词 | 按添加顺序、A-Z 或最常用的顺序对池进行排序；显示练习频率；并支持通过“收听”和“删除”操作进行预输入搜索。 | 自动传递 | 搜索部分单词，使用两个行操作，并将所有排序顺序与已知频率进行比较。 |
| V03-IMP-003 | 改进 | 父级输入 | 在任何父级输入外部点击都会关闭其键盘。家长会议中删除第一个单词需要确认；该会话中的后续删除直接执行并保留撤消。 | 自动通过 | 练习输入、搜索、OCR 复习和门字段；然后删除一个、几个、以及稍后的一个单词。 |
| V03-IMP-004 | 改进 | 家长导航 | Parent Gate 一旦出现预期的数字位数，就会进行检查。错误的完整答案将重置以重试。点击Parents中的`Lock`可锁定路线并返回Kid选择。 | 自动通过 | 输入正确和错误的一位数和两位数答案，然后输入 Parents 并点击仪表板上的“锁定”。 |
| V03-IMP-005 | 改进 | 图片提示 | 将完整审阅的图片目录与应用程序捆绑在一起。在第一个真正的 Write 不匹配时，无需网络请求即可显示已编目具体单词的可点击图片图标。功能词和抽象词如`the`、`come`和`kind`没有图像。丢失、损坏或规模过大的资产无法关闭，但不会阻碍实践。 |自动传递|验证所有74个清单资产在大小限制内解码，添加`dog`和`the`，强制一个Write不匹配，并确认新的离线安装在练习继续时仅显示捆绑的狗提示。 |
| V03-IMP-006 | 改进 | 语音设置 | 用六个打乱顺序的短 Pre-K 句子替换通用样本录音。孩子听到并重复每个句子；接受/拒绝的进度保持可见，并且原始音频不会保留。 | 自动通过 | 完成目标儿童的注册，重试拒绝的语音/噪声样本，重新启动，并确认仅保留设备本地模板。 |
| V03-IMP-007 | 改进 | 语音 | 每 Profile 使用一种规范的教师语音；删除六种样式选择器并在下次保存时放弃其旧版首选项。客户端只能调用已配置的 HTTPS 教师音频端点，并且绝不能包含提供者 API 密钥。如果没有该端点，它会使用一种确定性清晰度排名的 Apple 后备方案。 | 自动通行证；远程端点和监听保持打开状态 | 确认没有样式 UI 或持久样式保留，不存在凭证，并且丢失的网络/端点仍然会产生一个清晰的后备语音。单独配置和验证受限服务器端点。 |
| V03-IMP-008 | 改进 | 学习音频 | 优先考虑清晰、流畅的 Read `Hear it` 和 Write 参考语音，而不是精确的减速乘数。离线后备选择最清晰的已安装自然美式英语语音，避免辅音涂抹超低速率和人为音调，添加一个无声终端边界，并在较长的发布过程中保持音乐的隐藏。远程合同仍然是其支持的最慢速度的规范教师之一。 | 自动合成过程；物理设备聆听保持开放| A/B 合成和转录`of`、`at`、`cat`、`come` 和 `look`；然后使用纯压缩语音和可选的高级/增强语音收听目标iPhone。验证一个不间断的单词、一个独特的结尾辅音以及单词中间没有间隙。 |
| V03-IMP-009 | 改进 | Read 帮助 | 两次有效的错误读数后，仅显示儿童触发的`Hear it`；删除Read图片按钮。技术重试永远无法解锁帮助。 |自动通过|确认0/1错时隐藏，2错时可见，技术重试后消失，并重置下一个单词。 |
| V03-IMP-010 | 改进 | 结果 | Replay 仅在完整运行中遗漏或有帮助的单词。完美的跑步没有空的Replay动作。 | 自动通行证 | 用一个棘手的单词完成两种模式，点击Replay，仅验证该单词返回，并确认没有重复的永久奖励。 |
| V03-IMP-011 | 改进 | 评分 | 首次独立正确性达到 75% 或符合资格的立即无辅助恢复时获得准确度。个人配速接受校准和 50% 慢侧宽限。分数最多使用 80 个准确度点加上 20 个速度点；完美的第一次尝试总是可以获得 100 分和全部三颗星。 Guardian 证据仍然严格。 | 自动通过 | 将完美、75%、恢复、帮助、校准、过快和慢速带外运行与 Guardian 报告进行比较。 |
| V03-IMP-012 | 改进 | Write 控制 | 单词开始时切勿预先显示拼写。 `Clear` 未经确认而采取行动； `?` 单独揭示了这个词。接受首字母大写、大写和小写手写。保持完成反馈可见 830 毫秒，比 v0.2 长 400 毫秒。 | 自动通过| 测试新词/复习单词、所有支持的案例表格、一键帮助/清除、计时和指导评分。 |
| V03-IMP-013 | 改进 | Write 工具 | 仅提供带有黑色墨水的铅笔、粉笔和画笔；隐藏颜色选择器并从可选工具中删除 Crayon。按照 Profile 保留所选工具。将旧的蜡笔或彩色设置迁移到黑色铅笔。使用4×橡皮擦；擦除后点击空白画布即可恢复之前的笔。 |自动传递|切换所有三个工具，重新启动和更改配置文件，加载旧工具/颜色数据，擦除部分笔划，点击空白画布，并验证保留的工具和识别输入。 |
| V03-IMP-014 | 改进 | Write 布局 | 将书写区域加宽 10%，并在出现反馈时保持其框架固定。保持根 Quest 过渡标识在单词更改时保持稳定，这样动画就不会移动手写坐标空间。 | 自动传递| 在手机/平板电脑上记录错误反馈和单词到单词的转换；比较画布边界和根转换键。 |
| V03-IMP-015 | 改进 | 规范发音 | 从每个家长输入和 OCR 路径中删除发音上下文编辑。每个新单词都使用独立的规范老师发音；遗留上下文元数据仅保持解码兼容。 |自动传递|通过打字和全部添加添加普通、同音、异义词示例；验证没有编辑器出现，并且每个新提示都有一个独立的音频提示。 |
| V03-IMP-016 | 改进 | Read 演示 | 用每个世界一个固定、协调、高对比度的设计标记替换每个单词的颜色变化。活跃世界中的每个 Read 单词都使用该标记；仅当子级改变世界时颜色才会改变。 |自动通过|验证所有八个世界标记在视觉上是不同的，满足Read卡上的WCAG对比度，在单词/重试中保持固定，并且仅在世界切换后改变。 |
| V03-FEAT-001 | 功能 | 跨设备同步 | 同步配置文件、Read/Write 池、Profile 设置、不可变的尝试/更正、事件衍生进度、日历完成以及通过家长选择的奖励 CloudKit，同时每个任务仍然完全本地优先。声纹保留在每台设备上；图片和规范的教师音频缓存重新下载。 | v0.7.0 源代码实现和确定性模拟器 E2E 完成；生产CloudKit和物理/人类接受保持开放|保持精确HEAD模拟器工件绿色，然后在付费团队发布版本上验证一个Apple-ID私人同步和两个Apple-ID`CKShare`同步。当另一台设备离线时删除仅测试的Profile，并证明墓碑可以防止复活，同时非墓碑CloudKit数据被删除。参见`Docs/ADR-0001-CROSS-DEVICE-FAMILY-SYNC.md`。 |

## v0.3 日常笔记

### 2026-07-13

- 在 PR #1 将 v0.2 合并到 `main` 后，从合并提交 `7728f28` 创建了`v0.3`。
- 围绕粘性“添加全部”、编号多照片OCR审查、严格的每张图像 500 个单词限制、排序/搜索/频率工具、会话范围的删除确认和键盘解除重建了家长单词管理。
- 使Parent Gate按预期位数自动提交，通过自动清除保留错误答案反馈，并使父`Lock`直接返回Kid选择。
- 用随机重复的句子取代了语音注册。现在的实践揭露了一种规范的教师语音合同；以前的六种风格选择器和存储的偏好被删除，清晰度排名的苹果语音是离线后备。
- 围绕清晰度重新设计了Read和Write后备语音：自然质量第一的美式英语语音、适度的`0.40`AVS语音速率、中性音调、一个终端边界和延长的释放。 `of`、`at`、`cat`、`come` 和 `look` 的渲染 A/B 样本均在本地转录检查中返回了预期单词；仍然需要物理设备监听。
- 两次有效失误后，将Read帮助减少至`Hear it`。结果Replay现在只包含棘手的单词；完美的运行不会显示空的Replay动作。
- 将儿童奖励放宽至 75% 的准确度阈值、50% 的慢速宽限，并保证首次尝试完美获得 100 分/三颗星，而无需更改严格的 Guardian 证据。
- 强化手写捕捉点、后续字母和连接笔画；缓存/节流写入音频；将橡皮擦改为4×；并在空白橡皮擦敲击后恢复了之前的笔。
- 将Write设置为从不预先显示答案，接受大写变体，仅在`?`之后显示帮助，并在第一次真正错过之后提供具体的单词图片。工具箱现在只保留铅笔、粉笔和黑色墨水画笔；所选工具按照Profile 保留。
- 加宽了 Write 画布并稳定了其本地布局和根 Quest 过渡标识，因此反馈和单词更改不会移动其坐标。将完成反馈从 430 毫秒延长至 830 毫秒。
- 将每个单词的Read颜色变化替换为每个世界一个独特的、高对比度的设计标记，因此单词在视觉上保持一致，直到世界发生变化。
- 在第 `THIRD_PARTY_NOTICES.md` 中添加了固定的 Twemoji 17.0.3 具体单词提示、私有设备上缓存、抽象单词失败关闭行为和存储库归属。
- 在 v0.3 检查点，审核了现有的本地优先/CloudKit 基础，并在`Docs/ADR-0001-CROSS-DEVICE-FAMILY-SYNC.md` 中记录了跨设备Profile + Progress Sync 合约。该设计让家长选择加入，使声纹设备本地化和缓存可重新下载，并确定持久发件箱、事件派生进度、业务密钥融合、无条件墓碑、CloudKit 擦除和付费团队两设备接受作为下一步工作。源码端项目在v0.7.0中实现；生产CloudKit和物理/人类接受仍然开放。
- 完成了 v0.3 分支范围的 Swift 套件：548/548 通过，零失败。
- 添加了五个关键的 XCUITest 流程；所有 5/5 在 iPhone 17 Pro Max 模拟器上通过，包括 OCR 审核 → 添加全部 → 池 → 排序和连续的 Read/Write 反馈驳回。
- 为 iPhone 17 Pro Max 和 iPad Pro 13 英寸构建了全新的 v0.3 LocalQA 应用程序
(M5) 零构建失败的模拟器。

### 2026-07-14

- 从输入、OCR、池显示、导入请求、复制和文档中删除了家长发音帮助部分。旧的上下文元数据仍然只能解码，并且永远不会出现或阻止导入。
- 通过将反馈绑定到当前提示并使下一个单词之前的延迟回调无效，修复了 P0 Read/Write 完成覆盖。
- 修复了吞噬父添加、排序和稍后删除操作的手势竞争；将会话撤消状态移至长期存在的仪表板模型中，并使演示存储初始化一次性完成。
- 通过向 Vision 提供 `of`/`Of`/`OF`，评估其五个最佳候选者和分割片段，并仅允许目标对齐的 `0` → `o` 字形标准化，修复了`of`手写识别问题。相邻的单词仍然完全不匹配。
- 重新设计了离线教师后备，以实现清晰、流畅的短单词：质量第一的美式英语语音选择、不间断的发声、适中的语速、中性音调、终端边界和更长的释放。本地合成/转录认可`of`、`at`、`cat`、`come`和`look` 5/5；仍然需要人类说话者的聆听。
- 重新生成了Xcode项目，通过了548/548Swift测试和5/5关键XCUITests，为两个目标模拟器构建了新的LocalQA应用程序，签署了物理设备版本，并将其安装在连接的iPhone17 Pro Max上。

## v0.3 设备验收记录

安装证据记录在这里；人类儿童/父母的接受程度仍然是分开的。

| 日期 | 设备 | 版本/版本 | 测试仪 | 结果 | 注释/证据 |
|---|---|---|---|---|---|
| 2026-07-14 | iPhone 17 Pro Max | `v0.3.0` (`2026071401`) LocalQA | Codex 安装；父级 + 子级接受待定 | 已安装 | 签名版本已成功安装。人类`of`、发音、语音、手写、旋转和可访问性检查仍然存在。 |
| 待定 | iPad Pro 13 英寸 (M5) | `v0.3.0` 候选 | 家长+儿童 | 待定 | 以上完整 v0.3 清单。 |

## v0.3.1 — 2026-07-14

目标发布：`v0.3.1`

Branch: `v0.3.1`
Baseline: `main` 和 `cc42e17`，合并了 v0.3 至 PR #2。
总体状态：生产修复、自动回归、签名iPhone和iPad安装、物理设备生产视觉测试、物理iPad关键UI通过、离线教师音频候选以及模拟器验证的世界艺术许可。儿童手写、音频收听、旋转和无障碍接受仍然开放。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V031-BUG-001 | Bug | Write 识别 | 真正的手写识别必须接受 `of` 和 `go`，独立于小写、首字母大写或全大写输入。测试必须运用生产渲染器和视觉服务，而不是制造的OCR候选者或演示识别器。字面 `90` 和相邻单词不得作为 `go` 或 `of` 传递。 |自动物理iPhone和iPad合成通行证；儿童笔迹待定 | 实体生产服务测试已通过 iPhone 和 iPad。接下来，让孩子在没有帮助的情况下分别写下`of`、`Of`、`OF`、`go`、`Go`和`GO`两次；需要 12/12 或捕获隐私安全的故障诊断。 |
| V031-IMP-001 | 改进 | 学习音频 | Read `Hear it` 和 Write 参考语音使用一份规范的离线教师合同。 500 字的 Katie 包提供单独的 0.90× Read 和 0.82× Write 剪辑；记录在案的`bun`语音/速度覆盖修复了客观上不清楚的渲染。包丢失失败，无法关闭 Apple en-US TTS。语音提示使用语音音频播放会话，回避应用程序音乐和外部音频，然后在不中断录音的情况下恢复正常混音。 | 自动解码、捆绑和转录过程；物理监听待定 | 在目标 iPhone 和 iPad 上，监听 `of`、`at`、`cat`、`come`、`look`、`bun` 和一个包丢失单词。确认预期的声音、清晰的话语、可听见的最终辅音、没有剪辑的开始/结束以及流畅的音乐闪避/恢复。 |
| V031-FEAT-001 | 功能 | 配置文件和预设词 | 每个新的 Profile 路径都需要从 3 到 8 的明确年龄。家长设置保留明确的成绩控制； Kid self-create 根据年龄得出当前支持的等级建议。 Parents可以浏览按年龄/年级排名的离线版本化目录，搜索或导航其层次结构，选择单个/所有单词，并明确添加到Read、Write或两者。没有推荐自动添加。每次导入仍受发起它的Profile的约束。如果池失败、返回部分结果或返回不匹配的成员资格 ID，则“两者”导入都会进行补偿。补偿仅撤销由该请求插入或重新激活的成员资格，并保留已激活的单词。 | 自动通行证；物理iPad明确批准流程；手动布局待处理 | 通过首次运行创建配置文件、Kid 自行创建和 Parents；验证保存的年龄和年级。浏览所有根，搜索一个单词，打开一个没有任何池突变的列表，然后显式添加到每个目的地并确认标准化重复数据删除。练习失败、部分结果、不匹配、刷新失败、并发激活以及两者的交叉Profile情况。 |
| V031-FEAT-002 | 功能 | 预设目录内容 | 交付独立策划的 3–8 / Pre-K–Grade 3 目录，其中包含 34 个叶预设、1,365 个单词参考和 1,166 个标准化唯一单词。每页包含 40-45 个有效的单词，涉及视觉词汇、语音/拼写、精细名词主题、动词、情感和概念。使生成的 Obsidian Markdown 目录与 App JSON 保持一致并公开方法源。 | 自动内容审核通过 | 运行捆绑目录审核器，验证每个叶子都在 30-50 个单词内，并且每个源 ID 都解析，然后抽样审查年龄/年级适合度、儿童安全、拼写、类别相关性和生成的黑曜石注释。 |
| V031-FEAT-003 | 功能 | 父词删除 | Read 和 Write 各自公开了 `Delete all N words`。该操作始终确认确切的计数/模式，停用池而不擦除学习历史记录，保持其他模式不变，并提供完全撤消。根据Profile，首次删除确认和撤消状态保持隔离。快照故障会在报告故障之前补偿成员资格突变。 | 自动通行证；物理 iPad 全部删除/恢复和顺序删除流程；手动布局待处理 | 清除具有混合历史记录的每种模式，取消一次，确认一次，撤消一次，然后切换配置文件。验证其他模式/Profile加上历史报告是否未更改，并且失败的突变后快照不会留下隐藏的池更改。 |
| V031-NIT-001 | UI 优化 | 世界场景 | 将城堡、独角兽、车辆、动物和扩展世界故事艺术进一步移动到下边带，而不移动前景控件。环境艺术可能只会从其安全基线向下漂移。 Moonpetal 的独角兽必须完全保持在画布上，并且在每个动画帧上都与 Write 卡片和阴影明显分离。 |已实施；聚焦几何 5/5 和 iPhone/iPad 模拟器视觉通行证 | 在 iPhone 17 Pro Max 和 iPad 景观上，等待 Moonpetal 和一个扩展世界中的完整环境循环。要求每张任务卡周围有可见的背景间隙，并且底部/侧面没有剪裁。 |

### 2026-07-14 v0.3.1 笔记

- 添加了离线 3-8/Pre-K-Grade 3 预设目录、明确的年龄捕获和生成的黑曜石目录。年龄和年级排名建议，但切勿添加文字。
- 将预设导入绑定到启动Profile。现在，这两种导入都会在失败、部分成功、不匹配结果或刷新错误后补偿精确插入/重新激活的成员资格，同时保留已激活的单词。
- 添加了按池删除全部并具有精确确认和完整撤消功能。确认和撤消状态现在按照 Profile 保持隔离，并且快照故障补偿池突变。
- 将回归覆盖范围扩大到 595 Swift 测试。 1,008 个捆绑音频文件干净地解码为单声道 44.1 kHz AAC-LC，并且新的 iPhone/iPad 应用程序捆绑包包含字节相同的资源树，没有凭证形状的令牌。
- 将世界故事艺术转移到安全地带。 Moonpetal 还缩短并右移了独角兽，足以在整个环境循环中在Write卡下方保留可见的间隙。 iPhone 月瓣和全屏 iPad 恐龙模拟器捕获通道，没有剪切或前景重叠。

### 早期测试遗漏了什么

- 早期的案例测试在 Vision 之后开始，通过注入 `of` 等字符串，
`Of`和`OF`。仅当 OCR 已经发出正确的字母时，他们才证明了大小写标准化。
- 关键的Write XCUITest 有意使用确定性演示
识别器。它证明了反馈消除和导航，而不是手写准确性。
- 在 v0.3.1 之前，没有断言测试通过生产发送非空笔划
渲染器、Apple Vision、转录解析器和最终决策一起。

### 根本原因和有限修复

- 实际生产链探针显示小写`of`未产生任何愿景
以默认 26 点光栅宽度进行观察。 36 点回退栅格返回精确的 `of`。
- 小写`go`产生最高候选`90`加上较低候选`g0`；一个
单独绘制的文字`90`不包含任何证实的`g`候选者。
- 生产现在最多运行两个独立的光栅通道（26 和 36 点），
启用目标词语言校正，并提供小写、首字母大写和全部大写词汇。每一遍必须独立解决完整的目标。
- 案例标准化后匹配仍然准确。 `0` 只能标准化为 `o`
在完整的目标匹配中。仅当另一个相同长度的 Vision 候选者在该位置明确包含 `g` 时，`9` 才可以标准化为 `g`。没有编辑距离或接受任何墨水回退，并且文字 `90` 仍被拒绝。

### 确认

- 严格的Swift格式和完整的Swift套件通过：595/595，零失败。
- 重点关注的macOS实际视觉套件通过了15/15，其中包括六项`of`/`go`
大小写变体和真实呈现的否定`on`、`if`、`off`、`do`、`no`和文字`90`。
- iOS 26.5.1 上连接的 iPhone 17 Pro Max 通过了新的生产服务
设备目标：2/2 XCTest 案例，涵盖 6/6 阳性变异和 4/4 阴性对照。赛程是匿名合成载体；不会存储或提交任何子中风。
- 七个关键 UI 流程在 iPhone17 Pro Max 模拟器上通过了 7/7。他们
保留生命周期/导航证据，不计为视觉准确性。
- iPadOS 26.5 上的 Darren iPad Air 13 英寸 (M4) 通过了生产物理测试
DeviceTests 2/2：错误词拒绝和`of/go`大小写变体。
- 相同的iPad通过了LocalQA关键XCUITest目标7/7：OCR添加全部，
全部删除/恢复、明确预设批准、顺序删除/排序、照片选择器/排序以及Read/Write完成解雇。
- 历史 iPhone 月瓣和 iPad 恐龙截图确认：等待环境动画周期后，底层场景艺术仍明显避开前景任务卡。
  临时截图文件已在 v0.7.43 仓库清理中移除。
- 适用于 iPhone 17 Pro Max 和 iPad Pro 13 英寸的全新LocalQA 模拟器构建通行证
（M5）。已签名的 `Tada Words QA` v0.3.1 (`2026071402`) 已在连接的 iPhone 上安装并启动。
- 团队 `6S245NCUPQ` 签署了 `Tada Words QA` v0.3.1 (`2026071403`) 已安装并
在连接的iPad上启动。儿童手写、音频、布局、旋转、Apple Pencil 和辅助功能接受仍然开放。

## v0.3.1 设备验收记录

| 日期 | 设备 | 版本/版本 | 测试仪 | 结果 | 注释/证据 |
|---|---|---|---|---|---|
| 2026-07-14 | iPhone 17 Pro Max、iOS 26.5.1 | `v0.3.1` (`2026071402`) LocalQA | Codex 自动化设备测试；父母+孩子接受等待|已安装；合成生产 Vision 通过 | 6/6 个阳性病例变体和 4/4 个阴性对照通过生产服务。儿童手册第 `of`/`go` 12 次尝试门仍然存在。 |
| 2026-07-14 | Darren iPad Air 13 英寸 (M4)、iPadOS 26.5 | `v0.3.1` (`2026071403`) LocalQA、团队 `6S245NCUPQ` | Codex 自动化设备和 UI 测试；父母+孩子接受等待|安装并启动；设备测试 2/2；关键 XCUITest 7/7 | 生产测试通过了错误词拒绝和 `of/go` 案例变体。 UI 测试通过了OCR添加全部、删除全部/恢复、显式预设批准、顺序删除/排序、照片选择器/排序和Read/Write完成解雇。儿童手写、音频、布局、旋转、Apple Pencil 和辅助功能仍然保留。 |

## v0.4 — 2026-07-14

目标发布：`v0.4`

Branch: `agent/v0.4-offline-audio`

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| AUDIO-FEAT-001 | 功能 | 教师单词音频 | 使用 Katie 主导的 500 字离线包，其中包含单独的 0.90× Read 提示和 0.82× Write 提示。当客观 QA 拒绝规范渲染时，清单可以记录单词级语音或速度覆盖。捆绑包未命中必须无法关闭至 Apple en-US TTS；可能不会传送提供程序密钥或运行时依赖项。第 16 条已实施；自动传递| 在iPhone和iPad上，比较两种模式下的`a`、`i`、`at`、`come`、`of`、`the`、`said`、`bun`以及两个长动物词。确认正确的发音、完成最终辅音、平滑闪避以及清单外一个单词的 Apple 后备功能。 |
| AUDIO-FEAT-002 | 功能 | 启动和转换 | 使用 Aurora 进行批准的连续 `Ta-dá↗ woooords↘!` 冷启动标记、六个不重复的正确答案微庆祝和一条 Quest 完整线路。在下面保留即时的世界特定综合反馈； Reduced Sound 抑制装饰性言论。 |已实施；自动化结构传递；设备侦听待|冷发射两次，确认上升`da`，无故意间隙，加长下降`wor`，然后完成一项Read和一项Write Quest。切换语音/音效/Reduced Sound，确认录音无重叠、无重复冷启动痕迹、响度舒适、无疲劳感。 |

### 音频实施证据

- 生成并检查了 1,000 个 Katie 文字剪辑以及 8 个 Aurora 剪辑。
- 所有 1,008 个文件均解码为单声道 44.1 kHz AAC-LC；合并的音频大小为 6,807,998 字节。教师包持续时间为 674.80 秒，Aurora 持续时间为 8.74 秒。
- 完整的 1,000 个 Apple Speech 剪辑审核已通过第二次 Whisper 审核，以找出真正的嫌疑人。同音字拼写差异被忽略； `near` 和 `chick` 已通过 IPA 进行纠正，并且在两个识别器均拒绝 Katie 后，`bun` 现在使用清单记录的 Aurora 覆盖。最终的目标剪辑通过两个识别器。
- 所有者拒绝了第一个直接 TTS 启动渲染，因为`da` 没有上升并且连接听起来太长，然后拒绝了分阶段替换，因为第一个音节听起来像降调“塔”而不是浅色“他”，并且重复的源切片在`da`之后产生了额外的重读`a`。 Aurora pack 1.0.2 仅在短暂的`/tə/`（大约 332→334 Hz）内保留自然水平到上升的起始，将一个不重复的连续`/dɑː/`窗口延伸到大约 380→394→459 Hz，并且仅使用 8 毫秒的点击安全连接到`words`。静音检测未发现内部暂停。准确的特征和自然度仍然是所有者设备收听质量检查的一部分。
- Swift6 软件包套件通过了 594/594 测试，包括捆绑清单、变体路由、后备和 Aurora 资源检查。演讲者的身体疲劳、混音和儿童反应仍然是手动验收项目。

## v0.4.1 — 2026-07-14

目标发布：`v0.4.1`

Branch: `agent/v0.4.1-slower-teacher-audio`

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| AUDIO-FIX-003 | 改进 | 教师单词音频 | 在 `1/1.5 ≈ 0.67×` 处生成 Read 和 Write 独立单词；保留末端辅音，例如`at`中的`/t/`。第 18 条已实施；自动声音和识别通过| 在iPhone和iPad上，在两种模式下收听`at`、`cat`、`sit`、`dog`、`help`、`look`和`with`。确认 Pre-K 的节奏是舒适的，并且最终辅音没有被扬声器响应或音乐恢复所掩盖。 |
| AUDIO-FIX-004 | 改进 | 语音转换 | 从任务完成行中删除作为正确答案感叹词的 `Ta-da!`。 `Tada Words` 冷启动品牌名称保持独立。 |已实施；自动清单和识别通过| 完成足够的单词以轮流浏览每个正确答案短语，然后完成一个任务。确认没有转换如`Ta-da`；冷启动还是得说产品名称。 |

### v0.4.1 实施证据

- 以 0.67 倍的分辨率从清单版本 1.1.0 重新生成了所有 1,000 个 Katie/Aurora 覆盖教师剪辑。每个剪辑在 AAC 编码之前接收 120 ms 的波形后填充；播放已经等待完整的`AVAudioPlayer`完成回调。
- 所有 1,000 个教师文件均解码为单声道 44.1 kHz AAC-LC。教师时长为863.12秒；所有 1,008 个音频资源总计 7,428,104 字节。
- 新的 `at` 剪辑为 0.68–0.76 秒，而更改前为 0.48–0.56 秒。静音/能量检查显示停止关闭，随后的`/t/`释放，然后是受保护的尾部。
- Whisper 独立转录了 Read 和 Write 的 `at`、`it`、`cat`、`hat`、`sit`、`hit`、`get`、`cut`、`hot`、`not`、`dog`、`big`、`red`、`stop`、`help`、`look`、`fish`、 `duck`、`back`、`off`和`with`，其末端辅音完好无损。在 50 个可用的精选剪辑中，43 个是准确的单词；七个仅在元音或开头辅音方面有所不同，同时保留了预期的结尾辅音。三个请求的审核词不属于家长批准的 500 字清单的成员，因此被排除而不是默默添加。
- 正确答案清单现在显示五行，并且不再显示`Ta-da!`。重新生成的任务完成剪辑仅包含`Quest complete!`； Whisper 将其转录为 `Quest complete.` 私有 `correct/ta-da.m4a` 资源仍然仅作为单独冷启动品牌标记的可复制源组件，并且无法通过过渡轮换访问。
- 在发布前集成当前的`origin/main`（`02e23aa`），因此 v0.3.1/v0.3.2 世界艺术、设备 QA、视觉、UI 复制和项目设置更改仍然是基线。只有较新的 v0.4.1 音频资源和音频合同才能取代早期版本。
- 严格的Swift格式和完整的集成后595测试包套件通过。早期的通用iOS模拟器版本包含所有1,008个资源，其捆绑的`at`哈希与审查的源资产相匹配；合并之前需要一个新的合并树iOS构建。

## v0.4.2 — 2026-07-14

目标发布：`v0.4.2`

Branch: `agent/v0.4.2-transition-pause`

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| AUDIO-FIX-005 | 改进 | 字间音频计时 | 新字绝不能直接附加到正确答案转换音频的末尾。等待完成转换，将现有的可见反馈保持在最低限度，然后在前进到任何非最终Read/Write项目之前留下 700 毫秒的沉默。不要在任务结果之前添加项目间暂停。 |已实施； 600/600 预合并测试和模拟器构建已通过 | 完成连续的 Write 项目，包括语音打开、语音关闭、Reduced Sound 和正常音效。确认每个下一个提示在明显的暂停后开始，并且没有过渡被截断；重复Read以确认其字卡没有提前推进。 |

## v0.5 — 2026-07-14

目标发布：`v0.5.0`

Branch: `v0.5`

Baseline: 合并`v0.4.2`，包括恢复的 v0.3.2 设备 QA 修复和
v0.4.1 离线教师音频包。总体状态：集成自动化验证通过； iPad 儿童/家长的身体接受仍然开放。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V05-UX-001 | UX 重新设计 | 家长导航 | 用一个紧凑的 `Parent Home` 替换长家长仪表板：单个 `Kids` Profile 入口、`Words & Practice`、`Progress & Performance`、`App & Family` 和 `Lock`。言语管理和孩子的表现绝不能属于同一类别。删除重复的池/管理/预设入口，并将每个详细信息页面返回到其所属的类别中心。 | 自动通行证；视觉设备 QA 待定| 在两个父方向的 iPhone 和 iPad 上，仅一次达到每个现有的父功能，验证返回到所属中心，并确认在支持的 Dynamic Type 尺寸下没有卡片文本换行或剪辑。 |
| V05-FEAT-001 | 特征 | Write 拼写 | 开头 Write 要求孩子选择 `Write by Hand` 或 `Spell with Letters`。任一选择都完成相同的每日Write Quest（规则 B），使用相同的Write池/掌握/复习时间表，并且仅获得一次完成/奖励。拼写检查使用完全采用 SwiftUI 构建的主题色、固定位置 QWERTY A–Z 键盘；它永远不会打开iOS键盘。大小写被忽略，撇号/连字符是结构性的，打字速度永远不会与手写速度进行比较。 Focused Replay 保留所选的输入法。 | 自动通行证；物理儿童 QA 等待| 完成两项选择，验证一个每日Write 完成/奖励，检查每个世界中的所有 26 个字母键以及删除/Done，断言没有系统键盘、测试用例和标点符号、错误答案引导重试、Replay、重新启动恢复、VoiceOver 顺序和两个横向方向。 |
| V05-IMP-001 | 改进 | 实践默认值 | 新配置文件默认为 5 个新词和 5 个评论 Write 单词，而不是 3 个和 3 个。现有配置文件保留每个已保存的自定义值；没有任何迁移会覆盖父级的选择。 |自动传递|创建一个新的Profile并参见5/5；重新打开具有自定义 Write 限制的现有 Profile 并确认保存的值未更改。 |

### 2026-07-14 v0.5 笔记

- 将家长工具重组为三个类别中心，同时保留每个单词，
报告、日历、Profile、通知、音频、辅助功能和同步功能。
- 将原来的一体化设置页面拆分为练习计划、声音和
辅助功能和通知。每次保存都会针对最新的Profile设置执行范围合并，因此隐藏值不会被覆盖。
- 添加了面向儿童的 Write 输入选择器和主题匹配的 A–Z 键盘。
手写和打字拼写共享Write学习契约，而尝试速度仍然因输入法而分开。
- 仅将新创建的Profile设置的默认值提高到5/5；坚持
Profile 设置仍然具有权威性。
- 与个人团队注册并签署新连接的iPad
`6S245NCUPQ`; v0.3.2 (`2026071406`) 已成功安装并启动。
- 通过 PR #7 恢复了经过设备测试的 v0.3.2 QA 修复，然后将它们合并
在将生成的 `main` 基线引入 v0.5 之前，将其引入 v0.4.2 PR #6。
- 集成的 v0.5 树通过了 619/619 Swift 测试、严格格式 lint、a
全新通用iOS模拟器构建，以及所有8/8关键模拟器UI流程。它的大厅 → Write → 拼写流程确认了所有 26 个自定义键，没有本地键盘、第一个单词输入和项目前进。
- Exact v0.3.2 (`2026071406`) 已成功在连接的设备上重新安装
阅读iPad。 Mac 端自动启动被拒绝只是因为 iPad 仍处于锁定状态；安装的应用程序解锁后即可直接打开。

## v0.5.1 — 2026-07-15

目标发布：`v0.5.1`

Branch: `v0.5.1`

Build: `2026071504`

总体状态：实施已完成，638/638Swift测试通过。完整的九流模拟器UI矩阵在手机和平​​板上传递；肉体的孩子/父母的接受仍然开放。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V051-UX-001 | UX 改进 | 家长主页 | 将可见的 `Lock` 控件替换为 `Back`。返回返回到上一个子页面并恢复下次访问的Parent Gate。将活跃的儿童世界与现有场景、面板、颜色和触觉按钮组件相匹配。去除标语和多余标签；缩短进度标题和计数摘要。 | 自动通行证；设备视觉 QA 待处理 | 输入 Kid 选择中的 Parents，完成门控，确认 `Back` 替换 `Lock`，然后返回到上一个子页面。重新输入Parents并确认门仍然出现。在支持的家长方向中检查手机和平板电脑上的所有八个世界主题。 |
| V051-UX-002 | UX 改进 | 启动 | 显示品牌启动页面至少 1.8 秒，播放捆绑的 `Tada Words` 启动签名，然后淡入应用程序。使用官方 Tada Words 和 Pawgoo 标记以及响应式手机/平板电脑尺寸和一个组合辅助功能标签。 | 自动通行证；设备视觉/听觉 QA 待处理 | 在支持的方向上在手机和平​​板电脑上冷启动。确认官方标记、口头品牌签名、最短持续时间、褪色、VoiceOver 标签以及不与隐藏应用内容交互。 |
| V051-BUG-001 | Bug | Write 识别 | 改进精确的`of` 恢复，无需模糊接受。仅对于 `of`，收集三个渲染和识别比例，检查最多 10 个视觉候选，包括混合大小写`oF`，涵盖六种类似儿童的笔画样式，并仅在包含`o`的目标位置接受数字`0`。要求对排名较低的目标证据进行两个尺度的佐证，并在任何尺度暴露出强大的完整`off`时否决匹配。其他目标保留 v0.5 两遍/前五行为。 | 自动通行证；儿童手写待处理 | 让孩子在每个目标设备上分别书写和连接 `of`、`Of`、`OF`、`oF`、`0f` 和 `0F` 两次。拒绝`if`、`on`、`or`、`ot`、`off`、`00`、`90`、`0t`、`0ff`、`+0`和`f0`；捕获任何错误拒绝的隐私安全诊断。 |

### 2026-07-15 v0.5.1 笔记

- 将父主页 `Lock` 替换为 `Back`。可见的动作返回到
之前的子页面，而路线会为下次访问恢复 Parent Gate。
- 重复使用活跃的孩子世界的背景场景、颜色、面板和触觉
对家长主页的控制。删除了标语、多余的`Kids`标签和较长的摘要；将`Progress & Performance`重命名为`Progress`。
- 添加了一个最短 1.8 秒的启动页面，包含官方Tada Words 和 Pawgoo
标记、捆绑的语音品牌签名、短暂的褪色以及一个组合的辅助功能标签。仅在配置音频首选项后才开始生产启动倒计时，而温暖的本机启动颜色可避免品牌页面之前出现冷蓝色闪烁。
- 为`of`添加了特定目标的三尺度证据，仅扩展了其愿景
来自 5 到 10 名候选人的观察，添加了混合大小写的 `oF`，并涵盖了六种类似儿童的风格。数值 `0` 仅在目标对齐的 `o` 处标准化为 `o`，允许 `0f` 和 `0F`，同时拒绝 `00`、`90`、`0t`、`0ff`、`+0` 和 `f0`。排名较低的精确目标必须在两个尺度上重复出现；任何强有力的完整`off`证据都会否决一场比赛，即使它出现在早期的`of`之后。三十对 `ot/on/or/off/if` 对照仍被拒绝。换句话说，保留其 v0.5 两遍/前五行为，没有模糊匹配或全局阈值更改。
- 将版本和 LocalQA 标识设置为 v0.5.1 (`2026071504`)。树经过
638/638 Swift 测试和严格格式 lint。关键的 XCUITest 矩阵在 iPhone 17 Pro Max 上通过了 9/9，在 iPad Pro 13 英寸模拟器上通过了 9/9。
- 在检测到
并行自动化PR保留了`2026071503`，防止两条发布线共享一个LocalQA构建标识。
- 直接将签名的物理包验证为 v0.5.1 (`2026071504`)、LocalQA
捆绑 ID `com.tadawords.app.localqa`，团队 `6S245NCUPQ`；其配置文件包括注册的 iPhone 和两台 iPad。安装和安装版本验证在阅读iPad时成功。在安装更正的软件包之前，iPhone 变得不可用，并且 iPad Air 13 英寸 (M4) 配对 Wi-Fi 隧道超时。重新连接这两个设备，安装`2026071504`，并在物理验收之前进行库存验证。

## v0.6.0 — 2026-07-15

目标发布：`v0.6.0`

Branch: `agent/batch-kid-ui-v0.6.0`

Build: `2026071601`

总体状态：实施、严格 lint、641/641 Swift 测试通过。仍然需要精确HEAD模拟器、签名设备和儿童可用性证据。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V060-UX-001 | UX 改进 | Kid UI | 删除在Profile、大厅、Read、Write/法术、结果、世界、日历和收藏中重复明显图标、目标、状态或艺术作品的可见副本。保留个人资料名称、Read/Write身份、目标词/槽、有意义的进度、破坏性/恢复标签以及完整的VoiceOver含义。第 19 条已实施；模拟器/设备证据待定 | 使用复制矩阵以及在 iPhone 17 Pro Max 和目标 iPad 上捕获之前/之后。验证两个 Done 控件都是复选标记优先的 72×72 pt 操作，具有稳定的标识符、VoiceOver 标签/提示和未更改的行为。练习VoiceOver、Dynamic Type、Reduce Motion、Reduced Sound、两个横向、错误/加载/锁定状态和关键 E2E 矩阵。 |

### 2026-07-15 v0.6.0 笔记

- 替换了重复的Profile、大厅、任务、结果、世界、日历和收藏
现有 SF 符号、国家边界、吉祥物、星星、奖励和选择/锁定徽章的解释。
- 保留可见的`Read`和`Write`身份、个人资料名称、目标词和
字母槽、有意义的锁定世界进度、破坏性`Clear`，以及所有加载、许可、技术重试和父恢复副本。
- 使用以下命令将手写和拼写提交转换为复选标记优先控件
共享 72 pt Kid 动作令牌。两者都保留 `Done` 作为 VoiceOver 标签，保留显式提示，并公开稳定的 `write.done` / `spell.done` 钩子。
- 添加了逐路复制处置矩阵和重点回归测试
用于空闲Read复制抑制、状态麦克风反馈、提交可访问性合同、稳定标识符和 72 点触摸目标。
- 跨生产的保留版本`0.6.0`和单调构建`2026071601`，
LocalQA，XcodeGen 配置、生成的项目设置和发布文档。

## v0.6.1 — 2026-07-17

目标发布：`v0.6.1`

Branch: `agent/batch-parent-v0.6.1`

Build: `2026071701`

总体状态：Issue#15 实施和自动模拟器覆盖范围通过；物理链路开放和人类可达性接受仍然开放。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| APPSTORE-015 | 改进 | 家长隐私/支持 | 仅在 Parent Gate 之后公开 Pawgoo 的隐私政策和支持页面，并解释家长如何删除本地 Profile 数据或审查 iOS 权限而不更改数据行为。 | 自动通行证；物理链接质量检查待定| 在iPhone和iPad上，完成Parent Gate，打开应用程序和系列，点击两个链接，返回到相同的父状态，离线重试，并检查VoiceOver和大Dynamic Type。 |

### 2026-07-17 v0.6.1 笔记

- 添加了 Tada Words 隐私政策和 Pawgoo 支持的固定 HTTPS 链接
受保护的应用程序和系列表面内的页面。链接标签、浏览器打开提示和稳定的可访问性标识符都是明确的。
- 添加了面向家长的删除一名孩子的本地Profile数据的说明
以及查看 iOS 设置中的相机、照片、麦克风、语音识别和通知。帐户、跟踪、分析、购买或数据收集行为没有改变。
- 跨源 Plist 将版本和 LocalQA 身份设置为 v0.6.1 (`2026071701`)，
`project.yml`，以及生成的Xcode项目。
- 严格格式 lint、所有 643 Swift 测试和所有 14 Issue 代理测试均通过。重点应用程序和系列
资源流在 iPhone 17 Pro Max 和 iPad Pro 13 英寸模拟器上传递。物理 Safari 打开、离线行为、VoiceOver 和大Dynamic Type 仍然是人工发布验收工作。

## v0.6.7 — 2026-07-18

目标发布：`v0.6.7`

Branch: `agent/batch-automation-v0.6.7`

Build: `2026071804`

总体状态：发布候选预检和Issue代理调度程序更改通过完整的自动化套件；实时 LaunchAgent 安装和精确的HEAD运行时观察与PR合并验收分开记录。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| AUTO-020 | 功能 | 发布自动化 | 仅在源身份、签名、权利、资源、隐私和清理树检查通过后生成确定性发布候选清单。 | 自动传递 | 针对已签名的存档/导出运行预检并保留其精确的HEAD 清单。 |
| AUTO-038 | 政策 | 版本控制 | 虽然第一个公开的 App Store 版本不完整，但拒绝任何当前、保留或高于 `v1.0.0` 的提议版本；普通的Issue示例不是保留。 |自动通行证|接受`v0.9.9`、`v0.10.0`和上限；拒绝`v1.0.1`、`v1.1.0`和`v2.0.0`；在发布后过渡之前需要完整的所有者证据。 |
| AUTO-047 | 可靠性 | 皮卡所有权 | 在实施之前添加 `agent-reclaimed` 并获得独特的远程租赁，以便重叠的工人不能同时实施一个 Issue。 | 自动通行证；实时争用观察待定 | 运行重叠民意调查并证明一名租约获胜者、一名安全跳过者以及没有重复的分支/PR。 |
| AUTO-048 | 可靠性 | PR 协调 | 链接精确的开放PR所有权并关闭过时的Issue，仅用于合并到当前`origin/main`中的精确关闭参考，以后不再重新打开。 | 自动通行证；实时对账待定| 行使开放PR、合并PR、重新开放Issue、模糊提及、所有者分支标记和更改PR HEAD。 |
| AUTO-049 | 操作 | 调度程序 | 每 900 秒运行一次，具有 `gpt-5.6-sol` 和推理工作 `ultra`，在一个全工作人员 macOS 锁定下。 | 自动通行证；实时 LaunchAgent 观察待处理 | 验证加载的 plist 间隔/模型/工作量、重叠刻度、空队列无操作和日志/状态保留。 |
| AUTO-050 ​​| 流程 | Issue-首次交付 | 每个实施/变更请求都会搜索并删除重复的 Issue，创建有界缺失的Issue，然后在编辑前立即回收。答复、诊断、审查和状态请求保持只读状态。 | 自动传递 | 查看回购指令并通过相同的回收路径启动新的实施会话。 |
| AUTO-051 | 可靠性 | 准入和阻止程序 | 拾取顺序为 P0→P1→P2→P3→未指定，然后是依赖项/Issue编号。阻止者会生成持久报告、阻止状态、声明删除和经过验证的租约释放。 | 自动通行证；实时阻塞恢复待定| 证明 P0 排序、阻塞释放、同伴批次释放、新鲜回收要求、主动PR 序列化和远程分支重复预防。 |

### 2026-07-18 v0.6.7 笔记

- 将 LaunchAgent 间隔从 10 分钟更改为 15 分钟并固定无人值守
在本地模型目录检查和实际探测后执行 Sol Ultra。
- 用整体工作 `lockf` 锁替换了 PID 目录竞争。两人赛跑者
测试证明第二个进程在检查之前退出，而第一个进程通过模拟 Codex 阶段拥有锁。
- 添加了精确的打开/合并PR协调、所有者创作的远程分支
所有权标记、新主合并可达性以及重新打开保护。模糊的文本和标题相似性永远不会导致Issue。
- 添加了可见的回收标签以及独特的远程租赁提交、实时重新检查
突变之前、受保护的租约删除、失败的保留清理以及事件确认之前的持久结果验证。
- 添加了优先级优先、仅显式批次准入。类似的`area`标签没有
更长地组合不相关的Issue，并且默认的活动实施通道是一个精确的HEAD批次。
- 添加了阻止程序报告/发布。旧版被阻止的音频 Issue #13 是
解除其声明和版本/构建保留；其未更改的远程占位符分支已被删除，而阻止程序证据仍然存在。
- 添加了存储库拥有的应用商店前版本策略并停止处理
Issue散文中的版本示例作为主动保留。
- 完整的精确树门通过：严格的Swift格式，646/646Swift测试，
37/37 Issue 代理测试和 11/11 发布预检测试。
## v0.7.0 — 2026-07-18

目标发布：`v0.7.0`

Branch: `codex/batch-family-sync-v0.7.0`

Build: `2026071806`

总体状态：跨设备 Family Sync 源合同、严格格式门、814/814 Swift 测试、14/14 Issue 代理测试以及源批量模拟器矩阵通过。生产CloudKit模式、精确承诺HEAD模拟器重新运行、签名iPhone/iPad私有/共享流、破坏性测试专用擦除、后台交付和人工可访问性/恢复审查仍然是发布大门。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V070-FEAT-001 | 功能 | 跨设备同步 | 保持每个任务本地优先，同时通过私人/共享 CloudKit 同步家长批准的 Profile 事实、Read/Write 池、独立设置组、不可变的学习事件、派生进度、每日完成/奖励事实以及有界的 Profile 照片。 | 源和确定性模拟器 E2E 通行证；生产验收待定 | 在确切提交的 HEAD 上重新运行六流程套件，然后在已签名的 iPhone 和 iPad 版本上完成相同 Apple-ID 私有同步和不同 Apple-ID 共享验收。 |
| V070-PRIV-001 | 隐私 | 终端删除 | 在删除所有者 Profile 记录/资产/共享/区域之前保留隐私最小删除分类账；使参与者离开并撤销终端；阻止陈旧设备复活并清除 Profile 范围内的传输/照片字节。 | 源删除/隐私保护通过 | 在仅测试配置文件上，在另一台设备离线时删除，重新连接后验证本地清除，并检查真实容器以证明仅保留最小的分类帐。 |
| V070-RECOVERY-001 | 可靠性 | 持久同步 | 避免发件箱、收件箱、应用、确认、服务器记录冲突、隔离、帐户更改和重试状态的进程死亡，而不会丢失本地工作或重复完成/奖励事实。 | 源线束和模拟器重新启动/状态流通过 | 在每次重试边界强制退出两个已签名的设备，按两个顺序重新连接，并在重新启动之前和之后验证父状态。 |
| V070-ACCESS-001 | 功能 | 家庭访问 | 使用 Apple 的生产共享控制器进行现有共享管理，将所有者路由至私有存储，将参与者路由至共享存储，因终端/格式错误的绑定而关闭失败，并通过正常通知路径协调保存/停止事件。 | 源实现和路由/演示测试通过 | 作为所有者和参与者，在签名设备上邀请、接受、删除/离开和撤销；证明撤销的路线不会产生私人后备。 |
| V070-BUG-001 | P0 bug | 升级迁移 | 保留 v0.6.x 编写的每日任务历史记录，其合成的 `QuestStars` 可编码形状为 `{ "earned": [...] }`，而 v0.7.0 编写规范的确定性数组形式。切勿删除或重置不可读的快照。 | 修复了双格式解码和 schema-1 完成/奖励迁移回归；物理重新安装确认待处理 | 升级未更改的 v0.6.x LocalQA 容器，验证应用程序打开，并确认计划、完成情况、奖励、日历和星星保持不变。 |

### 2026-07-18 v0.7.0 笔记

- 添加了一种版本化的私有状态和一种具有持久性的共享`CKSyncEngine`状态，
精确操作发件箱/收件箱持久性、帐户生成隔离、校验和有界信封、精确确认、隔离和更正记录恢复。
- 使冲突解决具有确定性：使用不可变的尝试/更正
稳定的身份，可变的池/设置记录使用逻辑修订，相同修订不同字节冲突无法关闭，并且进度/奖励是根据规范事实重建的。
- 添加了经过验证的 512 px / 256 KiB 准备好的 Profile 照片 `CKAsset`
具有持久暂存、确认清理、身份检查和损坏资产隔离功能的上传。声纹、原始/注册音频、通知、手写残留、图片/音频缓存、OCR和声音缓存保留在本地。
- 实现了清除前的账本终端删除，保留了最低限度的隐私
字段、所有者区域/共享/资产删除、参与者离开、撤销、重启幂等性、陈旧设备上传屏障以及 Profile 范围内的收件箱/隔离区/系统字段/锁/照片暂存清除。
- 添加了家长授权的生产 Apple 访问管理 UI。现存的
所有者和参与者路由使用其持久的私有/共享绑定；撤销、删除和格式错误的路由无法关闭。保存/停止共享委托事件重用幂等通知协调路径。
- 添加了隐私安全的持久父状态，用于待处理计数、重试状态、最后状态
成功、iCloud/帐户恢复、兼容性/损坏/冲突注意以及重新启动一致的演示。诊断不包含儿童姓名、单词、照片、录音、声纹或存储库负载。
- 帐户确认现在报告已更改的 CloudKit 帐户生成，以便
切换帐户后重新启用 Family Sync 会使旧的确认无效并为新确认的帐户播种。重新授权同一帐户仍然是幂等的。
- 业主访问管理现在始终进入运输经过测试的现有-
在介绍苹果控制器之前先分享一下恢复路径。已确认丢失的共享可以重建，瞬时故障会传播，并且参与者永远无法创建私有所有者共享。
- 添加了机器可读的数据清单和五层证据矩阵。仅有的
6个模拟器流程直接观察到的19个字段接收模拟器证据；未观察到的模拟器行和每个物理/人类行仍处于待处理状态。
- 源批次在 iPhone 17 Pro Max 上通过了 Family Sync 6/6 测试，并且
iPad Pro 13 英寸 (M5) 上为 6/6，加上每个模拟器上的临界流 10/10，全部在 iOS 26.5 上。在合并之前，精确承诺的-HEAD重新运行仍然是强制性的。
- 物理就地升级暴露了之前失败关闭的遗留解码间隙
所有保存的数据均已重置。 `QuestStars` 现在接受 v0.6.x 键控表示和规范 v0.7.0 数组，而所有新写入仍保持确定性。回归装置包括一个真实的计划/完成/奖励依赖链，这是早期的空完成迁移测试所遗漏的。

## v0.7.2 — 2026-07-19

目标发布：`v0.7.2`

Branch: `codex/p0-saved-data-recovery`

Build: `2026071902`

总体状态：P0就地数据恢复。在 v0.6.7 LocalQA 包取代 Family Sync 版本后，物理iPhone 显示了通用的“已保存数据无法打开”屏幕。两个只读导出产生相同的校验和清单； JSON 是有效的，但词池、学习记录和每日任务已经处于正向模式 2、4 和 3，而 v0.6.7 仅接受模式 1。

- 带来了先进的 Family Sync 阅读器及其规范数据合同
到最新的合并自动化和离线图片提示基线。没有快照被降级、重置或手动编辑。
- 在创建设备身份之前添加了应用程序级架构预检，
事务重放、删除恢复或载入写入。未来的模式现在会产生隐私安全的“更新Tada Words”指南，仅命名存储和版本边界。
- 为较新的词池添加了重试和无副作用回归覆盖，
学习记录和每日任务模式，加上当前的 2/4/3 引导覆盖率和捆绑的读者策略漂移测试。
- 添加了强制数据保存LocalQA安装包装。它执行一个
只读设备容器副本并在 `devicectl install` 运行之前阻止较旧的目标读取器。
- 复制的真实设备夹具加载了所有 488 次规范尝试，201
保留了单词条目、两个配置文件和任务历史记录。确定性派生进度刷新仅更改了可重建的`progress`投影；规范事实和所有其他快照保持不变。
- 确切的承诺HEAD门通过了严格的格式、821/821Swift测试，
40/40 Issue 代理测试和 11/11 发布预检测试。合并前，精确提交的-HEAD模拟器和数据保存物理设备门被记录在P0PR上。

## v0.7.3 — 2026-07-19

目标发布：`v0.7.3`

Branch: `agent/batch-third-party-notices-v0.7.3`

Build: `2026071903`

总体状态：家长控制的离线第三方归因加上版本化的内容权利清单和用于捆绑图片提示实施的确切源/存档验证器。 Cartesia 权利证据和 Pawgoo 所有权证明在 #32 和 #33 下仍然是独立的人类拦截器。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V073-COMP-001 | 合规性 | 父资源 | 保留确切的 Twemoji 归属、固定来源、未修改状态和 CC BY 4.0 许可证，可在 Parent Gate 后离线访问。 | 来源、存档和重点 iPhone/iPad 模拟器 UI 测试通过 | 保持发布清单与已签名的发布存档同步，并完成人工 VoiceOver 审查。 |

### 2026-07-19 v0.7.3 笔记

- 在家长主页 → 应用程序和家庭下添加了第三方通知目的地。
- 声明所有 74 个捆绑图片提示图形均未经修改，并指出
`jdecked/twemoji` 17.0.3，并公开了确切的版权归属以及来源和知识共享归属 4.0 国际链接。
- 保持每个通知字符串离线可用并保留每个外部链接
Parent Gate；没有添加面向儿童的路线。
- 添加了精确内容、路由/返回堆栈和集中的 UI 回归覆盖范围。
- 聚焦流程以最大的可访问性文本大小启动，验证
每个必需的通知段落和两个资源控件都保留固定的视觉证据，并通过共享的“后退”控件返回到应用程序和家庭。
- 聚焦的父流在 iPhone 17 Pro Max 上通过 1/1，在 iPad Pro 上通过 1/1
13 英寸 (M5)，iOS26.5。
- 完整的预提交门通过了严格的格式、822/822 Swift 测试，
40/40 Issue 代理测试和 11/11 发布预检测试。
- 添加了`Docs/APP_STORE_CONTENT_RIGHTS.md`和可重复的源/存档
验证者。未签名的 v0.7.3 版本存档匹配 1,008 个 M4A 文件、74 个 Twemoji PNG、五个预期的 JSON 文件以及所有测试/资源排除项。

## v0.7.4 — 2026-07-19

目标发布：`v0.7.4`

Branch: `codex/pr29-privacy-v074-refresh`

Build: `2026071904`

总体状态：根据合并的 v0.7.3 源刷新了 App Store 隐私清单。 App Store答案集仍然是有条件的草案，等待生产CloudKit、钥匙串删除、公共政策、运营商证明和精确签名的构建门。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| APPSTORE-017 | 文档 | 隐私清单 | 保留一个版本控制的、有来源支持的清单，用于设备上处理、Apple 服务、Pawgoo 可访问的支持数据、用户控制的导出以及每个配置/休眠的非 Apple 网络路径。切勿发布依赖于未经验证的操作实践的答案。 | 更新源审计和重点回归阶段 | 重新运行清单、依赖项/域扫描，以及针对确切签名的候选版本的 iPhone/iPad 流量观察；获得所有列出的所有者证明|
| APPSTORE-017-WEB | 拦截器 | Pawgoo 隐私/支持 | 将实时页面与捆绑的离线提示、合格的删除保证、钥匙串应用程序删除现实以及完整的分类家庭同步范围保持一致。 | 记录不匹配；公共站点不变 | 发布经过审查的措辞，记录部署的资产/提交，并将两个实时页面与确切的运输行为进行比较 |

### 2026-07-19 v0.7.4 笔记

- 替换了过时的 v0.6.3 审核，该审核仍然描述了 jsDelivr 提示，
缺少家长链接、尚未确定的家庭同步版本以及权威的传输进度。
- 记录了所有 74 个 Twemoji 图片提示都捆绑在一起，并且发货
配置没有教师音频端点、广告、分析、崩溃报告、跟踪 SDK 或外部 Swift 依赖项。
- 添加了缺失的 `UserDefaults` 必要原因声明 (`CA92.1`) 和
独立App Store审查后的源清单合同测试发现，生产手写工具首选项未包含在先前的两类清单中。
- 将当前的 Family Sync 有效负载分类为同步规范事实，
本地重建视图，以及仅设备敏感/恢复状态。添加了回归测试，可防止声纹字段静默进入同步类。
- 用专用有线 DTO 替换了 Profile 同步有效负载，省略了
完全`voiceprintStatus`。存储库导出/应用/身份验证和 CKAsset 照片暂存现在共享该 DTO；传统有效负载保持可读并保留其准确的照片校验和，而远程哨兵无法覆盖设备的钥匙串派生注册。递归合约现在检查每个记录类型、嵌套对象、数组元素、原始包装器和关联枚举情况的实际存储库输出。 1.0 之前签署的多设备验收要求所有设备都采用同一版本；未声明旧二进制/新照片混合版本兼容性。
- 对每个常见的同步信封字段进行分类，包括每次安装的随机字段
逻辑修订UUID，并用显式允许列表加上编码信封合同测试替换了记录类型推断。
- 库存父 CSV 和隐私安全同步诊断共享表，本地
操作系统诊断、APN 触发的 CloudKit 协调、有界 Profile 照片 `CKAsset`、终端删除分类账以及当前的家长隐私/支持/数据控制。
- 重新获取实时 Pawgoo 隐私和支持页面并记录过时的内容
提示下载、删除、钥匙串删除和未指定的家庭同步语言。公共站点或App Store Connect状态没有改变。
- 记录当前应用程序无法删除其唯一剩余的Profile并且
没有完整的“删除所有应用程序数据”路径； #19 必须在应用程序或公共政策声明完成应用内擦除之前缩小隐私差距。
- 打开 #54 以拥有精确的 RC 对齐和现场部署证据
Pawgoo 隐私和支持页面；这批没有改变公共站点。
- 保留 **未收集数据** 以生产 CloudKit 验收为条件，
准确的签名构建流量/依赖性证据、缺少远程音频端点、Pawgoo CloudKit 非访问、支持邮件实践和更正的公共副本。
- 完整的预提交门通过了严格的格式、834/834 Swift 测试，
40/40 Issue 代理测试和 11/11 发布预检测试。

## v0.7.5 — 2026-07-19

目标发布：`v0.7.5`

Branch: `codex/pr36-appstore-v075-refresh`

Build: `2026071905`

总体状态：内部App Store提交包现在使用合并的隐私和内容权利清单，并将元数据声明映射到真实源和测试路径。它从App Store Connect开始一直处于封锁状态，直到确切的签署发布、人工决策、生产CloudKit、最终Profile/全部删除、钥匙串生命周期、公共复制、内容权利和Parents门控权限通过。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| APPSTORE-018 | 文档 | 提交元数据 | 在 Apple 领域限制内保留一个版本化元数据、审阅说明、屏幕截图、声明和精确 RC 预检包，并与合并的隐私/内容权利证据同步。添加了 | v0.7.5 源候选和自动合同覆盖范围 | 重新计算最终本地化字段，验证精确签名的 iPhone/iPad 屏幕截图和审阅者路径，然后通过人工控制的提交工作流程仅输入接受的值 |
| APPSTORE-018-RIGHTS | 拦截器 | 版权/内容权利 | 将 `2026 Pawgoo LLC` 视为临时性的，并且在记录语音权利和 Pawgoo 权利链之前不要做出 App Store 内容权利表示。 | 合并库存可识别每个已发货的内容类别； #32 和 #33 保持开放| 保留帐户/层级证据并为每个选定的店面获取授权的 Pawgoo 作者/版权链证明|
| APPSTORE-018-DATA | 拦截器 | 隐私/公共声明 | 将核心实践/无 Pawgoo 帐户与家长选择加入的 Family Sync 分开，后者需要可用的 iCloud 帐户。当最终Profile无法删除或无法执行完全重置时，请勿声称完全删除。 | 源边界和警告位于元数据包中； #19、#28 和 #54 保持开放| 通过生产破坏性同步和最终Profile/删除所有验收，选择/测试钥匙串生命周期，并部署/验证匹配的 Pawgoo 隐私和支持副本|
| APPSTORE-018-KIDS | 阻止程序 | 权限请求 | 请勿指示应用程序审核者从面向儿童的 Read 屏幕授予语音或麦克风授权。 Tada Words 对此设置采用保守的家长隐私政策； Apple 并未在每次操作系统权限提示之前明确要求家长门。 |电流源可以触发Read中的两个系统提示；元数据和审核步骤被 #55 | 将设置移至 Parents 后面，涵盖拒绝/重试/已授权状态，并在替换审核者占位符 | 之前验证 iPhone 和 iPad 上的确切签名流程

### 2026-07-19 v0.7.5 笔记

- 保留版本`0.7.5`并跨两个源Plist构建`2026071905`，
`project.yml`，以及生成的Xcode项目。
- 添加了带有精确英文元数据的`Docs/APP_STORE_SUBMISSION_PACK_v0.7.5.md`，
审阅笔记、虚构的屏幕截图装置、真实的源/测试链接以及明确的精确 RC 预检。该文件仍标记为内部，并非上传或提交的授权。
- 删除了自然拼读法和抽认卡的误导性关键字声明； 93字节
关键字字段现在描述常见单词、阅读、拼写、手写、单词列表和早期识字练习。
- 记录当前教师音频捆绑或使用离线苹果语音；
两个发货 plist 都没有配置运行时教师音频端点。
- 将共享设备营销语言替换为特定于 Profile 的学习者
措辞。核心实践不需要 Pawgoo 帐户，而 Family Sync 单独需要家长选择加入和可用的 iCloud 帐户。
- 保持父级Profile控制合格：唯一剩余的Profile不能
已删除且不存在完整的“删除所有应用程序数据”路径。 Issue#19 仍然是行为和防破坏门。
- 整合合并的隐私和内容权利清单。 Issue#54 拥有
实时 Pawgoo 副本； #32 和 #33 拥有发言权和 Pawgoo 所有权证据；所显示的 Pawgoo 版权仍然是临​​时的。
- 阻止了 #55 下的当前 Read 权限指令，因为
面向儿童的动作可以触发语音和麦克风系统授权。最终审阅者路径必须从 Parent Gate 后面开始，并在粘贴前通过精确设备验证。
- 本批次不上传至App Store Connect，更改Pawgoo网站，
变异CloudKit，或要求模拟器/设备/人类接受。
- 完整的预提交门通过了严格的格式、837/837 Swift 测试，
40/40 Issue 代理测试和 11/11 发布预检测试。重点元数据限制/本地链接/过时声明合同通过了 3/3，源内容清单独立验证当前版本、构建、音频、图片、JSON、字体、属性和缺席端点边界。

## v0.7.6 — 2026-07-19

目标发布：`v0.7.6`

Branch: `codex/profile-erasure-lifecycle-v0.7.6`

Build: `2026071906`

总体状态：源实现和预提交存储库门已完成 #57 跟踪的 P0、隐私安全 Profile 擦除生命周期。生产CloudKit、真实账户删除、精确承诺HEAD模拟器和签署的跨设备验收仍然是#19、#22和#23下的独立门。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V076-PRIV-001 | P0 隐私 | Profile 删除 | 在本地删除 Profile 后，保留并显示真实请求、删除、等待/重试、需要注意和完成状态。完成需要在所有者或参与者清理路线完成后进行准确的墓碑确认。 | 来源完整；现场验收开放|预提交：998/998Swift、40/40Issue代理和11/11发布预检测试。仍然需要：精确的承诺HEAD模拟器矩阵，LocalQAiPhone/iPad回归，以及生产CloudKit破坏性证明。 |

### 2026-07-19 v0.7.6 笔记

- 为回收的 #57 批次保留版本 `0.7.6` 和构建 `2026071906`。
- 保持本地立即删除和子流非阻塞；耐用的
生命周期是在任何 Profile 有效负载清除之前使用逻辑删除写入的。
- 将生命周期分类为设备本地、隐私最小恢复证据。
它绝不能包含或导出昵称、单词、照片、学习负载、Apple Account标识符或共享 URL。
- 传输发送未完成。只有确切的公认墓碑
在每个所需的所有者或参与者清理步骤成功后，修订可能会完成生命周期。
- 帐户更改失败关闭：无法进行属于先前帐户的清理
通过运行新确认的帐户来得到确认。
- Profile 删除保留来自持久墓碑写入的一个共享突变租约
通过每个本地清除和提交标记。同步读取会等待该租约，并且在本地故障后无法导出未提交的逻辑删除。
- CloudKit元数据拒绝重复的Profile路线、重复使用的区域、缺失
根、丢失帐户来源以及所有者/参与者路由不匹配，而无需重写原始字节。项目记录必须是确切的持久根的父级，因此被拒绝的备用根的子级无法应用。
- 所有者分类账恢复提交其最小的收件箱收据和终端绑定
在每个区域删除证明之后以原子方式重新检查同一元数据事务中的确切Apple Account出处。
- 远程所有者根/区域删除首先保留确切的隐私最低限度
控制区域逻辑删除，然后擦除有效负载区域，清除本地源并终止。每个破坏性或接收消耗边界都会重新检查实时的Apple Account和CKSyncEngine生成。
- 收据触发的子级和父级刷新使用单调生成和
取消，因此较旧的暂停刷新在较新的删除获胜后无法重新发布 Profile 或 Kid。
- 生产全新安装使用随机默认Profile身份并清除
在创建任何本地标记之前，仅Tada Words'设备本地声纹钥匙串服务。现有安装会保留注册，并且重置失败会导致引导程序关闭以重试。
- 父级可见的生命周期和导出的诊断使用匿名聚合；
他们从不公开Profile、Apple Account、分享、昵称、文字、照片或语音数据。
- 预提交存储库门通过了 998 Swift 测试、40 Issue 代理测试、
和 11 项发布预检测试。仅在确切提交的HEAD通过后才会记录模拟器和物理验收证据。

## v0.7.7 — 2026-07-19

目标发布：`v0.7.7`

Branch: `codex/apns-release-preflight-v0.7.7`

Build: `2026071907`

总体状态：问题 #56 在源/工具层实现。规范发布策略现在仅接受开发或生产签名的存档作为中间证据，并要求精确导出的应用程序或 IPA 携带生产 APN 和 CloudKit 权利。此批次不会创建或更改 Apple 资源、证书、配置文件、存档、导出、CloudKit 架构或 App Store Connect 记录。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V077-REL-001 | P0 发布 | APNs 预检 | 将推送权利证据绑定到精确签名的存档并导出，而不接受 LocalQA、源设置、屏幕截图或存档单独作为生产证明。 | 源/工具完整；签署出口开放|重点预检：16/16。仍然需要：完整的精确HEAD存储库和模拟器门，在iPhone和iPad上签署LocalQA身份/安装/启动，以及最终的PawGoo生产存档/导出清单。 |

### 2026-07-19 v0.7.7 笔记

- 为回收的问题 #56 保留版本 `0.7.7` 和构建 `2026071907`。
- 添加了字面源合同
规范政策的`aps-environment = $(APS_ENVIRONMENT)`。
- 添加了 `aps-environment=production` 作为必需的导出应用程序权利。
缺失、开发或任何其他导出值无法关闭。
- 保留小写 `development` 的特定于存档的覆盖或
`production`;这永远不会放松导出的应用程序或 IPA 要求。
- 添加了针对确切源表达式的规范策略测试，有效
生产导出、缺失值、开发导出、开发存档、LocalQA拒绝以及意外的额外权利。
- 记录了清单保留了存档和导出路径、哈希值和
权利字典分开。只有确切的出口才是生产推动的证据。
- 重点发布预检套件已通过 16/16。真实签名的档案和
导出的应用程序尚不存在，因此该批次不会在源/工具门之外提出生产就绪性声明。

## v0.7.8 — 2026-07-20

目标发布：`v0.7.8`

Branch: `codex/issue55-parent-speech-permission-v0.7.8`

Build: `2026071908`

总体状态：源实现将仅子检查的语音和麦克风边界与仅限 Parents 的权限请求功能分开。在#55 或App Store 门关闭之前，仍需要对第一个iPhone 和一个iPad 进行准确签署的首次安装、拒绝、授权、限制和撤销接受。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| APPSTORE-019-KIDS | P1 隐私 | 权限请求 | 子启动、Profile 切换、Read 进入、重播、重新启动和调试演示/深层链接路由绝不能触发语音识别或麦克风系统提示。 Parents 需要一个清晰的设置路线，并为两种权限提供单独的状态。 | 来源已实施；精确设备门打开|确定性否定路由、状态、授权兼容性和故障关闭测试；然后对一个 iPhone 和一个 iPad | 进行精确签名的首次安装、拒绝、授权和撤销验证

### 2026-07-20 v0.7.8 笔记

- 保留现有版本`0.7.8`和构建`2026071908`；没有竞争分支
或版本已创建。
- 从 `TadaWordsFeatures` 中删除了所有请求功能。儿童Read可以
仅检查现有授权并显示适合年龄的“询问家长”状态，而不将权限失败视为学习尝试。
- 添加Parents → 应用程序和系列 → 具有独立语音功能的语音和麦克风
识别和麦克风状态、显式设置、已授权的兼容性以及针对拒绝、限制或撤销访问的 iOS 设置指南。
- 将语音设置保留为第二个成人拥有的权限入口点。苹果
控制器仅请求每个尚未确定的权限，并且从不重新请求拒绝或限制状态。
- 添加了`Docs/SYSTEM_PERMISSION_INVENTORY_v0.7.8.md`，枚举语音，
麦克风、相机、照片、通知、设备所有者身份验证和无提示 APN/CloudKit 服务所有权。
- 源/单元/文档门不声明模拟器、签名设备或
人类的接受。这些仍然是#55/#22 下的连续发布证据。
- 预提交存储库门通过了 1,016 Swift 测试、40 Issue 代理测试、
集成 v0.7.7 生产 APNs 门后进行 16 次发布预检测试。准确的已提交-HEAD验证在实施提交后单独记录。
## v0.7.9 — 2026-07-19

目标发布：`v0.7.9`

Branch: `codex/apns-registration-observability-v0.7.9`

Build: `2026071909`

总体状态：源实现和存储库门已完成，可实现 #64 跟踪的隐私安全 APNs 注册可观察性。精确签名的iPhone/iPad注册证据和真实背景收敛在#60和#62下仍然是分开的。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V079-SYNC-001 | P0 可观察性 | Family Sync 推送注册 | 区分未请求、待处理、已注册和失败的 APN 注册，无需保留或导出不透明设备令牌。 | 来源完整；实时验收开放|1042/1042Swift、40/40Issue代理和16/16发布预检测试通过了组合源候选。仍然需要：#60 下精确签名的 iPhone 和 iPad 回调； #62 下的真实背景收敛。 |

### 2026-07-19 v0.7.9 笔记

- 为回收的#64批次保留版本`0.7.9`和构建`2026071909`。
- 添加了 UIKit 成功和失败委托回调。成功回调
没有本地令牌标识符，并且没有设备令牌字节进入域、父 UI、诊断、日志、持久性、散列或导出路径。
- 每个活动仅保留一个进程本地状态值和一个未读流值
观察者。重新启动从未请求开始，重试返回到待处理状态。
- 将 Apple 故障映射到配置、连接或系统类别
无需导出原始域、代码、描述、设备标识、Apple Account 详细信息、Profile 内容或子数据。
- 添加了家长可见的注册状态和 schema-2 系列同步诊断
具有粗略状态、可选类别和更新时间戳。
- 选择退出后的延迟回调无法替代未请求状态。登记
失败永远不会阻碍本地实践或声称CloudKit收敛失败。
- 通知呈现授权不作为沉默的证据
CloudKit推送注册。
- 语音/麦克风和 APN 集成焦点的组合超过 110/110。
完整的组合源门通过了 1,042 项 Swift 测试、40 项 Issue 代理测试和 16 项发布预检测试。

## v0.7.10 — 2026-07-19

目标发布：`v0.7.10`

Branch: `codex/second-device-profile-adoption-v0.7.10`

Build: `2026071910`

总体状态：问题 #66 源实现和确定性独立 - UUID 覆盖范围已完成。精确签署的iPhone加上干净的iPad生产-CloudKit接受仍然是后来的#62收敛门的一部分；该批次不会安装设备、改变 Apple 门户或合并自身。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V0710-SYNC-001 | P0 bug | 第二个设备加入 | 让家长在提交任何随机本地Profile之前发现并收养现有的同步孩子Profile。保留精确的UUID和同步字段；切勿根据昵称、年龄、头像、照片或相似性进行合并。 | 来源完整；签署的生产验收开放|独立-UUID单元/集成和模拟器UI覆盖，完整的存储库门，然后精确-HEAD一-iPhone加上清洁-iPadCloudKit根据#62|验收

### 2026-07-19 v0.7.10 笔记

- 为回收的#66批次保留版本`0.7.10`和构建`2026071910`，
独立保留的下部释放插槽保持不变。
- 添加了显式传输引导策略。生产CloudKit现已离开
一个真正新鲜的Profile存储库是空的，直到父母选择寻找现有的孩子或明确创建一个单独的新孩子；仅设备安装保留其本地种子行为。
- 添加了家长拥有的首次运行选择、隐私确认、可重试iCloud
发现，为一个或多个孩子进行精确的Profile选择，以及明确的离线新孩子路线。
- 采用仅保留确切选定的 Profile UUID 作为该设备的最后一个
选择并完成入职，无需重写Profile。声纹注册仍然是设备本地的。
- 发现意图在采用前退出或重新启动时是持久的，因此
已经下载的远程Profile永远不会成为可编辑的本地新手种子。完成精确采用或显式创建可以明确该意图； schema-v1 载入状态在 v2 策略下仍然可读。
- 显式创建在之前持久保留一个确切的待定 Profile UUID
设置、Profile、子会话或完成标记写入。中断后重试会重用该UUID，因此它无法覆盖已发现的远程Profile或创建第二个本地Profile。重点测试在每个写入边界处中断和恢复。
- 发现重试或重新启动会继续已启用的家庭同步
与`synchronize()`会话而不是重新启用它，保留生产CKSyncEngine光标和收件箱状态。模拟器装置使用独立的持久光标标记来跟踪确认，而不是从本地Profile存在来推断它。
- 帐户确认期间暂时 iCloud 不可用表示为
离线重试状态；丢失或受限的 iCloud 帐户仍然处于明显的不可用状态。这两条路径都隐式创建了Profile。
- 相同昵称的个人资料保持独立。没有昵称、年龄、头像、照片或
采用路径中存在模糊身份规则。
- 新的Profile创建在之前保留了隔离的默认实践设置
如果 Profile 持久性失败，Profile 将变得可见并回滚这些设置。
- 添加了针对干净引导/重新启动、一个和多个的确定性测试
远程配置文件、相同的昵称、延迟连接、无iCloud帐户、显式离线创建、精确选择以及与捆绑模拟器种子不同的独立模拟器UUID。
- 完整的预提交门通过了严格的格式、1012/1012Swift测试，
40/40 Issue 代理测试和 11/11 发布预检测试。
- 两个聚焦的独立UUID第二设备 XCUITests 在两个方面都通过了 2/2
iPhone 17 Pro 和 iPad Pro 11 英寸 (M5) 模拟器：无需本地种子的精确采用，以及发现和采用之间的退出/重新启动，无需本地种子的重复。
- 通用iOS模拟器应用程序构建也成功。这是源码和模拟器
仅证据；它不能替代精确签署的生产版本和#62 中保留的一-iPhone 加上清洁-iPad CloudKit 验收。

### 2026-07-20 v0.7.10可靠性后续

- CloudKit回调，其元数据、收件箱、隔离区或传出系统-
字段写入失败现在会留下一代范围的恢复围栏。下一次提取或直接发送将取消失败的引擎，并在同一进程中重新加载最后一个持久的私有/共享游标，因此重试不再需要强制退出。来自被丢弃一代的后期回调仍然被忽略。
- 不可变的冲突处置现在不受 200 项诊断上限的影响。
直接隔离、收据隔离和原子冲突转换共享一个失败关闭的 upsert 规则，因此稍后的兼容性回调在重新启动后无法解锁可见冲突或压缩冲突。
- 采用和显式创建在提交之前请阅读最终的Profile列表
入职完成标记。因此，失败的最终读取使流程保持可重试，并重复使用确切的保留ProfileUUID，而不是留下没有可用结果的已完成标记。
- 前台iCloud-帐户重新验证现在会使正在进行的查找失效
在最终存储库和表示边界处。从帐户 A 获取的结果将转换回持久重置状态，选择退出 Family Sync，并且只有新的父级重试才可能会暴露帐户 B 候选者。
- 添加了确定性帐户切换竞赛测试，该测试会暂停帐户后查找
A 已填充规范存储库，完成对帐户 B 的前台重新验证，并证明过时的结果在干净重试仅返回帐户 B 的确切 Profile UUID 之前被拒绝。
- 添加了红到绿的覆盖范围，用于通用耐久性恢复、可见和
压缩冲突锁降级尝试，以及采用和创建中的最终读取失败。确切的工作树门通过了严格的格式化、1037/1037 Swift 测试、40/40 Issue 代理测试和 11/11 发布预检测试。在此后续提交之后，仍然需要新的精确HEAD签名的模拟器证据。
- App Store 后续行动仍然明确：#78 拥有版本化迁移
新的紧凑冲突语义，#79 拥有并发公共传输恢复序列化，#80 拥有有界故障关闭冲突索引。这些是 P1 释放门，不会扩展正常的单协调器iPhone-加-iPad P0 家庭游戏路径。

## v0.7.11 — 2026-07-20

目标发布：`v0.7.11`

Branch: `codex/auto-merge-exact-head-v0.7.11`

Build: `2026072011`

总体状态：Issue#85 更改交付政策和Issue代理合同；应用程序运行时逻辑和持久模式保持不变。 PR #72 被合并，并且该批次直接重新基于生成的 `main`。由于所需的发布增量会更改应用程序/LocalQA版本/构建元数据和生成的Xcode项目，因此精确HEAD模拟器和签名的LocalQAiPhone/iPad门仍然适用。 Apple Portal 状态、签名资产、CloudKit 和子数据仍然超出范围。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V0711-DELIVERY-001 | P1 自动化 | 交付 | 用常设的精确HEAD授权替换强制所有者`/merge`注释，同时保留所有证据、拦截器、高风险和合并后门。保留`/merge`可选，并提供经过验证的回滚到之前的评论政策。 | 保护合并强化正在进行中；打包工件验证待定|每PR基本OID加上规范保护/关闭引用摘要，严格的服务器强制精确头状态，存储库范围的合并租用，fsync支持的待定意图恢复，不确定请求后不重发，Issue代理聚焦/全面测试，存储库检查，精确HEADiPhone/iPad模拟器构建，并签名LocalQAiPhone/M4iPad身份/安装/启动证据|

### 2026-07-20 v0.7.11 笔记

- 为回收的 Issue #85 保留版本 `0.7.11` 和构建 `2026072011`
交付政策批次。
- 一个现成的、非草稿的、畅通无阻的代理PR现在会产生确定性的自动
合并由其完整HEAD、每PR基本OID、PR主体SHA-256、分页规范结束引用摘要和经过验证的分支保护摘要键入的候选者，而不需要GitHub注释；堆叠/非 `main` PR 被排除在外。
- 新的提交会产生新的候选者并使之前的检查、工件、
设备证据、评论和准备情况。
- 基础更改、PR-正文编辑或规范的结束引用更改
在同一次提交中使候选者无效。工作人员对 GitHub 的侧边栏感知 GraphQL 连接进行分页，拒绝跨存储库关闭，并保持仅 `Refs` 的 PR 有效。
- 可选的所有者`/merge <sha>`命令仍然受支持并受
相同的当前-HEAD预检。
- 合并突变集中在受保护的核心命令中。需要严格的
服务器端最新保护和确切的头状态，获取单写入器元数据边界的存储库范围的远程租约，保留 fsync 支持的准备和发送或未知状态，禁止管理/更新/变基绕过，并发送完整的 HEAD 作为 GitHub 的合并比较和交换值。不确定的请求仅用于协调，并且永远不会重新发送。
- 合并后的持久确认现在需要经过精确测试的HEAD，a
合并提交可从新的`origin/main`到达，预期的基础作为其第一个父级，相同的合并树，以及通过该PR链接的每个规范链接的Issue的关闭。挂起的意图在进程死亡后仍然存在，而不会静默容量截断，并且即使当 PR 不再由 open-PR 列表返回时也会重播。
- 规范关闭引用读取拒绝 GraphQL 部分错误、格式错误
节点和畸形分页。持久确认在释放确切的唯一远程租约之前会同步未完成的租约清理记录；下一次轮询将恢复崩溃后存储库检查之前未完成的清理工作。
- GitHub 没有针对 PR 元数据的比较和交换。自动作家必须尊重
合并关键租约；所有者在短关键部分期间的编辑是记录的可信操作员边界，而不是原子GitHub保证。
- 破坏性数据工作、不可逆转的提供商/帐户突变、凭证、
身份验证、模糊的产品选择和不匹配的目标环境仍然是明确的人为大门。
- 回滚会恢复此策略批次并重新安装经过验证的Issue代理；
日志、状态、worktree（工作树）、分支、标签和审计证据均保留。
- 应用程序行为不变，但版本/构建和生成的包
元数据改变构建的工件。精确的HEAD模拟器验证和签名的LocalQAiPhone和iPad证据正在序列化设备通道中等待。

## v0.7.12 — 2026-07-20

目标发布：`v0.7.12`

Branch: `codex/pawgoo-formal-identity-v0.7.12`

Build: `2026072012`

总体状态：Issue#68 仅将正常的调试/发布身份移至PawGooLLC 团队。 CloudKit 容器和每个持久的 Family Sync 标识符保持不变。 LocalQA 保留其现有的捆绑包、团队灵活性、空权利、已安装的数据和物理设备工作流程。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V0712-IDENTITY-001 | P0 发布身份 | 发布/持久 | 将 `app.tadawords.app` 和 PawGoo `7R78Q4HP86` 用于普通应用程序，而不派生或替换 LocalQA 身份。 | 保留分支上的实施正在进行中 | 静态身份合约、生成的构建设置矩阵、重点验证者测试、完整存储库门、精确HEAD iPhone/iPad 模拟器证据和精确PawGoo 开发签名工件验证 |

### 2026-07-20 v0.7.12 笔记

- 为回收的 P0 Issue #68 保留版本 `0.7.12` 和构建 `2026072012`。
- 普通应用程序调试/发布使用捆绑包`app.tadawords.app`；正常的 UI 测试
目标使用`app.tadawords.app.uitests`。两者都固定到PawGoo团队`7R78Q4HP86`。
- LocalQA 仍为`com.tadawords.app.localqa`； LocalQA UI 测试仍然存在
`com.tadawords.app.uitests`；设备测试仍为`com.tadawords.app.devicetests`。这些配置不会继承 PawGoo 团队或 APNs 设置。
- 普通应用程序保留 APN 和唯一的 CloudKit 容器
`iCloud.com.tadawords.app`，同时删除未使用的 KVS 源权利。 CloudKit 区域/根/订阅标识符和设备本地声纹服务未更改。
- 新的普通包创建一个新的本地沙箱、权限状态和
默认钥匙串组。本批次不安装； #60 拥有旧的普通库存和第一个普通应用程序安装。 LocalQA 数据未受影响。
- 预提交源门通过 1,119/1,119 Swift 测试，91/91 Issue 代理
测试和 54/54 发布/身份验证器测试。开发验证程序现在绑定 Apple CMS 信任和签名者固定、PawGoo 代码签名叶、配置文件授权信封、精确批准的设备覆盖范围、仅限 iPhoneOS 的 arm64 元数据以及稳定的应用程序树摘要。确切的承诺 - HEAD模拟器和签名的工件证据仍有待确定。

## v0.7.17 — 2026-07-21

目标发布：`v0.7.17`

Branch: `codex/family-sync-status-refresh-v0.7.17`

Build: `2026072117`

总体状态：Issue#101 修复了物理设备 Family Sync 状态竞争。 CloudKit 已在两台批准的设备上聚合，但父 UI 在现有协调期间打开时保留了临时的 `.syncing` 快照。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V0717-BUG-001 | P0 bug | 家长/家庭同步 | 在进行中协调期间到达的读者必须接收其最终的家长可见状态，而不是短暂的 `.syncing` 快照。 |源传递|协调器并发回归，完整源套件，精确HEAD构建，然后一个物理iPhone加一个物理iPad，无需重新安装或重置数据|

### 2026-07-21 v0.7.17 笔记

- 为回收的 Issue #101 保留版本 `0.7.17` 和构建 `2026072117`。
- 现在，参与者将并发状态和同步调用者排队，同时
协调处于活动状态，然后在每个所需的立即传递完成后以相同的已结算状态恢复所有这些。
- 不会进行轮询、配置文件更改、首选项更改、卸载或数据重置
参与修复。
- 修复前的物理证据显示，两台设备均已确认存在问题
278 个本地清单，零发件箱和待处理记录，空闲持久状态，并且在两个屏幕仍显示“正在同步...”时没有错误。
- 重点并发测试和完整的 1129 测试Swift套件通过。
Exact-HEAD 构建和签名设备验收仍在等待中。

## v0.7.32 — 2026-07-24

目标发布：`v0.7.32`

Branch: `codex/privacy-support-alignment-v0.7.32`

Build: `2026072406`

总体状态：Issue #76 采用所有者批准的保守 App Store 1.0 fallback：移除所有生产
voiceprint 注册和说话人匹配入口，仅为休眠的预发布 Keychain 模板保留既有的
Profile 删除与已验证首次安装清理路径。

| ID | 类型 | 区域 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V0732-PRIVACY-001 | P0 发布范围 | Voiceprint/COPPA | 在没有合格书面处理前，不得在 App Store 1.0 发布 voiceprint 注册或说话人匹配；保留任何休眠预发布模板的删除能力。 | 自动通过；exact-artifact 验收待定 | 源契约、完整回归门、exact-HEAD iPhone 和 iPad 模拟器 UI 检查、保留数据的签名实体 iPhone 验收，以及保留的生命周期清理测试 |

### 2026-07-24 v0.7.32 说明

- 生产组合不再构造注册 service，也不会向 Read Practice 注入说话人验证器。
- 当发布策略禁用时，Parent Profile 卡片不暴露 voice 设置；如果遗留代码尝试
  导航或开始注册，view-model guard 会 fail closed。
- 麦克风权限文案现在只覆盖 spoken Read Practice。
- 更新期间不会静默擦除现有模板。生产 repository 仍保持组合，只为使 Profile 删除
  与已验证首次安装 bootstrap 能执行此前验证过的限定范围清理。
- 这是发布范围 fallback，而不是法律结论。Issue #76 仍待针对瞬态 Read 语音、
  Profile/photo 数据、持久标识符和可选 CloudKit Family Sync 的合格处理。

## v0.7.30 — 2026-07-23

目标发布：`v0.7.30`

Branch: `codex/voiceprint-lifecycle-proof-v0.7.30`

### Voiceprint Keychain 生命周期验证

- 新增签名真机测试，通过 Apple Security framework 验证生产
  `KeychainDeviceVoiceprintRepository`。
- 测试使用 UUID 限定范围的测试 service，而不是生产 voiceprint
  service；无需卸载 App 或重置 App 数据。
- 覆盖证明：保留项在 repository 重建后继续存在，直到限定范围的
  fresh-install reset 执行；该 reset 会删除目标 service 中的全部项目，
  同时保留相邻 service。
- 覆盖还验证 `WhenUnlockedThisDeviceOnly`、不同步属性，以及空 service
  reset 的幂等性。
- 新增持久生命周期记录，并同步内部隐私和提交包文案。与之匹配的
  Pawgoo Privacy/Support 文案部署仍归 #54。

## v0.7.27 — 2026-07-21

目标发布：`v0.7.27`

Branch: `codex/appstore-decisions-v0.7.27`

总体状态：App Store 1.0 分发约定已明确，并在发布决策记录、提交包、
隐私计划、审查说明和 exact-RC 检查表之间保持一致。

| ID | 类型 | 区域 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V0722-RELEASE-001 | P1 决策 | App Store | 使用 Made for Kids 6–8、免费且无 IAP 或广告、仅美国上架，并在所有地区手动发布。 | 所有者已批准；源契约已实现 | 精确源测试、生成项目身份、PR 合并，以及稍后由 #65 针对已验收 RC 填写 App Store Connect。 |

### 2026-07-21 v0.7.27 说明

- 所有者明确选择 Made for Kids，并以 6–8 岁为主要年龄段；批准后的
  锁定被记录为不可逆。
- 首个公开版本免费，不含 IAP、订阅、广告或付费解锁，仅在美国提供，
  且不启用预购。
- 获批的发布方式为手动发布。App Review 批准后，版本必须保持
  Pending Developer Release，直到 #26 授权最终发布。
- 即使 1.0 不包含欧盟 storefront，账户级 EU DSA trader 声明仍属于
  #23 范围。
- 本文档与发布身份批次不会填写 App Store Connect 值、提交构建，
  也不会改变运行时或数据行为。

## v0.7.19 — 2026-07-21

目标发布：`v0.7.19`

Branch: `codex/profile-chooser-grid-v0.7.19`

总体状态：紧凑的iPhoneProfile选择器使用有界垂直网格而不是无界水平条带。第一行最多包含三个现有配置文件加上`New Kid`；后面的每一行最多包含三个配置文件，并且保留在景观安全区域内。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V0719-UI-001 | P1 bug | Kid/Profile 选择器 | 将三个以上配置文件保留在 iPhone 横向边界内，同时将 `New Kid` 保留在第一行中。 | 自动通过 | 0 到 20 个配置文件的布局策略覆盖范围、重点 Swift 测试以及使用四个配置文件的精确iPhone 横向视觉/点击验证。 |

### 2026-07-21 v0.7.19 笔记

- 紧凑型卡使用适合三个配置文件加上`New Kid`的有限宽度
在现有的 760 点内容范围内。
- 第四个现有的 Profile 开始垂直可滚动的第二行；
后续行绝不会包含超过三个配置文件。
- 每个紧凑行共享相同的前缘，因此部分溢出行不会
不会漂移到iPhone屏幕的中心。
- 标准高度和iPad布局保留其现有的自适应网格。

## v0.7.18 — 2026-07-21

目标发布：`v0.7.18`

Branch: `codex/family-sync-background-and-default-consent-v0.7.18`

总体状态：Family Sync 现在在启动后只要家长打开它就会注册远程通知。在支持 iCloud 的设备上首次运行的家长会看到家庭同步默认处于启用状态，可以在创建配置文件之前将其关闭，并且在使用 iCloud 配置文件发现之前必须明确将其保持打开状态。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V0718-SYNC-001 | P0 bug | 家长/家庭同步 | 在 Parents 中启用家庭同步必须立即注册 APN，而不是等待重新启动；然后，后台设备可能会收到CloudKit更改唤醒。 | 自动通行证；观察到已签名的 iPhone 到 iPad 传播 | 在正常的 `app.tadawords.app` 构建中，iPhone 创建 `Push Pebble 0721` 收敛到未受影响的 iPad，无需打开 Family Sync；两个设备快照均包含一个匹配的Profile，总共四个配置文件。 |
| V0718-ONBOARDING-001 | P1 改进 | 首次运行家长协议 | 将 Family Sync 作为支持 iCloud 的默认设置，并在任何新的 Profile 排队之前以简单语言披露并在屏幕上选择退出。 | 自动通行证；干净设备物理验收待定|全新安装父路径：验证默认打开、显式关闭、新Profile创建以及选择退出时禁用“查找我的孩子”。在此测试中，故意不卸载或重置现有的家庭数据设备。 |

### 2026-07-21 v0.7.18 笔记

- 现在在Parents中打开或关闭家庭同步分别请求或
在同一会话中取消注册远程通知传送。
- 首次运行协议默认启用 iCloud-capable 选项；它是
完成会在创建 Profile 之前写入所选的首选项，因此选择退出永远不会将第一个突变排入 Family Sync 的队列。
- “查找我的孩子”仍然是仅限 iCloud 的操作，并且在以下情况下不可用：
家长明确选择退出；创建本地Profile仍然可用。
- 重点关注首次运行、通知注册、家长演示以及
完成 233 项测试 Family Sync 回归套件的通过。已签名的 v0.7.18 应用程序工件现已安装在批准的 iPhone 和 iPad 上；设备数据容器均未重置、替换或卸载。
- 在正常的PawGoo应用程序中，在生成的iPhone上创建`Push Pebble 0721`
在未访问的 iPad 上添加一个匹配的 Profile，无需访问 Family Sync。 Read-仅设备容器快照显示每个设备上的四个配置文件以及每侧都有一个具有该显示名称的记录。

## v0.7.13 — 2026-07-20

目标发布：`v0.7.13`

Branch: `codex/quest-session-regressions-v0.7.13`

Build: `2026072013`

总体状态：Issue#91、#92 和#93 修复三个日常练习回归，而不删除或替换儿童学习历史。源回归测试通过；精确HEAD模拟器和物理设备验收仍然是分开的。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V0713-BUG-001 | P1 bug | Kid UI | 适合 Spell 镶边、提示符、插槽和完整键盘在受限高度景观中 iPhone，同时保留 44 点控件和常规 iPad 比例。 |自动通过|布局策略测试加上精确HEAD景观iPhone和iPad模拟器捕获；物理分接待处理|
| V0713-BUG-002 | P1 错误 | Write 会话 | 完成的手写项目后的显式拼写选择必须覆盖过时的恢复的输入模式证据，同时保留完整的前缀。 | 自动传递| 模型回归，涵盖手写完成、退出、显式拼写选择和第二项恢复；模拟器流程待定|
| V0713-BUG-003 | P1 bug | 父级/持久性 | 提高新上限或审核上限必须单调地将符合条件的单词附加到今天的规范计划中，而不更改其 ID、完成度、奖励或尝试历史记录。重复刷新是幂等的，并且较低的大写字母永远不会删除历史记录。 | 自动通过 | 两种限制的本地 JSON 完成/扩展/重新启动测试以及待处理的父子模拟器流程 |

### 2026-07-20 v0.7.13 笔记

- 为回收的 Issue #91 保留版本 `0.7.13` 和构建 `2026072013`，
＃92和＃93。
- Spell 使用低于 560 点的受限高度指标：chrome、prompt、
响应槽、键盘间距和提交控件紧凑在一起；每个交互式控件至少保留 44 个点，并且常规高度 iPad 值保持不变。
- Write 选择器现在将其选择标记为显式。坚持尝试
上下文对于通用崩溃/重新启动恢复仍然具有权威，但不能覆盖新的子选择。
- 每日计划协调是一个序列化、单调的存储库突变。
它保留稳定的计划 ID，并仅附加上限允许的增量。现有的完成和奖励参考保持不变；降低上限和重复核对是不行的。
- 重点模型、内容存储库和布局套件通过。完整源码，
自动化、模拟器和签名设备门分别记录。

## v0.7.21 — 2026-07-21

目标发布：`v0.7.21`

Branch: `codex/atomic-profile-visibility-v0.7.21`

Build: `2026072121`

总体状态：已接受的远程 Family Sync Profile 批次在每个规范存储库和复合 UI 阅读器中都可见为一个已提交的生成。中断的应用会保留准确接受的重播负载，并在不发布部分子项、父项或通知快照的情况下关闭失败。

| ID | 类型 | 面积 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V0721-SYNC-001 | P0 bug | 系列同步/应用 | 防止任何接受的跨存储库 Profile 代出现半新半旧的情况；保留精确的重播和删除最终性。 |自动传递|每次应用边界后的失败注入、精确的接收/重放断言、完整的源门、精确的HEAD模拟器家庭同步矩阵，以及签名的iPhone加iPad烟雾而不删除应用程序数据。 |

### 2026-07-21 v0.7.21 笔记

- 一个全流程的承诺生成门现在序列化已接受的Profile
适用于规范存储库读取以及复合子项、父项和通知快照。
- 部分接受的申请标志着受影响的Profile需要恢复。民众
读取失败关闭，直到持久事务重播其确切字节；协调员协调在指纹或获胜者计算之前执行重播。
- 应用收据在中断期间保持缺席，在完整后出现一次
提交，并且在无操作恢复过程中不要更改。
- 通过逻辑删除、本地数据擦除和远程Profile删除重放
持久提交，不允许陈旧的Profile数据重新出现。
- 该版本保留了现有的PawGoo捆绑标识、CloudKit容器、
和就地数据合同。模拟器和签名设备证据仍然准确-HEAD，并与源测试分开记录。

## v0.7.28 — 2026-07-24

目标发布：`v0.7.28`

Branch: `codex/camera-ocr-editor-v0.7.15`

Build: `2026072402`

总体状态：Issue #96 在相机拍摄与 OCR 审查之间增加设备端裁剪与遮罩
编辑器，同时保留 v0.7.21 的原子 Family Sync 可见性和所有现有的
家长批准词池规则。

| ID | 类型 | 区域 | 后续要求 | 当前状态 | 所需验收证据 |
|---|---|---|---|---|---|
| V0720-UX-001 | P1 改进 | Parent/相机 OCR | 允许家长在 OCR 前裁剪拍摄的词表并遮盖无关内容，支持撤销、重置、重拍、取消和明确的 Use Photo 交接。 | 自动通过 | 编辑器模型/渲染测试、exact-HEAD iPhone 与 iPad 模拟器流程、签名 LocalQA 身份验证，以及保留数据的实体 iPhone 相机到 OCR 审查流程 |

### 2026-07-24 v0.7.28 说明

- 编辑器会规范化图像方向、保留源分辨率，并且只在所选裁剪范围内、
  OCR 之前应用黑色遮罩。
- 相机图像和编辑后的图像仅保留在设备上且不会持久化。取消不会改变
  词池；OCR 结果仍需家长审查并明确添加。
- Crop 和 Mask 在编辑器黑色背景上处于非活动状态时使用白色文字；
  活动工具保留白色分段与黑色文字。
- 所有者仅为本次合并豁免实体 iPad 与 Apple Pencil 通道；iPad 模拟器
  覆盖仍为必需。一个实体 iPhone 相机流程仍是强制发布门槛。
