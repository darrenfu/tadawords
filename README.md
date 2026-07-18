<p align="center">
  <img src="Apps/TadaWordsApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="112" alt="Tada Words app icon">
</p>

<h1 align="center">Tada Words</h1>

<p align="center"><strong>Short, playful sight-word practice for early readers on iPhone and iPad.</strong></p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/iOS-18%2B-111111?logo=apple" alt="iOS 18 or later">
  <img src="https://img.shields.io/badge/UI-SwiftUI-0D96F6?logo=swift&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/status-v0.6.2%20agent%20PR-6D48D7" alt="v0.6.2 agent PR">
</p>

Tada Words gives children two separate daily quests for sight words:

- **Read:** See a word and say it aloud.
- **Write:** Hear a word, then either write it by hand or spell it with the
  app's theme-matched A–Z keyboard.

Parents add every practice word by typing, scanning a school list with optical character recognition (OCR), or selecting words from an offline preset. Tada Words never fills a Pool automatically. The review scheduler brings parent-approved words back based on recall strength, errors, help use, replays, and each child's response pace.

> **Project status:** The `agent/batch-import-v0.6.2` branch packages version `0.6.2` (build `2026071702`). It carries forward the human-controlled release loop and v0.6.0 visual-first Kid UI, bundles all 74 catalogued Twemoji picture hints for deterministic offline loading, and removes the shipping runtime CDN request. Missing, corrupt, and unexpectedly large picture assets fail closed without blocking practice. Full VoiceOver meaning and recovery copy remain intact; physical child/Parent acceptance remains open. See the [Kid copy matrix](Docs/KID_UI_COPY_MATRIX_v0.6.0.md), [follow-up log](FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md), [acceptance checklist](MVP_ACCEPTANCE.md), and [cross-device sync ADR](Docs/ADR-0001-CROSS-DEVICE-FAMILY-SYNC.md).

The app ships eight separate visual worlds: Moonpetal Kingdom, Build-It Bay,
Paws & Pines, Dino Discovery, Firehouse Heroes, Brickwork City, Frostlight
World, and Coaster Carnival. Each world keeps its own original scene, mascot,
music, sound cues, and 25-item reward collection.

## Learning model

| Route | Prompt | Child response | Evidence |
|---|---|---|---|
| Read Quest | The app shows a sight word | The child says the word | On-device speech recognition plus optional device voiceprint confidence |
| Write Quest | The app speaks a sight word | The child chooses handwriting or the in-app A–Z spelling keyboard | Vision handwriting recognition or exact case-insensitive typed spelling; both complete the same Write Quest while pace stays separate |
| Review | The scheduler selects due and weak words | The child retrieves the word again | Accuracy, elapsed time, help, replay, and retry history |

Read never speaks the target before the child's first independent response. After two valid wrong readings it reveals only child-triggered **Hear it**; technical retries never reveal help early. Covered words use the bundled Katie Read-hint recording, while other guardian-entered words use Apple speech. Each World owns one coordinated, high-contrast word color, so every Read word stays visually consistent until the child changes Worlds.

Write plays the bundled Katie isolated-word recording at 0.67× for the first 500 covered words and never pre-shows the spelling. The separate Read-hint version uses the same one-and-a-half-times-slower cadence. Both variants retain 120 ms of encoding-safe tail padding so final consonants such as the `/t/` in `at` finish before playback completes. Apple speech is the offline fallback for words outside the pack and keeps a neutral pitch plus enough release time to preserve final consonants. The child first chooses **Write by Hand** or **Spell with Letters**; either choice completes the same Daily Write Quest and shares its Pool, mastery, review schedule, score, and reward. Typed pace is recorded in a separate input-method band so fast key taps never make handwriting look slow. The spelling surface is a fixed-position, theme-colored QWERTY A–Z keyboard built in SwiftUI, so the system keyboard, predictive text, numbers, and symbols never appear. Comparison ignores capitalization, while apostrophes and hyphens are supplied as structural parts of the prompt. Focused Replay keeps the selected input method.

