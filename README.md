<p align="center">
  <img src="Apps/TadaWordsApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="112" alt="Tada Words app icon">
</p>

<h1 align="center">Tada Words</h1>

<p align="center"><strong>Short, playful sight-word practice for early readers on iPhone and iPad.</strong></p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/iOS-18%2B-111111?logo=apple" alt="iOS 18 or later">
  <img src="https://img.shields.io/badge/UI-SwiftUI-0D96F6?logo=swift&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/status-V1%20pre--release-6D48D7" alt="V1 pre-release">
</p>

Tada Words gives children two separate daily quests for sight words:

- **Read:** See a word and say it aloud.
- **Write:** Hear a word and write the whole word by hand.

Parents can enter each week's school list or let the app fill a short practice set from its grade-based catalog. The review scheduler brings back words based on recall strength, errors, help use, replays, and each child's response pace.

> **Project status:** The V1 source, automated tests, and simulator builds pass. CloudKit consent and remote erasure need implementation before family deployment. Physical-device testing, child speech calibration, handwriting calibration, and live CloudKit acceptance remain open. See the [acceptance checklist](MVP_ACCEPTANCE.md).

The app ships three separate visual worlds: Moonpetal Kingdom, Build-It Bay, and Paws & Pines. Each world keeps its own scene, music, sound cues, and reward collection.

## Learning model

| Route | Prompt | Child response | Evidence |
|---|---|---|---|
| Read Quest | The app shows a sight word | The child says the word | On-device speech recognition plus optional device voiceprint confidence |
| Write Quest | The app speaks a sight word | The child writes the complete word | Vision handwriting recognition from the drawing canvas |
| Review | The scheduler selects due and weak words | The child retrieves the word again | Accuracy, elapsed time, help, replay, and retry history |

The app demonstrates each new word once before independent recall. Read allows two valid retries. Write reveals the answer after an error and offers one guided rewrite. Technical speech or recognition failures do not reduce the child's score.

The scheduler uses an Ebbinghaus-style recall model. A word reaches Mastered after independent success on three local dates and a predicted 14-day recall rate above the configured threshold.

## V1 features

| Area | Included |
|---|---|
| Practice | Separate Read and Write pools, independent Today Quest buttons, New and Review ordering, timer, Rescue state, score, stars, and mastery |
| Word setup | Parent-entered pools, automatic de-duplication, smart fill, and grade-based recommendations |
| Profiles | Multiple child profiles, nickname entry, last-profile restore, animal or photo avatar, grade, age, and preferred world |
| Motivation | Three original worlds, 20 small rewards and five milestones per world, unlocks, and a Collection screen |
| Guardian tools | Parent gate, Today dashboard, monthly quest calendar, 7-day and 30-day reports, corrections, settings, and CSV export |
| Accessibility | Landscape-only layouts, shared 44-point minimum targets, VoiceOver labels and announcements, Reduce Motion, left-handed writing, Reduced Sound, and Calm Rescue; physical accessibility acceptance remains open |
| Platform | Apple Speech, Vision handwriting recognition, Keychain voiceprints, local notifications, local JSON snapshots, and a CloudKit transport whose consent gate remains a release blocker |

## Architecture

The Swift package keeps learning policy separate from SwiftUI and Apple frameworks.

| Module | Responsibility |
|---|---|
| `TadaWordsDomain` | Entities, value objects, and service contracts |
| `TadaWordsLearning` | Planning, review, scoring, pace, and mastery rules |
| `TadaWordsContent` | Word pools, persistence, recommendations, sync records, and rewards |
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
- An Apple Developer Team for signed device builds and CloudKit

The latest V1 acceptance run used Xcode 26.6, an iPhone 17 Pro Max simulator, and an iPad Pro 13-inch simulator.

## Build and test

```sh
git clone https://github.com/darrenfu/tadawords.git
cd tadawords

brew install xcodegen
make generate
make check
open TadaWords.xcodeproj
```

`make check` runs strict Swift formatting checks and the Swift package test suite. The latest V1 pass contains **367 tests with zero failures**.

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
- The signed-device V1 starts CloudKit synchronization after onboarding when the configured container and an iCloud account are available. The app does not yet store a separate guardian opt-in.
- Profile deletion clears local learning data, reminders, and the local voiceprint. It uploads a tombstone that prevents profile resurrection, but it does not yet erase records already stored in CloudKit.

The voiceprint provides a confidence signal. It does not prove that only the selected child spoke. Production use needs representative same-child and different-speaker testing.

Simulator builds use a local-only family sync transport. Signed physical-device builds use the real CloudKit path after the developer configures `iCloud.com.tadawords.app` and signs in to iCloud. Add a persisted, default-off guardian consent gate and remote record erasure before using that path with family data.

## Validation status

| Check | Result |
|---|---|
| Strict Swift format lint | Passed |
| Swift tests | 367 passed, 0 failed |
| iPhone 17 Pro Max Release simulator | Built, installed, and launched |
| iPad Pro 13-inch Release simulator | Built, installed, and launched |
| Landscape declarations | Landscape Left and Landscape Right only |
| CloudKit guardian opt-in and remote erasure | Implementation required |
| Physical child speech, handwriting, audio, accessibility, and CloudKit | Acceptance open |

The [feature audit](QAArtifacts/FULL_FEATURE_AUDIT_2026-07-12.md) records the implementation evidence. The [V1 backlog](V1_BACKLOG.md) lists the remaining device and human acceptance work.

## Test fixture attribution

The repository includes one unmodified child-speech fixture from [OpenSLR SLR101, speechocean762](https://www.openslr.org/101/) under CC BY 4.0. Read its [source and license record](Tests/Fixtures/ChildSpeech/LICENSE_SOURCE.md) and [SHA-256 checksum](Tests/Fixtures/ChildSpeech/SHA256SUMS). The app does not bundle this test file.

## Documentation

- [Product and interaction design](TADA_WORDS_V1_PRODUCT_DESIGN.md)
- [Design review](TADA_WORDS_DESIGN_REVIEW.md)
- [V1 acceptance checklist](MVP_ACCEPTANCE.md)
- [Physical-device deployment](DEVICE_DEPLOYMENT.md)
- [Voiceprint Device Alpha plan](VOICEPRINT_DEVICE_ALPHA.md)
- [Visual and accessibility audit](QAArtifacts/DESIGN_AUDIT_2026-07-12.md)

## License

The project source does not include an open-source license. Copyright remains with the project owner. Third-party material retains the copyright and license stated in its attribution file.
