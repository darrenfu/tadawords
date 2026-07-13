<p align="center">
  <img src="Apps/TadaWordsApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="112" alt="Tada Words app icon">
</p>

<h1 align="center">Tada Words</h1>

<p align="center"><strong>Short, playful sight-word practice for early readers on iPhone and iPad.</strong></p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/iOS-18%2B-111111?logo=apple" alt="iOS 18 or later">
  <img src="https://img.shields.io/badge/UI-SwiftUI-0D96F6?logo=swift&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/status-v0.2%20device%20QA-6D48D7" alt="v0.2 device QA">
</p>

Tada Words gives children two separate daily quests for sight words:

- **Read:** See a word and say it aloud.
- **Write:** Hear a word and write the whole word by hand.

Parents add every practice word by typing it or scanning a school list with the camera or photo library. Tada Words schedules only those parent-provided words; V1 never grows a Pool from a grade catalog or smart fill. The review scheduler brings words back based on recall strength, errors, help use, replays, and each child's response pace.

> **Project status:** Work is active on branch `v0.2` after the first physical-iPhone feedback pass. The branch-wide Swift suite passes **479/479**, and LocalQA simulator builds pass for iPhone 17 Pro Max and iPad Pro 13-inch (M5). Fresh physical-device installation, child speech/handwriting, launch-voice listening, accessibility, and iPad acceptance remain open. Family Sync is persisted, default-off, and requires explicit parent opt-in; CloudKit remote erasure remains a release blocker. See the [follow-up log](FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md) and [acceptance checklist](MVP_ACCEPTANCE.md).

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

Read never speaks the target before the child's first independent response. After two valid wrong readings it reveals child-triggered pronunciation and a local picture hint; technical retries never reveal help early. Its large word color varies deterministically inside the active World's high-contrast palette, without flickering during an attempt. Write uses a slower, clearly released pronunciation, then reveals the answer after an error and offers one guided rewrite. Children can choose Pencil, Crayon, Chalk, or Brush, 12 basic colors, and a local 2.5× eraser; each pen keeps its own stroke character and gentle writing sound. Technical speech or recognition failures do not reduce the child's score.

Child-facing stars reward completion, accurate retrieval, and a comfortable personal pace. One immediate unaided recovery can still earn the Accuracy Star, calibration can earn Pace, and the post-calibration slow side gets 25% grace. Guardian accuracy and mastery evidence stay strict.

The scheduler uses an Ebbinghaus-style recall model. A word reaches Mastered after independent success on three local dates and a predicted 14-day recall rate above the configured threshold.

## V1 features

| Area | Included |
|---|---|
| Practice | Separate Read and Write pools, independent Today Quest buttons, New and Review ordering, timer, Rescue state, score, stars, and mastery |
| Word setup | One-word Return-to-add, local Camera/Photo OCR review, newest-first Read/Write queues, de-duplication, single/bulk delete, and Undo; no automatic additions |
| Profiles | Profile-first launch, multiple children, nickname entry, last-profile highlight, animal/photo/collected-treasure avatar, earned icon, grade, age, and preferred world |
| Motivation | Eight original worlds, 20 small rewards and five milestones per world, 200 distinct treasure icons, Double-Quest next-day Theme/Icon unlocks, My Collection, and a monthly calendar |
| Guardian tools | Single-tap `Parents` → math Parent Gate, Today dashboard, Word Manager, reports, corrections, settings, and CSV export |
| Accessibility | Landscape child routes plus rotatable parent routes, shared 44-point minimum targets, VoiceOver labels and announcements, Reduce Motion, left-handed writing, Reduced Sound, and Calm Rescue; physical accessibility acceptance remains open |
| Platform | Apple Speech, Vision handwriting recognition, Keychain voiceprints, local notifications, local JSON snapshots, device-only LocalQA, and explicitly enabled CloudKit family sync |

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

The current v0.2 automated run used Xcode 26.6, an iPhone 17 Pro Max simulator, and an iPad Pro 13-inch (M5) simulator.

## Build and test

```sh
git clone https://github.com/darrenfu/tadawords.git
cd tadawords

brew install xcodegen
make generate
make check
open TadaWords.xcodeproj
```

`make check` runs strict Swift formatting checks and the Swift package test suite. The accepted V1 baseline contained **367 tests with zero failures**; it is superseded for the active branch by the full v0.2 run of **479 tests with zero failures**.

Run the device-readiness script before installing on an iPhone or iPad:

```sh
./Scripts/verify-device-readiness.sh
```

Follow [DEVICE_DEPLOYMENT.md](DEVICE_DEPLOYMENT.md) for signing, Developer Mode, and direct installation.

## Data and privacy

- The app stores child profiles, word pools, quest history, and settings in local JSON snapshots.
- The app does not run an app-owned server database.
- Speech and enrollment audio buffers stay in memory. The app does not save or upload raw child recordings.
- Each device stores its voiceprint template in Keychain. CloudKit does not sync the template, so each device needs its own enrollment.
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
| Swift tests | v0.2 full run: 479 passed, 0 failures; supersedes the 367-test V1 baseline |
| iPhone 17 Pro Max LocalQA simulator | Build passed |
| iPad Pro 13-inch (M5) LocalQA simulator | Build passed |
| Route-based orientation | Plist and runtime-policy checks passed. iPad simulator window shapes show Parents rotating while child routes remain landscape. Raw iPhone simulator framebuffer captures are inconclusive, so physical rotation remains open. |
| Persisted, default-off CloudKit guardian opt-in | Implemented; live-device acceptance open |
| CloudKit remote erasure | Implementation required |
| Physical child speech, handwriting, audio, accessibility, and CloudKit | Acceptance open |

The [feature audit](QAArtifacts/FULL_FEATURE_AUDIT_2026-07-12.md) records the implementation evidence. The [V1 backlog](V1_BACKLOG.md) lists the remaining device and human acceptance work.

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

## License

The project source does not include an open-source license. Copyright remains with the project owner. Third-party material retains the copyright and license stated in its attribution file.
