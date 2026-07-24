<!-- TADA_BILINGUAL_DOC: English is the default reading language. The original source text is preserved for verification. -->
<a id="english-default"></a>

> **Languages / 语言：** **English (default) / 英文（默认）** · [简体中文](#简体中文版)

<p align="center">
  <img src="Apps/TadaWordsApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="112" alt="Tada Words app icon">
</p>

<h1 align="center">Tada Words</h1>

<p align="center"><strong>Short, playful sight-word practice for early readers on iPhone and iPad.</strong></p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/iOS-18%2B-111111?logo=apple" alt="iOS 18 or later">
  <img src="https://img.shields.io/badge/UI-SwiftUI-0D96F6?logo=swift&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/status-v0.7.39%20App%20Store%20Acceptance-6D48D7" alt="v0.7.39 App Store acceptance candidate">
</p>

Tada Words gives children two separate daily quests for sight words:

- **Read:** See a word and say it aloud.
- **Write:** Hear a word, then either write it by hand or spell it with the
  app's theme-matched A–Z keyboard.

Parents add every practice word by typing, scanning a school list with optical character recognition (OCR), or selecting words from an offline preset. Tada Words never fills a Pool automatically. The review scheduler brings parent-approved words back based on recall strength, errors, help use, replays, and each child's response pace.

> **Project status:** Version `0.7.39` (build `2026072413`) is the App Store acceptance candidate. It retains v0.7.38 contextual Read permission sequencing, the v0.7.34 Profile-erasure retry, and the conservative App Store 1.0 voiceprint fallback, and adds a data-preserving production-device installer for signed acceptance. The distribution contract remains: Made for Kids with Apple's `6–8` primary band, public and in-app Profile ages 3–8, Free with no IAP or ads, United States only, and manual release. External App Store, TestFlight, cross-device CloudKit, privacy-traffic, and human acceptance remain pending until recorded against this exact release HEAD. See the [v0.7.39 release note](Docs/Releases/v0.7.39-app-store-acceptance.md), [v0.7.38 permission release note](Docs/Releases/v0.7.38-child-speech-permissions.md), [1.0 fallback record](Docs/VOICEPRINT_1_0_RELEASE_FALLBACK_v0.7.32.md), [decision record](Docs/APP_STORE_RELEASE_DECISIONS_v0.7.27.md), v0.7.5 [submission pack](Docs/APP_STORE_SUBMISSION_PACK_v0.7.5.md), [privacy inventory](Docs/APP_STORE_PRIVACY_v0.7.4.md), [content-rights inventory](Docs/APP_STORE_CONTENT_RIGHTS.md), [data manifest](Docs/FAMILY-SYNC-DATA-MANIFEST.md), and [evidence matrix](Docs/FAMILY-SYNC-ACCEPTANCE-COVERAGE.md).

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

The current v0.7.39 source candidate uses Xcode 26.6. Merged v0.7.2 passed
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
  0.7.39 2026072413 "$(git rev-parse HEAD)" com.tadawords.app.localqa
```

For the normal PawGoo Development artifact, use the stricter no-install gate:

```sh
./Scripts/verify-pawgoo-development-app.py \
  '/path/to/Tada Words.app' \
  0.7.39 2026072413 "$(git rev-parse HEAD)" \
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
  names every requesting API and entry point. A first microphone tap in Read can
  request still-undetermined Speech Recognition and Microphone access in
  sequence, while denied, restricted, or revoked states fail closed with
  Ask-a-Parent recovery. The exact-device matrix remains required for release.

Voiceprint enrollment and speaker matching are not included in App Store 1.0 while issue #76 remains unresolved.

The `TadaWordsLocalQA` scheme installs a visibly separate **Tada Words QA** app with bundle ID `com.tadawords.app.localqa`. It has no iCloud entitlement, does not advertise CloudKit sharing, and keeps data only on that device. Its local data is separate from the release app and does not sync to another device.

Simulator builds also use a deterministic local test transport. A normal signed physical-device Release build can use CloudKit only after the developer configures `iCloud.com.tadawords.app`, the device is signed in to iCloud, and a parent opts in. The production-only access UI uses Apple's existing-share controller and fails closed for revoked, deleted, or malformed routes. Production schema, sharing, background delivery, and destructive erasure still require signed-device acceptance before release use with family data.

## Validation status

| Check | Result |
|---|---|
| Strict Swift format lint | Passed |
| Version and build | v0.7.39 (`2026072413`) in source Plists and generated project settings |
| Swift tests | v0.7.39 adds the data-preserving production-install contract and retains contextual child permission sequencing, overlap/cancellation protection, ages 3–8 profile-write, App Store decision, voiceprint release-policy, atomic Family Sync, content-rights, and Profile-erasure coverage; the full source gate is rerun at the immutable release HEAD |
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

The [feature audit](QAArtifacts/FULL_FEATURE_AUDIT_2026-07-12.md) records the merged v0.2 implementation evidence. The [follow-up log](FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md) records changes through v0.7.33, and the [V1 backlog](V1_BACKLOG.md) lists the remaining device and human acceptance work.

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
<!-- TADA_BILINGUAL_ZH_START -->

---

<a id="简体中文版"></a>

> **翻译说明：** 英文为默认阅读语言；本文同时保留原始语言文本。如中英文内容存在差异，请以原始语言文本为准。

<p align="center">
<img src="Apps/TadaWordsApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="112" alt="Tada Words app icon">
</p>

<h1 align="center">Tada Words</h1>

<p align="center"><strong>针对早期阅读者在iPhone和iPad上的简短、有趣的视字练习。</strong></p>

<p align="center">
<img src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white" alt="Swift 6.0">
<img src="https://img.shields.io/badge/iOS-18%2B-111111?logo=apple" alt="iOS 18 or later">
<img src="https://img.shields.io/badge/UI-SwiftUI-0D96F6?logo=swift&logoColor=white" alt="SwiftUI">
<img src="https://img.shields.io/badge/status-v0.7.39%20App%20Store%20Acceptance-6D48D7" alt="v0.7.39 App Store acceptance candidate">
</p>

Tada Words为孩子们提供了每天两个独立的视字任务：

- **Read:**看到一个单词，然后大声说出来。
- **Write:**听到一个单词，然后要么用手写，要么用...拼写它
与应用主题相匹配的 A-Z 键盘。

Parents通过键入、使用光学字符识别（OCR）扫描学校列表或从离线预设中选择单词来添加每个练习单词。Tada Words从不自动填充池。审查时间表根据回忆强度、错误、帮助使用、重播和每个孩子的反应速度将家长批准的单词带回。

> **项目状态：**版本 `0.7.39`（构建 `2026072413`）是 App Store 验收候选。它保留 v0.7.38 的 Read 权限顺序、v0.7.34 的 Profile 删除重试，以及 App Store 1.0 voiceprint fallback，并新增先验证持久化兼容性、再原位安装的生产真机通道。分发契约仍为：Made for Kids，Apple 主年龄段 `6–8`，产品与 App 内 Profile 年龄 3–8，免费、无内购、无广告，仅美国区，手动发布。App Store、TestFlight、跨设备 CloudKit、隐私流量和人工验收必须在该精确发布 HEAD 上记录后才算完成。另见 [v0.7.39 发布说明](Docs/Releases/v0.7.39-app-store-acceptance.md)、[v0.7.38 权限发布说明](Docs/Releases/v0.7.38-child-speech-permissions.md)、[1.0 fallback 记录](Docs/VOICEPRINT_1_0_RELEASE_FALLBACK_v0.7.32.md)、[App Store 决策记录](Docs/APP_STORE_RELEASE_DECISIONS_v0.7.27.md)和[隐私清单](Docs/APP_STORE_PRIVACY_v0.7.4.md)。

该应用程序包含八个独立的视觉世界：Moonpetal Kingdom、Build-It Bay、Paws & Pines、Dino Discovery、Firehouse Heroes、Brickwork City、Frostlight World和Coaster Carnival。每个世界都保留了自己的原创场景、吉祥物、音乐、声音线索和25个物品的奖励收藏。

## 学习模型

| 路线 | 迅速 | 儿童反应 | 证据 |
|---|---|---|---|
| Read Quest | 应用程序显示一个视觉单词 | 孩子说出单词 | 设备上的语音识别加上可选的设备语音指纹置信度 |
| Write Quest | 应用程序会说视觉单词 | 孩子选择手写或应用程序内的A-Z拼写键盘 | 视觉手写识别或精确大小写无区分的打字拼写；两者都完成相同的 Write Quest 同时速度保持独立 |
| 复习 | 排程器选择应答和弱词 | 孩子再次检索单词 | 准确性、已过时间、帮助、重播和重试历史记录 |

Read在孩子第一次独立反应之前从不说目标。在两次有效的错误读数后，它只显示由孩子触发的**听到它**；技术重试从不提前显示帮助。涵盖的单词使用捆绑的Katie Read提示录音，而其他由监护人输入的单词使用Apple语音。每个世界拥有一个协调的、高对比度的单词颜色，因此每个Read单词在视觉上保持一致，直到孩子切换世界。

Write 会为首批 500 个覆盖词播放 0.67× 速度的 Katie 独立单词录音，并且不会预先显示拼写。单独的 Read 提示版本采用相同的 1.5 倍慢速节奏。两个版本都保留 120 毫秒的编码安全尾部填充，确保 `at` 中的 `/t/` 等末尾辅音在播放结束前完整发出。打包范围之外的单词离线回退到 Apple 语音，并保持中性音高和足够的释放时间，以保留末尾辅音。孩子先手动选择 **Write by Hand** 或 **Spell with Letters**；任一方式都会完成同一个 Daily Write Quest，并共享其 Pool、掌握度、复习计划、分数和奖励。打字速度记录在独立的输入方式区间中，因此快速按键不会让手写显得过慢。拼写界面是用 SwiftUI 构建的固定位置、主题配色 QWERTY A–Z 键盘，因此不会出现系统键盘、预测文本、数字或符号。比较时忽略大小写，撇号和连字符则作为提示的结构部分直接提供。聚焦 Replay 会保留所选输入方式。

对于手写，`?`控制可按需显示单词。在第一次真正的不匹配后，如`dog`等具体单词可以显示来自捆绑的Twemoji包的可触摸图片提示，包括在新的离线安装中；如`the`等抽象和功能单词不会收到图像。儿童可以选择铅笔、粉笔或画笔；墨水始终为黑色，所选工具会根据Profile保持不变。4×本地橡皮擦在轻点空白画布后恢复之前的笔迹。画布宽度增加10%，在反馈和单词切换期间保持固定坐标，并保留点、后续字母和连接的笔触。大多数单词保留两个懒散的Vision网格透视，每个观察包含五个候选词。仅视觉模糊的目标`of`在决定之前就收集了三个尺度和最多10个候选词：较低等级的准确拼写需要两个尺度的一致，而任何强烈的完整拼写`off`都拒绝匹配。混合大小写`oF`、连接的小写`of`和六种类似儿童形状的变体都获得这种精确的、特定目标的恢复。数字`0`只有当其对齐的目标位置正好为`o`时才可能代表`o`，因此`0f`和`0F`被接受，而`00`、`90`、`0t`、`0ff`、`+0`和`f0`则仍然被拒绝。技术语音或识别失败不会降低儿童的分数。

面向儿童的星星奖励完成、准确检索和舒适的个人节奏。一次即时的无助恢复仍然可以获得准确性星星，校准可以获得节奏，校准后缓慢的一面获得50%的宽限。Guardian准确性和掌握证据保持严格。

### 评分规则

|结果|面向儿童的规则|
|---|---|
|完成星星|完成每个计划中的单词|
|准确性星|达到75%严格的第一独立准确性，或者错过一个单词，并在看到或听到帮助之前正确回答其立即的无助重试|
|个人速度星|获得准确性并保持在个人速度范围内，保持有效时间校准，或完成完美的第一次尝试|
| 积分 | 最多80个准确性积分加上20个步伐积分 |
|完美第一次尝试|100分和所有三颗星，甚至在存在速度基线之前|

一次恢复规则只改变了孩子的奖励显示。家长报告保持了原始的第一个独立准确性。Replay只出现在运行中包含遗漏或帮助的单词时，它只练习那些棘手的单词。

### 单词发音

Parents只输入学校单词。每个新添加的单词都使用规范的孤立教师发音；没有发音上下文编辑器或发音选择器。包含上下文音频元数据的旧保存提示仍然用于数据兼容性解码，但Parents无法创建或编辑该元数据。

捆绑的音频包包含500个独特的幼儿园至1年级单词，分别有0.67倍的Read和Write录音。Katie是规范教师；在两个独立的语音识别器拒绝Katie的孤立渲染后，Manifest文件向Aurora进行了一个质量覆盖（`bun`）。其1000个AAC剪辑加上八个Aurora资源增加了约7.4 MB。正确的答案保留了所选世界的即时合成闪光，并旋转了五个简短的Aurora庆祝活动；既没有这些行也没有`Quest complete!`使用`Ta-da`作为过渡插话。Reduced Sound抑制了装饰性的口头过渡。

调度器使用Ebbinghaus风格的回忆模型。一个单词在三个本地日期的独立成功后达到熟练程度，并预测的14天回忆率高于配置的阈值。

### 家长控制的单词来源

Parents选择进入Read或Write池的所有单词：

- **打字：**在每个单词后按回车键，将其添加到所选池中
- **相机或照片OCR：**在添加已识别的单词之前，请查看它们。
- **离线预设：**查看按年龄和年级排名的建议或按主题浏览，选择单个单词，选择Read、Write或两者兼而有之，然后轻点**添加**

Parents在创建Profile时记录3至8岁的年龄。Tada Words仅使用年龄和年级来排序预设列表；它从不从它们中添加单词。打包目录包含34个叶子预设，有1,365个单词引用和1,166个唯一的标准化单词。每个叶子包含30-50个单词。有关层次结构、完整列表和源注释，请参阅[预设单词目录](Docs/TADA_WORDS_PRESET_CATALOG.md)。[目录导出脚本](Scripts/export_preset_catalog.py)从App JSON中生成相同的适用于Obsidian的Markdown。

每个池子还具有**删除全部**。Parents确认确切的数量和目标，然后可以使用**撤销**恢复完整的池子。删除确认和撤销状态保持独立于发起者Profile，因此切换的子节点无法暴露或应用另一个子节点的操作。

预设导入也仍然受制于发起者Profile。导入到**两者**完成两个池的导入，或补偿当前请求。补偿仅恢复由该请求插入或重新激活的会员资格，从不停用已经激活的单词。

## V1功能

|区域|包括|
|---|---|
| 练习 | 单独 Read 和 Write 池，独立的 Today Quest 按钮，Write-手动或主题 A-Z 拼写，新和审查排序，计时器，救援状态，分数，星星和掌握 |
| 单词设置 | 单单词返回添加；多照片相机/照片 OCR；34个带有明确单词选择的离线预设列表；编号评论；每张图片500个单词；新增顺序、A-Z和最常用的排序；带有Hear/Delete的预先输入搜索；重复数据删除；会话范围内的删除确认；批量删除；每个池删除所有和撤销；无自动添加 |
| Profiles | Profile-首次发布，多个孩子，昵称输入，从3岁到8岁年龄捕获，最后个人资料亮点，动物/照片/收集宝藏头像，获得的图标，年级和首选世界 |
| 激励 | 8个原始世界，每个世界20个小奖励和5个里程碑，200个不同的宝藏图标，第二天双任务主题/图标解锁，我的收藏和一个月历 |
| Guardian 工具 | 单击 `Parents` → 自动检查数学 Parent Gate，带有Profile卡的世界主题家长主页，单词和练习、进度和应用程序和家庭入口，单词管理器，报告，更正，设置，CSV导出，离线第三方通知和返回儿童导航 |
| 辅助功能 | 景观儿童路线以及可旋转的家长路线，共享44点最低目标，VoiceOver 标签和公告，Reduce Motion，左撇子书写，Reduced Sound，以及Calm Rescue；物理辅助功能接受仍然开放 |
|平台|带有官方Tada Words和Pawgoo标志的1.8秒品牌发布页面，带有Apple Speech备用功能的离线优先Katie教师音频，捆绑的Aurora发布/过渡，我之后重复的钥匙扣语音印记，基于目标的信息的Vision手写识别，本地通知，本地JSON快照，仅限设备LocalQA，并明确启用的CloudKit家庭同步|

## 建筑物

Swift 包将学习策略与 SwiftUI 和 Apple 框架分开。

|模块|责任|
|---|---|
| `TadaWordsDomain` | 实体、价值对象和服务合同 |
| `TadaWordsLearning` | 规划、审查、评分、节奏和掌握规则 |
| `TadaWordsContent` | 单词导入/OCR 解析，池，持久性，调度，同步记录和奖励 |
| `TadaWordsDesignSystem` | 共享的儿童和Guardian组件和视觉代币|
| `TadaWordsFeatures` | Profiles，大厅，Read，Write，结果，世界和收藏|
| `TadaWordsGuardianFeatures` | 父门，设置，设置，报告，更正和同步控制 |
| `TadaWordsApplePlatform` | 语音、视力、音频、钥匙链、通知和 CloudKit 适配器 |
| `TadaWordsAppShell` | 生产构成和本地优先引导 |

iOS目标取决于`TadaWordsAppShell`、`TadaWordsApplePlatform`和`TadaWordsDomain`。软件包目标声明强制执行剩余的边界。Read [ARCHITECTURE.md](ARCHITECTURE.md)用于依赖规则和数据流。

## 要求

- macOS与Xcode和一个iOS 18或更新的SDK
- Swift 6
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)用于项目再生
- 一个免费的Apple Account，用于直接LocalQA在个人设备上安装
- 一个为 TestFlight 和 CloudKit 接受提供付费的 Apple Developer Program 团队