For handwriting, the `?` control reveals the word on demand. After the first genuine mismatch, a concrete word such as `dog` can show a tappable picture hint from the bundled Twemoji pack, including on a fresh offline install; abstract and function words such as `the` receive no image. Children can choose Pencil, Chalk, or Brush; ink is always black and the selected tool persists per Profile. The 4× local eraser restores the prior pen after a blank-canvas tap. The canvas is 10% wider, keeps fixed coordinates during feedback and word transitions, and preserves dots, later letters, and connected strokes. Most words retain two lazy Vision raster passes and five candidates per observation. The visually ambiguous target `of` alone gathers three scales and up to 10 candidates before deciding: a lower-ranked exact spelling needs agreement across two scales, while any strong complete `off` spelling vetoes a match. Mixed-case `oF`, connected lowercase `of`, and six child-like shape variations receive this exact, target-specific recovery. A numeric `0` may stand for `o` only when its aligned target position is exactly `o`, so `0f` and `0F` are accepted while `00`, `90`, `0t`, `0ff`, `+0`, and `f0` remain rejected. Technical speech or recognition failures do not reduce the child's score.

Child-facing stars reward completion, accurate retrieval, and a comfortable personal pace. One immediate unaided recovery can still earn the Accuracy Star, calibration can earn Pace, and the post-calibration slow side gets 50% grace. Guardian accuracy and mastery evidence stay strict.

### Scoring rules

| Result | Child-facing rule |
|---|---|
| Completion Star | Finish every planned word |
| Accuracy Star | Reach 75% strict first-independent accuracy, or miss one word and answer its immediate unaided retry correctly before seeing or hearing help |
| Personal Pace Star | Earn Accuracy and stay in the personal pace band, stay in calibration with valid timing, or complete a perfect first try |
| Points | Up to 80 accuracy points plus 20 pace points |
| Perfect first try | 100 points and all three stars, even before a pace baseline exists |

The one-recovery rule changes only the child's reward display. Parent reports keep the original first-independent accuracy. Replay appears only when the run contains missed or helped words, and it practices only those tricky words.

### Word pronunciation

Parents only enter the school word. Every newly added word uses the canonical isolated teacher pronunciation; there is no pronunciation-context editor or pronunciation picker. Older saved prompts that contain contextual audio metadata still decode for data compatibility, but Parents cannot create or edit that metadata.

The bundled audio pack contains 500 unique Pre-K–Grade 1 words, with separate Read and Write recordings at 0.67×. Katie is the canonical teacher; the manifest documents one quality override (`bun`) to Aurora after two independent speech recognizers rejected Katie's isolated rendering. Its 1,000 AAC clips plus eight Aurora resources add about 7.4 MB. Correct answers keep the selected World's immediate synthesized sparkle and rotate five short Aurora celebrations; neither those lines nor `Quest complete!` uses `Ta-da` as a transition interjection. Reduced Sound suppresses decorative spoken transitions.

The scheduler uses an Ebbinghaus-style recall model. A word reaches Mastered after independent success on three local dates and a predicted 14-day recall rate above the configured threshold.

### Parent-controlled word sources

Parents choose every word that enters a Read or Write Pool:

- **Typing:** Press Return after each word to add it to the selected Pool
- **Camera or photo OCR:** Review recognized words before adding them
- **Offline presets:** Review age- and grade-ranked suggestions or browse by topic, select individual words, choose Read, Write, or Both, then tap **Add**

Parents record an age from 3 through 8 when they create a Profile. Tada Words uses age and grade only to rank preset lists; it never adds words from them. The bundled catalog contains 34 leaf presets with 1,365 word references and 1,166 unique normalized words. Each leaf contains 30–50 words. See the [preset word catalog](Docs/TADA_WORDS_PRESET_CATALOG.md) for the hierarchy, complete lists, and source notes. The [catalog export script](Scripts/export_preset_catalog.py) generates the same Obsidian-ready Markdown from the App JSON.

Each Pool also has **Delete All**. Parents confirm the exact count and destination, then can restore the complete Pool with **Undo**. Delete confirmation and Undo state stay isolated to the initiating Profile, so switching children cannot expose or apply another child's operation.

