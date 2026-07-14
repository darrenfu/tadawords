<p align="center">
  <img src="Apps/TadaWordsApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="112" alt="Tada Words app icon">
</p>

<h1 align="center">Tada Words</h1>

<p align="center"><strong>Short, playful sight-word practice for early readers on iPhone and iPad.</strong></p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/iOS-18%2B-111111?logo=apple" alt="iOS 18 or later">
  <img src="https://img.shields.io/badge/UI-SwiftUI-0D96F6?logo=swift&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/status-v0.3%20device%20QA-6D48D7" alt="v0.3 device QA">
</p>

Tada Words gives children two separate daily quests for sight words:

- **Read:** See a word and say it aloud.
- **Write:** Hear a word and write the whole word by hand.

Parents add every practice word by typing it or scanning a school list with the camera or photo library. Tada Words schedules only those parent-provided words; V1 never grows a Pool from a grade catalog or smart fill. The review scheduler brings words back based on recall strength, errors, help use, replays, and each child's response pace.

> **Project status:** PR #1 merged v0.2 to `main` at `7728f28`. Branch `v0.3` contains the Parent/OCR, voice setup, Read scoring/replay, Write canvas, and recognition follow-ups described below. The v0.3 Swift suite passes **548/548** and the five critical XCUITest flows pass **5/5**. Fresh LocalQA simulator builds pass on iPhone 17 Pro Max and iPad Pro 13-inch (M5), and the signed candidate is installed on the connected iPhone 17 Pro Max. Child speech/handwriting, pronunciation listening, accessibility, iPad, and live CloudKit acceptance remain open. Family Sync is persisted, default-off, and requires explicit parent opt-in; CloudKit convergence and remote erasure remain release blockers. See the [follow-up log](FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md), [acceptance checklist](MVP_ACCEPTANCE.md), and [cross-device sync ADR](Docs/ADR-0001-CROSS-DEVICE-FAMILY-SYNC.md).

The app ships eight separate visual worlds: Moonpetal Kingdom, Build-It Bay,
Paws & Pines, Dino Discovery, Firehouse Heroes, Brickwork City, Frostlight
World, and Coaster Carnival. Each world keeps its own original scene, mascot,
music, sound cues, and 25-item reward collection.

## Learning model

| Route | Prompt | Child response | Evidence |
|---|---|---|---|
| Read Quest | The app shows a sight word | The child says the word | On-device speech recognition plus optional device voiceprint confidence |
| Write Quest | The app speaks a sight word | The child writes the complete word | Vision handwriting recognition from the drawing canvas |
| Review | The scheduler selects due and weak words | The child retrieves the word again | Accuracy, elapsed time, help, replay, and retry history |

Read never speaks the target before the child's first independent response. After two valid wrong readings it reveals only child-triggered **Hear it**; technical retries never reveal help early. Each World owns one coordinated, high-contrast word color, so every Read word stays visually consistent until the child changes Worlds.

Write prioritizes clear, fluent pronunciation rather than an extreme slowdown and never pre-shows the spelling. The offline fallback uses one uninterrupted utterance, a clarity-ranked American-English system voice, neutral pitch, and enough release time to preserve final consonants. The `?` control reveals the word on demand. After the first genuine mismatch, a concrete word such as `dog` can show a tappable picture hint; abstract and function words such as `the` receive no image. Children can choose Pencil, Chalk, or Brush; ink is always black and the selected tool persists per Profile. The 4× local eraser restores the prior pen after a blank-canvas tap. The canvas is 10% wider, keeps fixed coordinates during feedback and word transitions, and preserves dots, later letters, and connected strokes. Vision evaluates target-informed alternatives and ignores case, so forms such as `of`, `Of`, and `OF` share one exact-spelling decision without accepting neighboring words. Technical speech or recognition failures do not reduce the child's score.

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

The scheduler uses an Ebbinghaus-style recall model. A word reaches Mastered after independent success on three local dates and a predicted 14-day recall rate above the configured threshold.

## V1 features

| Area | Included |
|---|---|
| Practice | Separate Read and Write pools, independent Today Quest buttons, New and Review ordering, timer, Rescue state, score, stars, and mastery |
| Word setup | One-word Return-to-add; multi-photo Camera/Photo OCR; numbered review; 500 words per image; added-order, A-Z, and most-practiced sort; type-ahead search with Hear/Delete; de-duplication; session-scoped delete confirmation; bulk delete and Undo; no automatic additions |
| Profiles | Profile-first launch, multiple children, nickname entry, last-profile highlight, animal/photo/collected-treasure avatar, earned icon, grade, age, and preferred world |
| Motivation | Eight original worlds, 20 small rewards and five milestones per world, 200 distinct treasure icons, Double-Quest next-day Theme/Icon unlocks, My Collection, and a monthly calendar |
| Guardian tools | Single-tap `Parents` → auto-checking math Parent Gate, Today dashboard, Word Manager, reports, corrections, settings, CSV export, and Lock-to-Kid-selection navigation |
| Accessibility | Landscape child routes plus rotatable parent routes, shared 44-point minimum targets, VoiceOver labels and announcements, Reduce Motion, left-handed writing, Reduced Sound, and Calm Rescue; physical accessibility acceptance remains open |
| Platform | One canonical teacher-audio contract with an offline Apple Speech fallback, repeat-after-me Keychain voiceprints, target-informed Vision handwriting recognition, local notifications, local JSON snapshots, device-only LocalQA, and explicitly enabled CloudKit family sync |

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

