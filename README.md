<p align="center">
  <img src="Apps/TadaWordsApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="112" alt="Tada Words app icon">
</p>

<h1 align="center">Tada Words</h1>

<p align="center"><strong>Short, playful sight-word practice for early readers on iPhone and iPad.</strong></p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/iOS-18%2B-111111?logo=apple" alt="iOS 18 or later">
  <img src="https://img.shields.io/badge/UI-SwiftUI-0D96F6?logo=swift&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/status-v0.7.32%20Voiceprint%20Fallback-6D48D7" alt="v0.7.32 voiceprint fallback">
</p>

Tada Words gives children two separate daily quests for sight words:

- **Read:** See a word and say it aloud.
- **Write:** Hear a word, then either write it by hand or spell it with the
  app's theme-matched A–Z keyboard.

Parents add every practice word by typing, scanning a school list with optical character recognition (OCR), or selecting words from an offline preset. Tada Words never fills a Pool automatically. The review scheduler brings parent-approved words back based on recall strength, errors, help use, replays, and each child's response pace.

> **Project status:** Version `0.7.32` (build `2026072406`) invokes the conservative App Store 1.0 fallback for unresolved COPPA treatment: voiceprint enrollment and speaker matching are not shipped. The device-local repository remains composed only so Profile deletion and proven-fresh-install cleanup can remove an existing pre-release template. The release retains the v0.7.28 on-device crop-and-mask editor, the v0.7.30 signed Keychain lifecycle proof, and the App Store 1.0 distribution contract: Made for Kids 6–8, Free with no IAP or ads, United States only, and manual release. See the [1.0 fallback record](Docs/VOICEPRINT_1_0_RELEASE_FALLBACK_v0.7.32.md), [voiceprint lifecycle record](Docs/VOICEPRINT_KEYCHAIN_LIFECYCLE_v0.7.30.md), [decision record](Docs/APP_STORE_RELEASE_DECISIONS_v0.7.27.md), v0.7.5 [submission pack](Docs/APP_STORE_SUBMISSION_PACK_v0.7.5.md), [privacy inventory](Docs/APP_STORE_PRIVACY_v0.7.4.md), [content-rights inventory](Docs/APP_STORE_CONTENT_RIGHTS.md), [data manifest](Docs/FAMILY-SYNC-DATA-MANIFEST.md), and [follow-up log](FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md).

The app ships eight separate visual worlds: Moonpetal Kingdom, Build-It Bay,
Paws & Pines, Dino Discovery, Firehouse Heroes, Brickwork City, Frostlight
World, and Coaster Carnival. Each world keeps its own original scene, mascot,
music, sound cues, and 25-item reward collection.

## Learning model

| Route | Prompt | Child response | Evidence |
|---|---|---|---|
| Read Quest | The app shows a sight word | The child says the word | On-device speech recognition; App Store 1.0 does not use voiceprint speaker matching |
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
| Guardian tools | Single-tap `Parents` → auto-checking math Parent Gate, World-themed Parent Home with a Profile card, Words & Practice, Progress, and App & Family entrances, Word Manager, reports, corrections, settings, CSV export, offline Third-Party Notices, and Back-to-child navigation |
| Accessibility | Landscape child routes plus rotatable parent routes, shared 44-point minimum targets, VoiceOver labels and announcements, Reduce Motion, left-handed writing, Reduced Sound, and Calm Rescue; physical accessibility acceptance remains open |
| Platform | A 1.8s branded launch page with official Tada Words and Pawgoo marks, offline-first Katie teacher audio with an Apple Speech fallback, bundled Aurora launch/transitions, dormant Keychain-template cleanup with no 1.0 enrollment or matching, target-informed Vision handwriting recognition, local notifications, local JSON snapshots, device-only LocalQA, and explicitly enabled CloudKit family sync |

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

The current v0.7.32 source candidate uses Xcode 26.6. Merged v0.7.2 passed
the exact-HEAD iPhone/iPad simulator matrix, LocalQA install guard, and a data-
preserving physical iPhone update; merged v0.7.3 added offline Parent notices
and exact content verification. Family Sync production schema, signed cross-
device sharing/deletion, human accessibility, and exact-release privacy/network
acceptance remain open.

## Build and test

```sh
git clone https://github.com/darrenfu/tadawords.git
cd tadawords

brew install xcodegen
make generate
make check
open TadaWords.xcodeproj
```