当前 v0.7.39 源候选版本使用 Xcode 26.6。合并后的 v0.7.2 通过了 exact-HEAD iPhone/iPad 模拟器矩阵、LocalQA 安装保护和数据保留的实体 iPhone 更新；合并后的 v0.7.3 增加了离线 Parent 通知和精确内容验证。Family Sync 生产 schema、签名跨设备共享/删除、人工可访问性和精确发布隐私/网络验收仍未完成。

## 构建和测试

```sh
git clone https://github.com/darrenfu/tadawords.git
cd tadawords

brew install xcodegen
make generate
make check
open TadaWords.xcodeproj
```

`make check`执行严格的Swift格式化检查、Swift软件包测试套件、Issue代理检查和发布候选人飞行前故障模式测试。接受的V1基线包含**367个测试，零失败**。合并后的v0.2包含**480个**，v0.3包含**548个**，v0.3.1和v0.4.1包含**595个**，v0.5包含**619个**，v0.5.1包含**638个**，v0.6.0包含**641个**，v0.6.1包含**643个Swift测试加上14个Issue代理测试**，所有测试均零失败。v0.7.0源批次通过了**814个Swift测试加上14个Issue代理测试**。合并后的v0.7.2通过了**821个Swift测试、40个Issue代理测试和11个发布飞行前测试**；合并后的v0.7.3通过了**822个Swift测试，自动化/飞行前计数相同；v0.7.4通过了**834个Swift测试；v0.7.5通过了**837个Swift测试；v0.7.6通过了**998个Swift测试、40个Issue代理测试和11个发布飞行前测试**；v0.7.7添加了五个生产APN案例，用于**16个发布飞行前测试**；v0.7.8预提交源门禁通过了**1,016个Swift测试、40个Issue代理测试以及这些**16个发布飞行前测试。合并后的v0.7.11通过了**1,119个Swift测试、91个Issue代理测试和18个发布飞行前测试**。v0.7.12源门禁通过了**1,119个Swift测试、91个Issue代理测试和54个发布/身份验证器测试**；确切的已提交HEAD模拟器和签名凭证证据分别记录。单独的物理设备目标调用公共生产手写服务，但不使用演示识别器。有关规范的签名存档/导出验证命令，请参阅[`Docs/RELEASE_CANDIDATE_PREFLIGHT.md`](Docs/RELEASE_CANDIDATE_PREFLIGHT.md)。