Preset imports also stay bound to the initiating Profile. An import to **Both** completes for both Pools or compensates the current request. Compensation reverses only memberships inserted or reactivated by that request and never deactivates a word that was already active.

## V1 features

| Area | Included |
|---|---|
| Practice | Separate Read and Write pools, independent Today Quest buttons, Write-by-hand or theme A–Z spelling, New and Review ordering, timer, Rescue state, score, stars, and mastery |
| Word setup | One-word Return-to-add; multi-photo Camera/Photo OCR; 34 offline preset lists with explicit word selection; numbered review; 500 words per image; added-order, A-Z, and most-practiced sort; type-ahead search with Hear/Delete; de-duplication; session-scoped delete confirmation; bulk delete; per-Pool Delete All and Undo; no automatic additions |
| Profiles | Profile-first launch, multiple children, nickname entry, age capture from 3 through 8, last-profile highlight, animal/photo/collected-treasure avatar, earned icon, grade, and preferred world |
| Motivation | Eight original worlds, 20 small rewards and five milestones per world, 200 distinct treasure icons, Double-Quest next-day Theme/Icon unlocks, My Collection, and a monthly calendar |
| Guardian tools | Single-tap `Parents` → auto-checking math Parent Gate, World-themed Parent Home with a Profile card, Words & Practice, Progress, and App & Family entrances, Word Manager, reports, corrections, settings, CSV export, and Back-to-child navigation |
| Accessibility | Landscape child routes plus rotatable parent routes, shared 44-point minimum targets, VoiceOver labels and announcements, Reduce Motion, left-handed writing, Reduced Sound, and Calm Rescue; physical accessibility acceptance remains open |
| Platform | A 1.8s branded launch page with official Tada Words and Pawgoo marks, offline-first Katie teacher audio with an Apple Speech fallback, bundled Aurora launch/transitions, repeat-after-me Keychain voiceprints, target-informed Vision handwriting recognition, local notifications, local JSON snapshots, device-only LocalQA, and explicitly enabled CloudKit family sync |

## Architecture

The Swift package keeps learning policy separate from SwiftUI and Apple frameworks.

| Module | Responsibility |
|---|---|
| `TadaWordsDomain` | Entities, value objects, and service contracts |
| `TadaWordsLearning` | Planning, review, scoring, pace, and mastery rules |
| `TadaWordsContent` | Word import/OCR parsing, pools, persistence, scheduling, sync records, and rewards |
| `TadaWordsDesignSystem` | Shared child and Guardian components and visual tokens |
| `TadaWordsFeatures` | Profiles, lobby, Read, Write, results, worlds, and Collection |
| `TadaWordsGuardianFeatures` | Parent gate, setup, settings, reports, corrections, and sync controls |
| `TadaWordsApplePlatform` | Speech, Vision, audio, Keychain, notifications, and CloudKit adapters |
| `TadaWordsAppShell` | Production composition and local-first bootstrap |

The iOS target depends on `TadaWordsAppShell`, `TadaWordsApplePlatform`, and `TadaWordsDomain`. Package target declarations enforce the remaining boundaries. Read [ARCHITECTURE.md](ARCHITECTURE.md) for dependency rules and data flow.

## Requirements

- macOS with Xcode and an iOS 18 or later SDK
- Swift 6
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project regeneration
- A free Apple Account for direct LocalQA installation on personal devices
- A paid Apple Developer Program team for TestFlight and CloudKit acceptance

The current v0.6.0 automated run uses Xcode 26.6. The complete LocalQA phone/tablet simulator matrix passes; physical-device acceptance remains open.

## Build and test

```sh
git clone https://github.com/darrenfu/tadawords.git
cd tadawords

brew install xcodegen
make generate
make check
open TadaWords.xcodeproj
```