`make check` runs strict Swift formatting checks, the Swift package test suite, Issue Agent checks, and release-candidate preflight failure-mode tests. The accepted V1 baseline contained **367 tests with zero failures**. Merged v0.2 contained **480**, v0.3 contained **548**, v0.3.1 and v0.4.1 contained **595**, v0.5 contained **619**, v0.5.1 contained **638**, v0.6.0 contained **641**, and v0.6.1 contained **643 Swift tests plus 14 Issue Agent tests**, all with zero failures. The v0.7.0 source batch passed **814 Swift tests plus 14 Issue Agent tests**. Merged v0.7.2 passed **821 Swift tests, 40 Issue Agent tests, and 11 release-preflight tests**; merged v0.7.3 passed **822 Swift tests** with the same automation/preflight counts; v0.7.4 passed **834 Swift tests**; v0.7.5 passed **837 Swift tests**; v0.7.6 passed **998 Swift tests**, **40 Issue Agent tests**, and **11 release-preflight tests**; v0.7.7 added five Production APNs cases for **16 release-preflight tests**; and the v0.7.8 pre-commit source gate passed **1,016 Swift tests**, **40 Issue Agent tests**, and those **16 release-preflight tests**. Merged v0.7.11 passed **1,119 Swift tests**, **91 Issue Agent tests**, and **18 release-preflight tests**. The v0.7.12 source gate passes **1,119 Swift tests**, **91 Issue Agent tests**, and **54 release/identity-verifier tests**; exact committed-HEAD simulator and signed-artifact evidence is recorded separately. A separate physical-device target calls the public production handwriting service and does not use the demo recognizer. See [`Docs/RELEASE_CANDIDATE_PREFLIGHT.md`](Docs/RELEASE_CANDIDATE_PREFLIGHT.md) for the canonical signed archive/export verification command.

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
  0.7.32 2026072406 "$(git rev-parse HEAD)" com.tadawords.app.localqa
```

For the normal PawGoo Development artifact, use the stricter no-install gate:

```sh
./Scripts/verify-pawgoo-development-app.py \
  '/path/to/Tada Words.app' \
  0.7.32 2026072406 "$(git rev-parse HEAD)" \
  --device-udid 'APPROVED_IPHONE_HARDWARE_UDID' \
  --device-udid 'APPROVED_IPAD_HARDWARE_UDID'