在安装在iPhone或iPad上之前，请运行设备准备脚本：

```sh
./Scripts/verify-device-readiness.sh
```

每个物理发布批次构建也嵌入了其Git提交。在安装已签名的LocalQA应用程序之前，请验证捆绑包与保留的版本、构建、提交和捆绑包ID相匹配：

```sh
./Scripts/verify-signed-app-identity.sh \
  '/path/to/Tada Words QA.app' \
  0.7.39 2026072413 "$(git rev-parse HEAD)" com.tadawords.app.localqa
```

对于正常的PawGoo开发人工制品，请使用更严格的无安装门槛：

```sh
./Scripts/verify-pawgoo-development-app.py \
  '/path/to/Tada Words.app' \
  0.7.39 2026072413 "$(git rev-parse HEAD)" \
  --device-udid 'APPROVED_IPHONE_HARDWARE_UDID' \
  --device-udid 'APPROVED_IPAD_HARDWARE_UDID'
```

这些值是配置配置文件中列出的硬件UDID，而不是`xcrun devicectl`接受的CoreDevice UUIDs。命令打印已验证的应用程序树SHA-256；安装车道必须在使用序列化工件之前重新检查该摘要。

本地[Issue代理](Automation/issue-agent/README.md)可以按优先级、批次相关模块工作优先取走准备好的GitHub Issue，并停止处理人力产品、设备和合并门。除非所有者明确启用，否则其重复调度器将被禁用。

