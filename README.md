# Tada Words

Tada Words is a landscape-only SwiftUI learning app for early readers. Children practice two independent skills: Read shows a sight word for the child to say, while Write plays a word for the child to handwrite.

The app is local-first and supports iPhone and iPad. Core quests keep working without a network connection. Production composition uses Apple Speech, Vision handwriting recognition, procedural world audio, device-scoped voiceprints, local notifications, local JSON snapshots, and optional CloudKit family sync.

## What V1 includes

- Separate Read and Write pools, Today Quest buttons, settings, histories, and review schedules
- Parent-entered words plus optional grade-based recommendations with automatic de-duplication
- Ebbinghaus-style review priority, child-relative pace, guided retries, score, stars, and true mastery criteria
- Multiple Kid Profiles, last-profile restore, nickname-only child creation, animal or photo avatars, grade, age, and world selection
- First-run parent onboarding with versioned consent, Profile setup, and optional starter words for both pools
- Three separate original worlds, 20 small rewards and five milestones per world, world unlocks, and Collection
- Guardian Today, monthly quest calendar, 7-day and 30-day reports, correction history, and comma-separated values (CSV) export
- Profile-specific audio, notification, left-handed writing, Reduced Sound, and Calm Rescue settings
- Crash-resumable profile deletion that clears local learning data, reminders, and the device voiceprint
- Optional CloudKit sync and Apple iCloud family invitations

CloudKit and family sharing require an Apple Developer Team, the configured iCloud container, signed-in iCloud accounts, and physical-device acceptance. Simulator builds intentionally use a device-only local sync transport; the real CloudKit transport is created only by a signed physical-device build. Voiceprint matching runs on the device and never syncs its template. It is an accuracy aid, not proof that the microphone captured only one person.

## Modules

```text
TadaWordsDomain            Entities, value objects, and service contracts
TadaWordsLearning          Planning, review, evidence, mastery, and scoring
TadaWordsContent           Pools, recommendations, persistence, sync records, and rewards
TadaWordsDesignSystem      Reusable child and Guardian design tokens and components
TadaWordsFeatures          Profiles, lobby, Read, Write, results, worlds, and Collection
TadaWordsGuardianFeatures  Parent gate, profiles, settings, reports, sync, and voice setup
TadaWordsApplePlatform     Speech, Vision, audio, Keychain, notifications, and CloudKit
TadaWordsAppShell          Production composition and local-first bootstrap
TadaWordsPreview           macOS-hosted SwiftUI preview executable
```

Dependencies point inward. Domain code does not import SwiftUI, Speech, Vision, PencilKit, UserNotifications, or CloudKit.

## Run the checks

```sh
make generate
make check
./Scripts/verify-device-readiness.sh
swift run TadaWordsPreview
```

`make generate` creates the canonical `TadaWords.xcodeproj` from `project.yml`. Open only that project. The canonical 367-test check and both Release simulator builds passed. The stale numbered project copies and `Apps/TadaWordsApp/Info 2.plist` have been removed; only the canonical project and plist remain.

Direct device installation requires Developer Mode, a selected Apple development Team, and a valid signing identity. CloudKit also requires the `iCloud.com.tadawords.app` container under that Team.

## Understand local data

Asset-catalog `Contents.json` files describe app icons and colors. Child data lives in JSON snapshots under the app's Application Support directory. Tada Words has no app-owned server database. When a guardian enables Family Sync, CloudKit copies supported learning records between authorized Apple accounts; local files remain the offline source for quests.

## Product and acceptance documents

- [Run the V1 acceptance checklist](MVP_ACCEPTANCE.md)
- [Read the V1 product design](TADA_WORDS_V1_PRODUCT_DESIGN.md)
- [Review remaining release work](V1_BACKLOG.md)
- [Install on a physical device](DEVICE_DEPLOYMENT.md)
- [Review the current feature audit](QAArtifacts/FULL_FEATURE_AUDIT_2026-07-12.md)
- [Review the current design audit](QAArtifacts/DESIGN_AUDIT_2026-07-12.md)
- [Review the voiceprint Device Alpha plan](VOICEPRINT_DEVICE_ALPHA.md)