```

Those values are the hardware UDIDs listed in the provisioning profile, not
the CoreDevice UUIDs accepted by `xcrun devicectl`. The command prints the
verified app-tree SHA-256; the install lane must recheck that digest before it
uses the serialized artifact.

The local [Issue Agent](Automation/issue-agent/README.md) can pick up ready
GitHub Issues by priority, batch related module work, and stop for human
product, device, and merge gates. Its recurring scheduler is disabled unless
the owner explicitly enables it.

Follow [DEVICE_DEPLOYMENT.md](DEVICE_DEPLOYMENT.md) for signing, Developer Mode, and direct installation.

## Data and privacy

- The app stores child profiles, word pools, quest history, and settings in local JSON snapshots.
- The PawGoo normal bundle `app.tadawords.app` has a new iOS sandbox, permission state, and default Keychain group. It cannot read, replace, or migrate the separate `com.tadawords.app.localqa` data.
- The app does not run an app-owned server database.
- Speech audio buffers stay in memory. The app does not save or upload raw child recordings.
- App Store 1.0 does not expose voiceprint enrollment or use a retained template for speaker matching. An existing pre-release template stays inaccessible to practice and remains device-only; Profile deletion and proven-fresh-install bootstrap retain their fail-closed cleanup paths.
- Practice uses one canonical teacher-voice contract rather than a per-Profile style picker. A versioned offline pack covers 500 words with Katie as the canonical voice and one manifest-documented Aurora quality override for `bun`; other words use the clearest compatible American-English Apple voice already installed. Aurora launch and transition clips are also bundled. No Cartesia API key or runtime Cartesia request is present in the app.
- Pool import prefetches only the child-safe concrete-word picture catalog. All 74 unique Twemoji PNGs are bundled with the app, so a fresh offline install needs no CDN request. Abstract words have no picture mapping.
- Parents can open offline Third-Party Notices behind the Parent Gate to review the exact Twemoji source, modification status, copyright attribution, and CC BY 4.0 license.
- Release builds keep iCloud Family Sync off by default. Completing onboarding does not enable it; a parent must explicitly turn it on in Guardian settings.
- Turning Family Sync off prevents later lifecycle, manual, invitation, and access-management sync calls. By design, opting out does not erase records that were already uploaded; Profile deletion is the separate erasure action.
- APNs registration diagnostics are process-only and bounded to the latest not-requested, pending, registered, or coarse failed state plus its timestamp. UIKit drops the opaque device token at the callback boundary; the app never retains, prints, hashes, persists, or exports it. Notification-presentation permission is not used to infer silent CloudKit registration success.
- Profile deletion first commits a tombstone and device-local erasure lifecycle, then clears local learning data, reminders, the local voiceprint, and staged photo sources. Parent UI exposes only anonymous aggregate state. Completion requires the exact tombstone revision after the owner path removes its Profile zone/payload assets or the participant path completes leave/revocation; account provenance prevents a different Apple account from acknowledging the operation. The sole remaining Profile cannot currently be deleted and there is no complete Delete All App Data path. Issue #19 owns that gap plus signed production destructive proof.
- The versioned [App Store privacy inventory](Docs/APP_STORE_PRIVACY_v0.7.4.md)
  maps every audited runtime flow to its device/network boundary and records
  the owner attestations and Pawgoo copy changes required before submission.
- The [shipping system-permission inventory](Docs/SYSTEM_PERMISSION_INVENTORY_v0.7.8.md)
  names every requesting API, its adult-owned entry point, the child fail-closed
  behavior, deterministic negative route contracts, and the exact-device matrix
  still required for release.

Voiceprint enrollment and speaker matching are not included in App Store 1.0 while issue #76 remains unresolved.

The `TadaWordsLocalQA` scheme installs a visibly separate **Tada Words QA** app with bundle ID `com.tadawords.app.localqa`. It has no iCloud entitlement, does not advertise CloudKit sharing, and keeps data only on that device. Its local data is separate from the release app and does not sync to another device.

Simulator builds also use a deterministic local test transport. A normal signed physical-device Release build can use CloudKit only after the developer configures `iCloud.com.tadawords.app`, the device is signed in to iCloud, and a parent opts in. The production-only access UI uses Apple's existing-share controller and fails closed for revoked, deleted, or malformed routes. Production schema, sharing, background delivery, and destructive erasure still require signed-device acceptance before release use with family data.

## Validation status

| Check | Result |
|---|---|
| Strict Swift format lint | Passed |
| Version and build | v0.7.32 (`2026072406`) in source Plists and generated project settings |
| Swift tests | v0.7.32 voiceprint release-policy and composition contracts plus v0.7.30 lifecycle cleanup, v0.7.28 camera OCR editor, atomic Family Sync, Profile chooser, and content-rights coverage; full source gate is rerun at the immutable release HEAD |
| Family Sync physical delta | Normal PawGoo v0.7.18 installed in place on the approved iPhone and iPad; an iPhone-created test Profile converged automatically to the untouched iPad without opening Family Sync, with one matching record and four Profiles total on each side |
| Family Sync simulator E2E | Merged v0.7.2: 6/6 on iPhone 17 Pro Max and 6/6 on iPad Pro 13-inch (M5), iOS 26.5 |
| Critical XCUITest flows | Merged v0.7.2: full critical matrix passed on iPad; the single iPhone Photos-dismiss timing case passed 2/2 in isolated fresh reruns after the combined run, and every other flow passed |
| Third-Party Notices | Parent-gated offline text, exact attribution, source/license links, and route tests passed; focused UI flow passed 1/1 on iPhone 17 Pro Max and 1/1 on iPad Pro 13-inch (M5), iOS 26.5 |
| Data-preserving upgrade | Merged v0.7.2 installed in place on the physical iPhone and reached the existing Profile chooser; 2 Profiles, 201 Word Pool entries, 488 canonical attempts, and 62 derived progress rows remained present |
| Parent Privacy/Support XCUITest | v0.6.1 focused flow: 1/1 passed on iPhone 17 Pro Max and 1/1 passed on iPad Pro 13-inch simulators |
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
| CloudKit access management | Production owner/participant route and reconciliation implemented; signed owner removal, participant leave, and revocation acceptance open |
| CloudKit remote erasure | Durable lifecycle, exact owner/participant disposition, crash repair, retry, terminal completion, and account-provenance tests passed; production destructive test-only proof open |
| Physical child speech, handwriting, audio, accessibility, and CloudKit | Acceptance open |

The [feature audit](QAArtifacts/FULL_FEATURE_AUDIT_2026-07-12.md) records the merged v0.2 implementation evidence. The [follow-up log](FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md) records changes through v0.7.32, and the [V1 backlog](V1_BACKLOG.md) lists the remaining device and human acceptance work.

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
- [App Store privacy inventory](Docs/APP_STORE_PRIVACY_v0.7.4.md)
- [App Store submission pack](Docs/APP_STORE_SUBMISSION_PACK_v0.7.5.md)
- [Visual and accessibility audit](QAArtifacts/DESIGN_AUDIT_2026-07-12.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)
- [App Store content-rights inventory](Docs/APP_STORE_CONTENT_RIGHTS.md)

## License

The project source does not include an open-source license. Copyright remains with the project owner. Third-party material retains the copyright and license stated in its [third-party notices](THIRD_PARTY_NOTICES.md) or attribution file.