有关签名、开发者模式和直接安装，请遵循[DEVICE_DEPLOYMENT.md](DEVICE_DEPLOYMENT.md)。

## 数据和隐私

- 该应用程序将儿童配置文件、单词池、任务历史记录和设置存储在本地 JSON 快照中。
- PawGoo普通捆绑件`app.tadawords.app`有一个新的iOS沙盒、权限状态和默认密钥串组。它无法读取、替换或迁移单独的`com.tadawords.app.localqa`数据。普通应用程序安装等待#60的旧普通库存；语音设置和操作系统权限是设备本地化的，必须为新普通应用程序建立。
- 该应用程序不运行应用程序拥有的服务器数据库。
- 语音和注册音频缓冲区会保留在内存中。该应用程序不会保存或上传原始子录音。
- 语音设置随机打乱六句简短的幼儿园前段句子，供孩子听并重复。每个设备只在钥匙串中存储生成的语音指纹模板。CloudKit不同步模板，因此每个设备都需要单独注册。真正的全新安装会获得随机Profile身份，在创建任何本地数据之前，只清除Tada Words保留的语音指纹钥匙串服务；普通升级会保留注册的模板，失败的重置会失败，以安全重试。
- 练习使用一个标准教师语音合同，而不是每个Profile风格选择器。一个版本的离线包涵盖了500个单词，Katie是标准语音，并为`bun`提供了一个明文记录的Aurora质量覆盖。其他单词使用已安装的最清晰的兼容的美国英语Apple语音。Aurora启动和过渡剪辑也随附。应用程序中不存在Cartesia API密钥或运行时Cartesia请求。
- Pool导入只预加载儿童安全的混凝土单词图片目录。所有74个独特的Twemoji PNG都与应用程序捆绑在一起，因此新的离线安装不需要CDN请求。抽象单词没有图片映射。
- Parents可以在Parent Gate后打开离线第三方通知，以查看确切的Twemoji源代码、修改状态、版权归属和CC BY 4.0许可证。
- 发布构建默认情况下保持iCloud家庭同步关闭。完成入职不会启用它；父组件必须在Guardian设置中明确打开它。
- 关闭家庭同步可防止以后的整个生命周期、手动、邀请和访问管理同步呼叫。从设计上讲，选择退出不会删除已经上传的记录；Profile删除是单独的删除操作。
- APN注册诊断仅限于流程，并仅限于最新的未请求、待处理、已注册或粗略失败状态及其时间戳。UIKit在回调边界处丢弃不透明的设备令牌；应用程序从不保留、打印、哈希、持久化或导出它。通知呈现权限不用于推断静默的CloudKit注册成功。
- Profile删除首先会启动墓碑和设备本地擦除生命周期，然后清除本地学习数据、提醒、本地语音指纹和分阶段照片来源。父级UI只暴露匿名汇总状态。完成需要在所有者路径移除其Profile区域/数据包资产后进行确切的墓碑修订，或参与者路径完成离开/撤销；帐户来源阻止其他Apple帐户承认此操作。目前唯一剩余的Profile无法删除，也没有完整的删除所有应用程序数据路径。Issue #19拥有该空白以及签名的生产破坏性证明。
- 版本化的 [App Store 隐私库存](Docs/APP_STORE_PRIVACY_v0.7.4.md)
将每个经过审计的运行时流程映射到其设备/网络边界，并记录提交前所需的所有者证明和Pawgoo副本更改。
- [系统权限清单](Docs/SYSTEM_PERMISSION_INVENTORY_v0.7.8.md)
列出每个请求 API 和入口点。Read 中第一次点击麦克风可以依次请求尚未确定的 Speech Recognition 和 Microphone 权限；拒绝、受限或被撤销的状态会关闭失败并显示 Ask a Parent 恢复路径。发布前仍需要精确设备矩阵。