`make check` runs strict Swift formatting checks, the Swift package test suite, and the Issue Agent checks. The accepted V1 baseline contained **367 tests with zero failures**. Merged v0.2 contained **480 tests with zero failures**, merged v0.3 contained **548**, and the complete v0.3.1 baseline contains **595 tests with zero failures**. The v0.4.1 merged tree also passes **595 tests with zero failures**, including the v0.3.1 World-layout coverage and the updated audio contract. The v0.5 baseline passes **619 tests**, v0.5.1 passes **638**, and v0.6.0 passes **641 Swift tests plus 14 Issue Agent tests with zero failures**. The Xcode UI target covers Read/Write completion, repeated delete/Undo, Delete All/restore, explicit Preset approval, Photos-picker dismissal, OCR Review → Add All → Pool → Sort, and Lobby → Write → Spell. All nine critical flows pass on both the iPhone 17 Pro Max and iPad Pro 13-inch simulators. A separate physical-device target calls the public production handwriting service and does not use the demo recognizer.

Run the device-readiness script before installing on an iPhone or iPad:

```sh
./Scripts/verify-device-readiness.sh
```

Every physical Release Batch build also embeds its Git commit. Before installing
the signed LocalQA app, verify that the bundle matches the reserved version,
build, commit, and bundle ID:

```sh
./Scripts/verify-signed-app-identity.sh \
  '/path/to/Tada Words QA.app' \
  0.5.2 2026071505 "$(git rev-parse HEAD)" com.tadawords.app.localqa
```

The local [Issue Agent](Automation/issue-agent/README.md) polls ready GitHub
Issues every ten minutes, batches related module work, and stops for human
product, device, and merge gates.

Follow [DEVICE_DEPLOYMENT.md](DEVICE_DEPLOYMENT.md) for signing, Developer Mode, and direct installation.

## Data and privacy

- The app stores child profiles, word pools, quest history, and settings in local JSON snapshots.
- The app does not run an app-owned server database.
- Speech and enrollment audio buffers stay in memory. The app does not save or upload raw child recordings.
- Voice setup shuffles six short Pre-K sentences for the child to hear and repeat. Each device stores only the resulting voiceprint template in Keychain. CloudKit does not sync the template, so each device needs its own enrollment.
- Practice uses one canonical teacher-voice contract rather than a per-Profile style picker. A versioned offline pack covers 500 words with Katie as the canonical voice and one manifest-documented Aurora quality override for `bun`; other words use the clearest compatible American-English Apple voice already installed. Aurora launch and transition clips are also bundled. No Cartesia API key or runtime Cartesia request is present in the app.
- Pool import prefetches only the child-safe concrete-word picture catalog. All 74 unique Twemoji PNGs are bundled with the app, so a fresh offline install needs no CDN request. Abstract words have no picture mapping.
- Release builds keep iCloud Family Sync off by default. Completing onboarding does not enable it; a parent must explicitly turn it on in Guardian settings.
- Turning Family Sync off prevents later lifecycle, manual, and invitation sync calls. It does not yet erase records that were already uploaded.
- Profile deletion clears local learning data, reminders, and the local voiceprint. It uploads a tombstone that prevents profile resurrection, but it does not yet erase records already stored in CloudKit.

The voiceprint provides a confidence signal. It does not prove that only the selected child spoke. Production use needs representative same-child and different-speaker testing.

The `TadaWordsLocalQA` scheme installs a visibly separate **Tada Words QA** app with bundle ID `com.tadawords.app.localqa`. It has no iCloud entitlement, does not advertise CloudKit sharing, and keeps data only on that device. Its local data is separate from the release app and does not sync to another device.

Simulator builds also use the local-only transport. A normal signed physical-device Release build can use CloudKit only after the developer configures `iCloud.com.tadawords.app`, the device is signed in to iCloud, and a parent opts in. Remote CloudKit record erasure must be completed before release use with family data.

## Validation status