The current v0.3 automated run uses Xcode 26.6. Fresh LocalQA builds pass on iPhone 17 Pro Max and iPad Pro 13-inch (M5) simulators.

## Build and test

```sh
git clone https://github.com/darrenfu/tadawords.git
cd tadawords

brew install xcodegen
make generate
make check
open TadaWords.xcodeproj
```

`make check` runs strict Swift formatting checks and the Swift package test suite. The accepted V1 baseline contained **367 tests with zero failures**. Merged v0.2 contained **480 tests with zero failures**. The current v0.3 aggregate contains **548 tests with zero failures**. The Xcode UI target adds five critical end-to-end flows for Read/Write completion, repeated delete/Undo, Photos-picker dismissal, and OCR Review → Add All → Pool → Sort.

Run the device-readiness script before installing on an iPhone or iPad:

```sh
./Scripts/verify-device-readiness.sh
```

Follow [DEVICE_DEPLOYMENT.md](DEVICE_DEPLOYMENT.md) for signing, Developer Mode, and direct installation.

## Data and privacy

- The app stores child profiles, word pools, quest history, and settings in local JSON snapshots.
- The app does not run an app-owned server database.
- Speech and enrollment audio buffers stay in memory. The app does not save or upload raw child recordings.
- Voice setup shuffles six short Pre-K sentences for the child to hear and repeat. Each device stores only the resulting voiceprint template in Keychain. CloudKit does not sync the template, so each device needs its own enrollment.
- Practice uses one canonical teacher-voice contract rather than a per-Profile style picker. When no safe remote endpoint is configured, the app selects the clearest compatible American-English Apple voice already installed and keeps a system fallback. No provider API key is stored in the app.
- Pool import prefetches picture hints only for a child-safe catalog of concrete words. The app requests a fixed Twemoji asset filename, caches the PNG privately, and sends no child name, Profile ID, learning history, or typed word to the content delivery network. Abstract words do not make a request.
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
| Swift tests | v0.3 full run: 548 passed, 0 failures; supersedes the merged v0.2 count of 480 |
| Critical XCUITest flows | 5 passed, 0 failures on iPhone 17 Pro Max simulator |
| iPhone 17 Pro Max LocalQA simulator | Fresh v0.3 build passed |
| iPad Pro 13-inch (M5) LocalQA simulator | Fresh v0.3 build passed |
| Connected iPhone 17 Pro Max | Signed `Tada Words QA` v0.3 candidate installed; human `of`, audio, child handwriting, rotation, and accessibility checks remain |
| Pre-K visual hierarchy | v0.2 Profile, Lobby, Read, and Result captures pass on both simulators; physical child, VoiceOver, and Dynamic Type acceptance remain open |
| Route-based orientation | v0.2 Plist and runtime-policy checks passed. iPad simulator window shapes show Parents rotating while child routes remain landscape. Raw iPhone simulator framebuffer captures are inconclusive, so physical rotation remains open. |
| Persisted, default-off CloudKit guardian opt-in | Implemented; live-device acceptance open |
| CloudKit remote erasure | Implementation required |
| Physical child speech, handwriting, audio, accessibility, and CloudKit | Acceptance open |

The [feature audit](QAArtifacts/FULL_FEATURE_AUDIT_2026-07-12.md) records the merged v0.2 implementation evidence. The [follow-up log](FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md) records the active v0.3 changes, and the [V1 backlog](V1_BACKLOG.md) lists the remaining device and human acceptance work.

## Test fixture attribution

The repository includes one unmodified child-speech fixture from [OpenSLR SLR101, speechocean762](https://www.openslr.org/101/) under CC BY 4.0. Read its [source and license record](Tests/Fixtures/ChildSpeech/LICENSE_SOURCE.md) and [SHA-256 checksum](Tests/Fixtures/ChildSpeech/SHA256SUMS). The app does not bundle this test file.

## Documentation

- [Product and interaction design](TADA_WORDS_V1_PRODUCT_DESIGN.md)
- [Design review](TADA_WORDS_DESIGN_REVIEW.md)
- [Follow-up bug fixes and improvements](FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md)
- [V1 acceptance checklist](MVP_ACCEPTANCE.md)
- [Physical-device deployment](DEVICE_DEPLOYMENT.md)
- [Voiceprint Device Alpha plan](VOICEPRINT_DEVICE_ALPHA.md)
- [Visual and accessibility audit](QAArtifacts/DESIGN_AUDIT_2026-07-12.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

## License

The project source does not include an open-source license. Copyright remains with the project owner. Third-party material retains the copyright and license stated in its [third-party notices](THIRD_PARTY_NOTICES.md) or attribution file.