语音指纹提供了一种信心信号。它不能证明只有所选的儿童说话。生产使用需要代表性的同一个儿童和不同说话者的测试。

`TadaWordsLocalQA`方案安装了一个明显不同的**Tada Words QA**应用程序，其捆绑ID为`com.tadawords.app.localqa`。它没有iCloud权利，不宣传CloudKit共享，并且只在该设备上保存数据。其本地数据与发布应用程序是分开的，不会同步到其他设备。

模拟器构建还使用确定性本地测试传输。在开发人员配置`iCloud.com.tadawords.app`、设备签名到iCloud，以及父组件选择加入后，一个正常的签名物理设备发布构建才能使用CloudKit。仅限生产访问UI使用Apple现有的共享控制器，对于被撤销、删除或格式错误的路由，关闭失败。在使用家庭数据时，生产模式、共享、后台交付和破坏性擦除仍然需要签名设备接受才能发布使用。

## 验证状态

|检查|结果|
|---|---|
|严格Swift格式杂毛|通过|
| 版本和构建 | 源 Plist 与生成项目设置中的 v0.7.39（`2026072413`） |
| Swift 测试 | v0.7.39 新增数据保留的生产安装契约，并保留孩子场景权限顺序、重叠/取消保护、隐私和发布契约；必须在不可变的发布 HEAD 上重跑完整 source gate |
| 家庭同步物理差分 | 正常 PawGoo v0.7.18 已安装在批准的 iPhone 和 iPad 上；一个 iPhone 创建的测试 Profile 自动收敛到未触碰的 iPad，无需打开家庭同步，每侧总共有一个匹配记录和四个 Profile |
| 家庭同步模拟器E2E |合并v0.7.2：6/6在iPhone 17 Pro Max和6/6在iPad Pro 13英寸（M5），iOS 26.5 |
| 关键 XCUITest 流程 | 合并 v0.7.2：完整的关键矩阵通过 iPad；单个 iPhone 照片-拒绝时间案例在合并运行后在孤立的新重播中通过了 2/2，其余每个流程都通过了 |
| 第三方通知 | 家长门禁离线文本、准确归因、来源/许可证链接和路由测试通过；专注的UI流程在iPhone 17 Pro Max上通过1/1，在iPad Pro 13英寸（M5）上通过1/1，iOS 26.5 |
|数据保留升级|合并v0.7.2安装在物理iPhone上，并到达了现有的Profile选择器；2 Profiles、201个单词池条目、488个规范尝试和62个衍生进度行仍然存在|
| 家长隐私/支持 XCUITest | v0.6.1 重点流程：1/1 通过了 iPhone 17 Pro Max 和 1/1 通过了 iPad Pro 13 英寸模拟器 |
| 主页 | 返回导航，世界主题，共享触觉组件，并减少通过目标模拟器验证的副本 |
| 启动页面 | 1.8秒起步，官方Tada Words和Pawgoo标志，温暖的本地启动颜色，倒计时前音频序列化，捆绑的语音品牌签名，以及通过模拟器测试的渐变策略；物理听觉质量保证待定|
| `of` 手写恢复 | 三级证据聚合，10个候选人检查，混合案例词汇，六种像孩子一样的积极风格，目标对齐 `0` → `o` 使用真实Vision `0f` 固定装置的归一化，30个配对邻居控制，跨级证实，以及 `off` 否决通过了自动测试；儿童手写待定 |
| 物理 iPhone 生产 视觉 | 2/2 设备测试通过：6/6 `of/go` 病例变体和 4/4 阴性对照；仅合成载体 |
| 物理 iPad 生产 视觉 | 2/2 设备测试通过：错误单词拒绝和 `of/go` 案例变体；仅限合成向量 |
| 物理 iPad 关键 XCUITest | 7/7 通过：OCR 添加全部、删除全部/恢复、明确预设批准、顺序删除/排序、照片选择器/排序，以及 Read/Write 完成取消 |
| iPhone 17 Pro Max LocalQA 模拟器 | Fresh v0.5.1 构建 `2026071501`；关键 XCUITest 矩阵 9/9 通过 |
| iPad Pro 13英寸（M5）LocalQA模拟器| Fresh v0.5.1构建`2026071501`；关键XCUITest矩阵9/9通过|
| 连接 iPhone 17 Pro Max | 独特的v0.5.1（`2026071504`）软件包已签名并准备就绪，但在安装前手机无法使用；重新连接它，然后在儿童`of`/`0f`、音频、旋转和可访问性接受|之前安装/库存验证
| Darren的读取 iPad Air 11英寸（M2），iPadOS 26.5.2 | 团队 `6S245NCUPQ` 签署 `Tada Words QA` v0.5.1（`2026071504`）安装和库存验证；启动正在等待设备解锁，然后子/父设备接受仍然为|
| Darren iPad Air 13英寸（M4），iPadOS 26.5 | 配置包括设备，但其配对的Wi-Fi隧道在更正的`2026071504`软件包安装之前超时；唤醒/解锁或重新连接它，然后在接受前安装和库存验证|
| 学前视觉层次结构 | v0.2 Profile，大厅，Read，以及结果捕获在两个模拟器中传递；物理儿童，VoiceOver，和Dynamic Type接受仍然开放 |
|基于路线的定向 | v0.2 Plist和运行时策略检查通过。iPad模拟器窗口形状显示 Parents旋转，而子路由保持为横向。原始 iPhone 模拟器帧缓冲区捕获不确定，因此物理旋转仍然打开。|
| 持续，默认关闭 CloudKit 监护人选择加入 | 实施；实时设备接受开放 |
| CloudKit 访问管理 | 生产所有者/参与者路线和核对实施；签署所有者移除、参与者休假和撤销接受开放 |
| CloudKit 远程擦除 | 持久生命周期，准确的所有者/参与者处置，崩溃修复，重试，终端完成和帐户来源测试通过；仅生产破坏性测试证明开放 |
| 身体儿童的语言、手写、音频、可访问性以及CloudKit | 接受开放|