| Check | Result |
|---|---|
| Strict Swift format lint | Passed |
| Version and build | v0.6.2 (`2026071702`) in source Plists and generated project settings |
| Swift tests | v0.6.2: validation pending on this agent branch |
| Critical XCUITest flows | v0.6.2: validation pending on iPhone and iPad simulators |
| Parent Home | Back navigation, World theme, shared tactile components, and reduced copy passed targeted simulator verification |
| Launch page | 1.8s minimum, official Tada Words and Pawgoo marks, warm native launch color, audio-before-countdown sequencing, bundled spoken brand signature, and fade policy passed simulator tests; physical listening QA pending |
| `of` handwriting recovery | Three-scale evidence aggregation, 10-candidate inspection, mixed-case vocabulary, six child-like positive styles, target-aligned `0` → `o` normalization with a real Vision `0f` fixture, 30 paired neighbor controls, cross-scale corroboration, and the `off` veto passed automated tests; child handwriting pending |
| Physical iPhone production Vision | 2/2 device tests passed: 6/6 `of/go` case variants and 4/4 negative controls; synthetic vectors only |
| Physical iPad production Vision | 2/2 device tests passed: wrong-word rejection and `of/go` case variants; synthetic vectors only |
| Physical iPad critical XCUITest | 7/7 passed: OCR Add All, Delete All/restore, explicit Preset approval, sequential deletes/sort, Photos picker/sort, and Read/Write completion dismissal |
| iPhone 17 Pro Max LocalQA simulator | Fresh v0.5.1 build `2026071501`; critical XCUITest matrix 9/9 passed |
| iPad Pro 13-inch (M5) LocalQA simulator | Fresh v0.5.1 build `2026071501`; critical XCUITest matrix 9/9 passed |
| Connected iPhone 17 Pro Max | The unique v0.5.1 (`2026071504`) package is signed and ready, but the phone became unavailable before installation; reconnect it, then install/inventory-verify before child `of`/`0f`, audio, rotation, and accessibility acceptance |
| Darren's reading iPad Air 11-inch (M2), iPadOS 26.5.2 | Team `6S245NCUPQ` signed `Tada Words QA` v0.5.1 (`2026071504`) installed and inventory-verified; launch is waiting for device unlock, then child/Parent acceptance remains |
| Darren iPad Air 13-inch (M4), iPadOS 26.5 | Provisioning includes the device, but its paired Wi-Fi tunnel timed out before the corrected `2026071504` package could install; wake/unlock or reconnect it, then install and inventory-verify before acceptance |
| Pre-K visual hierarchy | v0.2 Profile, Lobby, Read, and Result captures pass on both simulators; physical child, VoiceOver, and Dynamic Type acceptance remain open |
| Route-based orientation | v0.2 Plist and runtime-policy checks passed. iPad simulator window shapes show Parents rotating while child routes remain landscape. Raw iPhone simulator framebuffer captures are inconclusive, so physical rotation remains open. |
| Persisted, default-off CloudKit guardian opt-in | Implemented; live-device acceptance open |
| CloudKit remote erasure | Implementation required |
| Physical child speech, handwriting, audio, accessibility, and CloudKit | Acceptance open |

The [feature audit](QAArtifacts/FULL_FEATURE_AUDIT_2026-07-12.md) records the merged v0.2 implementation evidence. The [follow-up log](FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md) records changes through v0.5.1, and the [V1 backlog](V1_BACKLOG.md) lists the remaining device and human acceptance work.

## Test fixture attribution

The repository includes one unmodified child-speech fixture from [OpenSLR SLR101, speechocean762](https://www.openslr.org/101/) under CC BY 4.0. Read its [source and license record](Tests/Fixtures/ChildSpeech/LICENSE_SOURCE.md) and [SHA-256 checksum](Tests/Fixtures/ChildSpeech/SHA256SUMS). The app does not bundle this test file.

## Documentation

- [Product and interaction design](TADA_WORDS_V1_PRODUCT_DESIGN.md)
- [Design review](TADA_WORDS_DESIGN_REVIEW.md)
- [Follow-up bug fixes and improvements](FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md)
- [V1 acceptance checklist](MVP_ACCEPTANCE.md)
- [Physical-device deployment](DEVICE_DEPLOYMENT.md)
- [Voiceprint Device Alpha plan](VOICEPRINT_DEVICE_ALPHA.md)
- [Preset word catalog](Docs/TADA_WORDS_PRESET_CATALOG.md)
- [Visual and accessibility audit](QAArtifacts/DESIGN_AUDIT_2026-07-12.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

## License

The project source does not include an open-source license. Copyright remains with the project owner. Third-party material retains the copyright and license stated in its [third-party notices](THIRD_PARTY_NOTICES.md) or attribution file.