[功能审计](QAArtifacts/FULL_FEATURE_AUDIT_2026-07-12.md)记录合并后的 v0.2 实施证据。[后续日志](FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md)记录到 v0.7.32 为止的运行时更改，[V1 backlog](V1_BACKLOG.md)列出剩余的设备与人工验收工作。

## 测试固定装置归属

该存储库包含一个未修改的子语音固定件，来自[OpenSLR SLR101, speechocean762](https://www.openslr.org/101/) under CC BY 4.0。Read其[源代码和许可证记录](Tests/Fixtures/ChildSpeech/LICENSE_SOURCE.md)和[SHA-256校验和](Tests/Fixtures/ChildSpeech/SHA256SUMS)。该应用程序不打包此测试文件。

## 记录

- [产品和交互设计](TADA_WORDS_V1_PRODUCT_DESIGN.md)
- [设计审查](TADA_WORDS_DESIGN_REVIEW.md)
- [后续错误修复和改进](FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md)
- [V1接受清单](MVP_ACCEPTANCE.md)
- [物理设备部署](DEVICE_DEPLOYMENT.md)
- [语音指纹设备Alpha计划](VOICEPRINT_DEVICE_ALPHA.md)
- [预设单词目录](Docs/TADA_WORDS_PRESET_CATALOG.md)
- [App Store 隐私库存](Docs/APP_STORE_PRIVACY_v0.7.4.md)
- [App Store提交包](Docs/APP_STORE_SUBMISSION_PACK_v0.7.5.md)
- [视觉和可访问性审计](QAArtifacts/DESIGN_AUDIT_2026-07-12.md)
- [第三方通知](THIRD_PARTY_NOTICES.md)
- [App Store 内容版权库存](Docs/APP_STORE_CONTENT_RIGHTS.md)

## 许可证

项目源文件不包括开源许可证。版权仍归项目所有者所有。第三方材料保留其[第三方通知](THIRD_PARTY_NOTICES.md)或归属文件中声明的版权和许可证。
