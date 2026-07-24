# App Store submission pack — v0.7.5

> **Status: internal draft — do not publish or paste into App Store Connect.**
>
> This pack records copy and capture instructions only. Version `0.7.5` and
> build `2026071905` identify this documentation candidate; they do not identify
> an accepted signed release candidate. Family Sync is required for Tada Words
> 1.0, but its production CloudKit, physical-device, and human acceptance remain
> gated.
> Kids age band, price, storefront availability, DSA status, and release method
> also remain behind the human gates linked below.

## Audit identity

| Item | Audited value |
|---|---|
| Metadata-pack version | `0.7.5` |
| Reserved build | `2026071905` |
| Runtime source baseline | `ce479db21eba64bd6abcd0aba739c222dfabb6a9` (`origin/main` after the merged privacy inventory) |
| Behavior delta in this draft | None; metadata, release identity, documentation, and contract tests only |
| Bundle ID expected for the eventual store build | `app.tadawords.app` on PawGoo LLC Team `7R78Q4HP86` |
| Primary localization drafted here | English (U.S.) |
| Merged evidence inputs | [`APP_STORE_PRIVACY_v0.7.4.md`](APP_STORE_PRIVACY_v0.7.4.md) and [`APP_STORE_CONTENT_RIGHTS.md`](APP_STORE_CONTENT_RIGHTS.md) |
| Public-site audit | Live Pawgoo routes rechecked July 19, 2026; content mismatches remain documented below |
| Apple requirements checked | July 19, 2026 |

The source baseline is a traceable integration point, not the approved 1.0
release candidate. It includes the Family Sync source contract, forward
persistence recovery, the current privacy inventory, and the current
content-rights inventory. It does not prove production
CloudKit schema, real sharing, remote erasure, physical-device convergence, or
human acceptance. Before any copy or image is uploaded, replace this baseline
with the exact archive commit and repeat the claim checks in this document.
Issue [#22](https://github.com/darrenfu/tadawords/issues/22) owns exact-RC
iPhone/iPad acceptance and issue
[#26](https://github.com/darrenfu/tadawords/issues/26) owns the human-gated
TestFlight, submission, and release sequence.

### Remaining evidence gates — do not silently promote

The following values are deliberately not represented as accepted. They must
be replaced with exact signed-release evidence during submission preparation:

- **Exact archive commit, bundle identity, and signing identity:** verify the
  signed release archive; do not infer them from this source-document version.
- **Final App Privacy answers:** start from the merged privacy inventory, then
  repeat its exact-build, CloudKit, Pawgoo-access, support-retention, and traffic
  gates before entering answers in App Store Connect.
- **Content-rights representation and copyright:** start from the merged
  content-rights inventory. Current Cartesia evidence covers only its recorded
  pack; reconcile the exact retained audio/provider terms and obtain the Pawgoo
  ownership-chain attestation in #33 before submitting a representation.
- **Family Sync reviewer steps and public claim:** add only after #19/#41 pass
  against production CloudKit and the exact signed release candidate.
- **Pawgoo wording:** issue #54 owns alignment and deployment evidence for the
  public Privacy and Support pages; this document does not change the site.
- **Child permission flow:** the v0.7.8 source candidate gives child Read only a
  current-status check and adds Parents → App & Family → Speech & Microphone for
  setup. Issue #55 still requires exact signed first-install, denied,
  authorized, and revoked verification on iPhone and iPad before these steps are
  paste-ready. See the
  [shipping permission inventory](SYSTEM_PERMISSION_INVENTORY_v0.7.8.md).

Until every gate above is satisfied, this file is a metadata candidate, not an
accepted release candidate or an App Store Connect checklist that is safe to
execute.

## Decisions and gates

| Decision | Current treatment in this draft | Human gate |
|---|---|---|
| Made for Kids and age band | **Unresolved.** Do not select an age band. The base copy avoids the reserved phrases “For Kids” and “For Children.” | [#24](https://github.com/darrenfu/tadawords/issues/24) |
| Price | **Unresolved.** No free/paid claim appears in copy or screenshots. | [#24](https://github.com/darrenfu/tadawords/issues/24) |
| Family Sync in 1.0 | **Resolved: required.** The source contract is present in the audited baseline, but public availability, sharing, convergence, revocation, and remote-erasure claims remain blocked until exact-RC production acceptance. | [#40](https://github.com/darrenfu/tadawords/issues/40), [#19](https://github.com/darrenfu/tadawords/issues/19), [#41](https://github.com/darrenfu/tadawords/issues/41) |
| Storefronts | **Unresolved.** No country or region is presumed. | [#24](https://github.com/darrenfu/tadawords/issues/24), [#23](https://github.com/darrenfu/tadawords/issues/23) |
| EU DSA trader status and displayed contact data | **Unresolved.** Do not infer from the public website. | [#23](https://github.com/darrenfu/tadawords/issues/23) |
| Release method | **Unresolved.** Manual, automatic, and phased release remain unselected. | [#24](https://github.com/darrenfu/tadawords/issues/24), [#26](https://github.com/darrenfu/tadawords/issues/26) |
| Exact RC and device acceptance | **Unresolved.** Captures must come from the accepted signed RC, not this documentation branch by default. | [#22](https://github.com/darrenfu/tadawords/issues/22) |
| Kids permission requests | **Source fixed; exact-device gate open.** Child Read has no request capability. The review path starts behind the Parent Gate at App & Family → Speech & Microphone, but first-install, denied, authorized, and revoked behavior still needs exact signed iPhone/iPad acceptance. | [#55](https://github.com/darrenfu/tadawords/issues/55), [permission inventory](SYSTEM_PERMISSION_INVENTORY_v0.7.8.md) |
| App Privacy answers | **Merged inventory; conditional answer set.** The source-backed inventory covers bundled picture hints, Family Sync, device-local data, support/export flows, the privacy manifest, and every configured or dormant network path. Exact signed-build and operating-practice gates remain. | [`APP_STORE_PRIVACY_v0.7.4.md`](APP_STORE_PRIVACY_v0.7.4.md), [#17](https://github.com/darrenfu/tadawords/issues/17), [#54](https://github.com/darrenfu/tadawords/issues/54) |
| Shipped-content rights | **Merged inventory; final release evidence blocked.** Twemoji provenance and in-app attribution are present. Cartesia account/tier evidence is preserved only for the recorded current pack; every retained generated-audio asset must be reconciled at exact RC. Pawgoo authorship/rights-chain attestation remains open. | [`APP_STORE_CONTENT_RIGHTS.md`](APP_STORE_CONTENT_RIGHTS.md), [#32](https://github.com/darrenfu/tadawords/issues/32), [#33](https://github.com/darrenfu/tadawords/issues/33) |

Apple states that a Made for Kids selection cannot be changed after approval,
and subsequent updates must continue to follow the Kids Category rules. This
pack therefore does not choose an age band by implication.

## Draft App Store metadata

All character and byte counts below use the exact English text shown. The
limits come from Apple's current App Store Connect reference.

| Field | Draft value | Count / state |
|---|---|---|
| App name | `Tada Words` | 10 characters; limit 30 |
| Subtitle | `Personal sight-word practice` | 28 characters; limit 30 |
| Primary category | `Education` | Draft category; verify at exact-RC preflight |
| Secondary category | Leave blank | Draft; do not add Games merely for discoverability |
| Promotional text | `Turn school word lists into short Read and Write quests, with photo import, separate word libraries, and adaptive review for each learner.` | 138 characters; limit 170 |
| Keywords | `sight words,reading,spelling,handwriting,vocabulary,school,practice,word lists,early literacy` | 93 UTF-8 bytes; limit 100 bytes |
| Marketing URL | `https://pawgoo.app/en/tadawords` | Live audit: HTTP 200 |
| Support URL | `https://pawgoo.app/en/support` | Live audit: HTTP 200; legal-contact sufficiency remains part of #23 |
| Privacy Policy URL | `https://pawgoo.app/en/tadawords/privacy` | Live audit: HTTP 200 |
| Copyright | `2026 Pawgoo LLC` | **Provisional — do not enter until #33 confirms the Pawgoo ownership/rights chain.** Apple adds the copyright symbol automatically |
| Price | **UNRESOLVED — #24** | Do not enter from this pack |
| Availability | **UNRESOLVED — #23/#24** | Do not select storefronts from this pack |

### Description

```text
Tada Words turns the exact sight words you choose into short, focused reading and writing practice.

BUILD PERSONAL WORD LIBRARIES
Type words one at a time or import a photo of a school list. Review every detected word before adding it to separate Read and Write libraries for each profile.

PRACTICE IN TWO WAYS
Read quests keep the word visible while the learner says it aloud. Write quests play the word and offer a choice of handwriting or an in-app letter keyboard.

REVIEW WHAT NEEDS WORK
Adaptive spaced review prioritizes due and difficult words using recent attempts, help, retries, and pace.

PROFILES FOR EACH LEARNER
Create separate profiles with their own words, progress, settings, worlds, and rewards. Tada Words supports iPhone and iPad.

PARENT-CONTROLLED SETUP
Word management, progress reports, reminders, profile controls, and app settings stay inside a protected Parent area.

PRIVATE BY DESIGN
Core practice is offline-first. Tada Words contains no advertising or third-party analytics. Raw speech recordings are not saved or uploaded to Pawgoo. Speech, camera, photo, and handwriting recognition use Apple frameworks on the device. Teacher-word audio comes from the app bundle or offline Apple speech; no runtime teacher-audio endpoint is configured.

Learn more at pawgoo.app/en/tadawords.
```

Family Sync is required 1.0 scope, not an unresolved product option. It remains
absent from the paste-ready description above only because #19/#41 production
acceptance, the privacy inventory's exact-release gates, and matching public-site
copy are not complete. Add a source-backed Family Sync paragraph after those
gates pass; do not describe the feature as optional release scope or imply
tested remote erasure before the evidence exists. Do not add “for kids,” “for
children,” or an age range unless #24 selects Made for Kids.

## Draft App Review information

The reviewer contact fields require a real organization contact and are not
filled with invented personal data.

| Field | Draft value |
|---|---|
| Contact first name | **HUMAN ENTRY — #23/#26** |
| Contact last name | **HUMAN ENTRY — #23/#26** |
| Contact phone | **HUMAN ENTRY — #23/#26** |
| Contact email | **HUMAN ENTRY — #23/#26** |
| Sign-in required | `No` for the app's core review path; Tada Words has no Pawgoo account or login. Family Sync separately requires parent opt-in and an available iCloud account |
| Demo username/password | Not applicable for core practice; do not create a Pawgoo reviewer account. Provide verified iCloud/Family Sync steps in the gated appendix instead |

### Base Notes for Review

> **Working draft.** Recheck every sentence against the exact signed RC. Remove
> the bracketed preflight instruction before pasting. Apple's Notes field is
> limited to 4,000 characters.

```text
Tada Words is a local-first sight-word practice app for iPhone and iPad. [Before submission, confirm the selected Kids Category/age-band decision from issue #24.] Core practice requires no Pawgoo account or login. Parent-opted-in Family Sync requires an available iCloud account. This build contains no advertising, third-party analytics, or in-app purchases.

FIRST-LAUNCH PATH
1. Complete the parent onboarding and create a fictional profile. No email address or phone number is requested.
2. At “Who’s playing?”, select the profile to reach the Read and Write quest lobby.

PARENT GATE AND WORD IMPORT
1. At “Who’s playing?”, tap “Parents.”
2. Solve the multiplication question shown on screen. The Parent area unlocks automatically when the answer is correct; there is no fixed passcode.
3. Open “Words & Practice” → “Manage Words.” A parent can type words, choose word-sheet photos, or take a photo. Every recognized word is shown for review before it can be added to the Read or Write pool.

READ PATH
1. Return to the profile and choose “Read.”
2. [BLOCKED BY ISSUE #55 EXACT-DEVICE ACCEPTANCE — in Parents, open App & Family → Speech & Microphone and choose Set up access; verify the separate Speech Recognition and Microphone rows are Ready, then return to Read practice. Never instruct the reviewer to grant either permission from a child screen.]

WRITE PATH
1. Return to the lobby and choose “Write.”
2. Choose “Write by Hand” or “Spell with Letters.” Handwriting recognition uses Apple Vision on the device; the letter option uses the app’s own A–Z keyboard.

PERMISSIONS
Do not paste this proposed permission guidance until issue #55's exact signed build is verified. Speech and Microphone setup begins only after the Parent Gate under App & Family → Speech & Microphone; child Read only checks existing status and fails closed. Camera or Photos access is requested only after a parent chooses the corresponding import/profile-photo action. Notifications are optional and managed in the Parent area. Face ID may be requested only for a sensitive parent action present in the exact release candidate. The complete ownership list is in `SYSTEM_PERMISSION_INVENTORY_v0.7.8.md`.

OFFLINE BEHAVIOR
Core Read and Write practice, bundled presets, teacher-word audio, speech recognition, and handwriting recognition are designed to work without a network connection. Raw speech recordings are not saved or uploaded to Pawgoo.

No special hardware, external accessory, purchase, subscription, or demo credential is required for the core review path.
```

### Required Family Sync review appendix — blocked from paste

Family Sync will ship in 1.0, but this appendix must not be pasted until #19 and
#41 pass against the exact production CloudKit configuration and signed RC.
The placeholder below records the required review surface without claiming it
has passed:

```text
FAMILY SYNC — PENDING EXACT-RC PRODUCTION ACCEPTANCE
Replace this placeholder with verified reviewer steps for parent opt-in, the required available iCloud account, same-account sync, caregiver share acceptance, offline convergence, access revocation, and test-only Profile deletion. Cite the exact signed build and acceptance artifact. Do not promise complete in-app or remote erasure until the destructive production test and final-Profile/delete-all flow have passed.
```

The final appendix must match the accepted UI labels and the merged privacy
inventory. A complete deletion or remote-erasure promise is prohibited until
#19 supplies both final-Profile/delete-all behavior and exact-RC destructive
evidence.

## Screenshot production plan

Apple currently accepts one to ten screenshots per device family in JPEG, JPG,
or PNG, with no alpha channel. Tada Words runs on both iPhone and iPad, so both
sets are required. Use actual app UI from the same signed RC accepted in #22.

### Exact capture targets

| Store well | Simulator / capture orientation | Required output used by this plan | Format |
|---|---|---|---|
| iPhone 6.9-inch | iPhone 17 Pro Max, landscape | `2868 × 1320` pixels | PNG, RGB, no alpha |
| iPad 13-inch | iPad Pro 13-inch (M4 or current equivalent), landscape | `2752 × 2064` pixels | PNG, RGB, no alpha |

Apple also accepts other listed resolutions for these wells, but this batch
chooses one exact size per family so the capture pipeline cannot silently mix
assets. Preserve the entire app viewport; do not stretch a smaller capture.

### iPhone sequence

| Order | Exact scene and state | Optional overlay copy | Claim demonstrated |
|---|---|---|---|
| 1 | “Who’s playing?” with two fictional icon-only profiles; `Mia` is marked as last played | `A space for every learner` | Separate profiles |
| 2 | Parent → Words & Practice → Manage Words → “Review scanned words,” showing the generated practice sheet results before import | `Snap a list. Approve every word.` | Photo import with parent review |
| 3 | Read quest before assistance, with the fictional pool word `where` centered and the microphone action visible | `See it. Say it.` | Read practice |
| 4 | Write quest using “Write by Hand,” with a partial fictional attempt for `play` | `Hear it. Write it your way.` | Handwriting option |
| 5 | Quest result after a completed fictional session, with ordinary progress and no perfect-score claim | `Short practice. Useful review.` | Completion and saved progress |

### 13-inch iPad sequence

| Order | Exact scene and state | Optional overlay copy | Claim demonstrated |
|---|---|---|---|
| 1 | Profile lobby showing the separate Read and Write quest cards for `Mia` | `Two focused ways to practice` | Read/Write structure and iPad layout |
| 2 | “How do you want to spell?” with both “Write by Hand” and “Spell with Letters” visible | `Write by hand or spell with letters` | Two Write inputs |
| 3 | Parent word manager with separate Read and Write pools populated from the fictional list | `Your words, organized your way` | Multiple word libraries |
| 4 | Parent progress report for the fictional profile with a mix of independent, helped, and due words | `See what needs practice next` | Parent progress visibility |
| 5 | Read quest or quest result in a different world from the iPhone set, with controls fully inside safe areas | `Practice that fits the family screen` | iPad support and world presentation |

The first three images in each set carry the strongest product story. If only
three are produced for an early review draft, use orders 1–3; the submission
may contain up to ten.

### Fictional-data contract

Every capture must satisfy all of the following:

- Use only the fictional nicknames `Mia` and `Leo`; do not use a real child's
  name, initials, photo, voice sample, handwriting sample, or learning history.
- Use built-in avatar illustrations. Do not use a person photograph, even a
  stock child image.
- Use the generated word sheet title `Practice words` with only these generic
  words: `the`, `said`, `where`, `come`, `play`, and `little`.
- Generate the sheet locally without a school name, teacher name, class,
  address, logo, date, QR code, barcode, or document metadata from a real file.
- Seed progress through a deterministic screenshot fixture or normal app use.
  Do not paint numbers into the screenshot or represent an unavailable state.
- Keep Apple IDs, email addresses, phone numbers, device names, notification
  banners, photo-library thumbnails, location, carrier details, and calendar
  events out of frame.
- Use an exact-RC build with demo/debug-only controls absent. The Debug OCR
  fixture described in `Tests/TadaWordsUITests/README.md` must not appear.
- If explanatory overlays are added, retain an untouched raw capture beside
  each composed asset and ensure the overlay does not cover required controls
  or promise unresolved functionality.

Apple requires screenshots to show the app in use and recommends fictional
account information instead of data from a real person. A splash screen or
website mockup is not a substitute for any scene above.

## Claim-to-source map

Only claims with a present source path are included in the base metadata. The
exact RC preflight must confirm that these symbols and tests still apply.

| Public/reviewer claim | Runtime source | Automated evidence | Gate or caveat |
|---|---|---|---|
| Parents can type words or import word-sheet photos and review recognized words before adding them | [`GuardianQuickAddView.swift`](../Sources/TadaWordsGuardianFeatures/GuardianQuickAddView.swift) (`GuardianWordManagerView`); [`AppleImageTextRecognitionService.swift`](../Sources/TadaWordsApplePlatform/AppleImageTextRecognitionService.swift); [`ManualWordBatchParser.swift`](../Sources/TadaWordsContent/ManualWordBatchParser.swift) | [`TadaWordsCriticalFlowUITests.swift`](../Tests/TadaWordsUITests/TadaWordsCriticalFlowUITests.swift); [`AppleImageTextRecognitionTests.swift`](../Tests/TadaWordsApplePlatformTests/AppleImageTextRecognitionTests.swift); [`ManualWordBatchParserTests.swift`](../Tests/TadaWordsContentTests/ManualWordBatchParserTests.swift) | Real Camera/Photos/Vision transfer still needs #22 device acceptance |
| Separate Read and Write libraries exist for each Profile | [`RepositoryGuardianWordStore.swift`](../Sources/TadaWordsGuardianFeatures/RepositoryGuardianWordStore.swift); [`LocalJSONWordPoolRepository.swift`](../Sources/TadaWordsContent/LocalJSONWordPoolRepository.swift); [`GuardianQuickAddView.swift`](../Sources/TadaWordsGuardianFeatures/GuardianQuickAddView.swift) | [`RepositoryGuardianWordStoreTests.swift`](../Tests/TadaWordsGuardianFeaturesTests/RepositoryGuardianWordStoreTests.swift); [`LocalJSONWordPoolRepositoryTests.swift`](../Tests/TadaWordsContentTests/LocalJSONWordPoolRepositoryTests.swift) | Capture only fictional Profiles |
| Multiple Profiles keep separate words, progress, settings, worlds, and rewards on the current device | [`KidProfileRepositories.swift`](../Sources/TadaWordsContent/KidProfileRepositories.swift) (`LocalJSONKidProfileRepository`); [`RepositoryGuardianFamilyStore.swift`](../Sources/TadaWordsGuardianFeatures/RepositoryGuardianFamilyStore.swift); [`ProfileChooserView.swift`](../Sources/TadaWordsFeatures/ProfileChooserView.swift) | [`KidProfileRepositoryTests.swift`](../Tests/TadaWordsContentTests/KidProfileRepositoryTests.swift); [`RepositoryGuardianFamilyStoreTests.swift`](../Tests/TadaWordsGuardianFeaturesTests/RepositoryGuardianFamilyStoreTests.swift); [`TadaWordsAppModelTests.swift`](../Tests/TadaWordsFeaturesTests/TadaWordsAppModelTests.swift) | This row does not claim cross-device acceptance |
| Read quests use speech recognition for spoken practice | [`ReadQuestView.swift`](../Sources/TadaWordsFeatures/ReadQuestView.swift); [`AppleSpeechRecognitionService.swift`](../Sources/TadaWordsApplePlatform/AppleSpeechRecognitionService.swift); [`AppleSpeechPermissions.swift`](../Sources/TadaWordsApplePlatform/AppleSpeechPermissions.swift); [`SYSTEM_PERMISSION_INVENTORY_v0.7.8.md`](SYSTEM_PERMISSION_INVENTORY_v0.7.8.md) | [`AppleSpeechAdapterTests.swift`](../Tests/TadaWordsApplePlatformTests/AppleSpeechAdapterTests.swift); [`ChildSpeechPermissionRouteContractTests.swift`](../Tests/TadaWordsAppShellTests/ChildSpeechPermissionRouteContractTests.swift); [`GuardianSpeechPermissionTests.swift`](../Tests/TadaWordsGuardianFeaturesTests/GuardianSpeechPermissionTests.swift); critical Read UI tests | Child Read now has check-only authorization and Parents owns setup. Issue #55 and #22 still require exact signed first-install, denied, authorized, and revoked iPhone/iPad acceptance before this becomes paste-ready reviewer guidance |
| Write offers handwriting and an in-app letter keyboard | [`WriteInputChooserView.swift`](../Sources/TadaWordsFeatures/WriteInputChooserView.swift); [`WriteQuestView.swift`](../Sources/TadaWordsFeatures/WriteQuestView.swift); [`SpellQuestView.swift`](../Sources/TadaWordsFeatures/SpellQuestView.swift); [`AppleHandwritingRecognitionService.swift`](../Sources/TadaWordsApplePlatform/AppleHandwritingRecognitionService.swift) | [`AppleHandwritingRecognitionTests.swift`](../Tests/TadaWordsApplePlatformTests/AppleHandwritingRecognitionTests.swift); [`SpellQuestTests.swift`](../Tests/TadaWordsFeaturesTests/SpellQuestTests.swift) | Exact-RC device handwriting requires #22 |
| Adaptive spaced review prioritizes due and difficult words from outcomes, help, retries, and pace | [`AdaptiveRetrievalScheduler.swift`](../Sources/TadaWordsLearning/AdaptiveRetrievalScheduler.swift); [`ReviewPriority.swift`](../Sources/TadaWordsLearning/ReviewPriority.swift); [`QuestPlanner.swift`](../Sources/TadaWordsLearning/QuestPlanner.swift) | [`AdaptiveRetrievalSchedulerTests.swift`](../Tests/TadaWordsLearningTests/AdaptiveRetrievalSchedulerTests.swift); [`ReviewPriorityTests.swift`](../Tests/TadaWordsLearningTests/ReviewPriorityTests.swift); [`QuestPlannerTests.swift`](../Tests/TadaWordsLearningTests/QuestPlannerTests.swift) | Public copy says “adaptive spaced review,” not a medical or guaranteed learning outcome |
| Parent controls are behind a multiplication challenge | [`GuardianParentGateView.swift`](../Sources/TadaWordsGuardianFeatures/GuardianParentGateView.swift); [`GuardianRootView.swift`](../Sources/TadaWordsGuardianFeatures/GuardianRootView.swift) | [`GuardianParentGateTests.swift`](../Tests/TadaWordsGuardianFeaturesTests/GuardianParentGateTests.swift); critical Parent UI tests | A parental gate is not itself parental consent under privacy law |
| Privacy Policy, Support, and qualified local data-control guidance are available inside the Parent area | [`GuardianTodayView.swift`](../Sources/TadaWordsGuardianFeatures/GuardianTodayView.swift); [`GuardianRootView.swift`](../Sources/TadaWordsGuardianFeatures/GuardianRootView.swift) | [`GuardianParentNavigationTests.swift`](../Tests/TadaWordsGuardianFeaturesTests/GuardianParentNavigationTests.swift); critical Parent navigation UI tests | Links need a network connection. The sole remaining Profile cannot currently be deleted and there is no final-Profile/delete-all path; #19 must close that gap before complete erasure is claimed. Public copy remains gated by #54 |
| Eligible concrete-word picture hints load from the app bundle without a runtime picture CDN request | [`AppleWordPictureHintService.swift`](../Sources/TadaWordsApplePlatform/AppleWordPictureHintService.swift); [`WordPictureHints.swift`](../Sources/TadaWordsDomain/WordPictureHints.swift); bundled `PictureHints/Twemoji-17.0.3` resources | [`AppleWordPictureHintServiceTests.swift`](../Tests/TadaWordsApplePlatformTests/AppleWordPictureHintServiceTests.swift); [`WordPictureHintTests.swift`](../Tests/TadaWordsDomainTests/WordPictureHintTests.swift); release content inventory | Abstract/ineligible words intentionally have no picture; Twemoji attribution is present and must remain |
| The app targets iPhone and iPad | [`project.yml`](../project.yml) (`TARGETED_DEVICE_FAMILY: "1,2"`); [`AppleInterfaceOrientationController.swift`](../Sources/TadaWordsApplePlatform/AppleInterfaceOrientationController.swift) | [`ResponsiveLayoutPolicyTests.swift`](../Tests/TadaWordsFeaturesTests/ResponsiveLayoutPolicyTests.swift); [`AppleInterfaceOrientationPolicyTests.swift`](../Tests/TadaWordsApplePlatformTests/AppleInterfaceOrientationPolicyTests.swift); critical UI matrix | Store screenshots and #22 acceptance are required for both device families |
| Core practice is offline-first; raw speech recordings are not persisted or uploaded to Pawgoo | [`AppleSpeechRecognitionService.swift`](../Sources/TadaWordsApplePlatform/AppleSpeechRecognitionService.swift); [`BundledTeacherWordAudioProvider.swift`](../Sources/TadaWordsApplePlatform/BundledTeacherWordAudioProvider.swift); [`KeychainDeviceVoiceprintRepository.swift`](../Sources/TadaWordsApplePlatform/KeychainDeviceVoiceprintRepository.swift); [`TadaWordsApp.swift`](../Apps/TadaWordsApp/TadaWordsApp.swift) | [`AppleSpeechAdapterTests.swift`](../Tests/TadaWordsApplePlatformTests/AppleSpeechAdapterTests.swift); [`BundledTeacherWordAudioProviderTests.swift`](../Tests/TadaWordsApplePlatformTests/BundledTeacherWordAudioProviderTests.swift); repository tests | Family Sync requires parent opt-in and an available iCloud account. The remote audio client is dormant: neither shipping plist configures `TadaWordsTeacherAudioEndpoint`, so current teacher audio uses the app bundle or offline Apple speech. Do not call the entire app fully offline |
| No advertising, third-party analytics, or IAP code is present in the audited baseline | [`Package.swift`](../Package.swift) has no external package dependencies; no StoreKit/ad/analytics integration appears in `Apps/` or `Sources/` | Repeat dependency and symbol scan on the exact RC | Final privacy answers remain conditional under the merged inventory and #17; price remains unresolved even without IAP |

The audited baseline also contains the required Family Sync source contract:
versioned CloudKit records, durable local-first outbox/apply state, canonical
Profile and learning facts, locally derived progress/rewards, sharing routes,
and deletion dominance. Core use requires no Pawgoo account, while Family Sync
requires parent opt-in and an available iCloud account. That is source evidence
only. It is deliberately excluded from the paste-ready public/reviewer claims
until the production CloudKit, physical-device, destructive test-only erasure,
final-Profile/delete-all, and human gates pass.

### Claims intentionally excluded pending other work

- **Family Sync availability, sharing, convergence, revocation, or deletion
  guarantees:** the 1.0 decision and source contract are complete, but #19/#41
  production acceptance remains pending.
- **Final App Privacy answers:** the merged inventory is the source of truth,
  but its exact signed-build, operating-practice, CloudKit, support-retention,
  Pawgoo-access, and public-copy gates must pass before submission.
- **All shipped content is fully cleared for every storefront:** the merged
  content-rights inventory is the source of truth, but Cartesia account/tier
  evidence (#32) and Pawgoo authorship/rights-chain attestation (#33) remain.
- **Complete Profile deletion or Delete All App Data:** the Parent area offers
  Profile deletion guidance, but it cannot delete the sole remaining Profile
  and has no complete delete-all reset. Issue #19 owns the required behavior
  and destructive exact-RC proof.
- **Child-facing Speech or Microphone authorization:** the v0.7.8 source moves
  permission setup behind the Parent Gate and removes requesting capability from
  child features. Issue #55 still requires exact-device verification; do not
  paste the proposed reviewer path until that evidence exists.
- **A specific Kids Category age band, price, storefront set, DSA status, or
  release method:** human decisions in #23/#24/#26.
- **“Improves reading,” “proven,” “guaranteed,” or similar outcome claims:** no
  such claim is supported or needed for this submission pack.

## Pawgoo URL and source audit

The three proposed public URLs returned HTTP 200 on July 19, 2026. Reachability
does not mean their content is ready for submission. The live product and
privacy copy still describe the pre-bundling picture-hint network behavior.

| URL | Current source/content finding | Submission consequence |
|---|---|---|
| `https://pawgoo.app/en/tadawords` | Product route exists and describes photo import, separate word libraries, adaptive review, iPhone/iPad, optional parent-controlled Family Sync, and picture-hint downloads | Picture hints are now bundled, so the download/network wording is stale. Family Sync is required 1.0 scope but remains parent opt-in on each device; align availability language only after production acceptance. |
| `https://pawgoo.app/en/tadawords/privacy` | Product privacy route identifies Pawgoo LLC, `privacy@pawgoo.app`, local data, Apple processing, a Twemoji CDN request, and current CloudKit limitations | The Twemoji CDN disclosure no longer matches current app source. Reconcile it with the merged privacy inventory and the accepted Family Sync data flow before submission. |
| `https://pawgoo.app/en/support` | Support route identifies the product, compatibility, developer, `support@pawgoo.app`, and `privacy@pawgoo.app` | It provides working contact email, but #23 must determine any legal address/phone/DSA display obligations for selected storefronts. |

No website change or deployment is part of this draft. Issue #54 owns the
reviewed public-copy change, deployment identity, and live verification. Until
that evidence exists, none of the HTTP-200 results above closes the
content-consistency gate.

## Exact-RC preflight before upload

- [ ] Record the immutable PR/archive commit, version, build, bundle ID, and
      TeamIdentifier; replace the runtime baseline at the top of this pack.
- [ ] Resolve #24 and apply the selected Made for Kids age band or deliberately
      avoid Kids-reserved metadata wording.
- [ ] Treat Family Sync as required 1.0 scope and complete #19/#41 production,
      physical-device, destructive test-only erasure, and human acceptance.
- [ ] Start from the merged App Privacy inventory; verify every SDK, CloudKit
      path, device-local data class, Pawgoo-access practice, support-retention
      practice, and shipping configuration. Confirm that
      `TadaWordsTeacherAudioEndpoint` remains absent.
- [ ] Confirm merged #15/#16 behavior on the exact RC, then reconcile the
      in-app links, product page, privacy policy, support page, review notes,
      bundled picture-hint claim, and offline wording.
- [ ] Start from the merged content-rights inventory; reconcile #32 to every
      retained generated-audio asset and resolve #33 for every asset visible in
      the app and screenshots. Do not enter the provisional Pawgoo copyright
      until #33 passes.
- [ ] Resolve #19 with a final-Profile/delete-all route and production
      destructive evidence before claiming complete in-app or CloudKit erasure.
- [ ] Complete #28's signed iPhone/iPad uninstall/reinstall proof for the
      fail-closed Tada Words voiceprint-service reset, verify that an in-place
      upgrade preserves enrollment, and reconcile final policy/support wording.
- [ ] Complete #54 and verify that the deployed Pawgoo Privacy and Support copy
      matches bundled hints, Family Sync scope, deletion limits, and Keychain
      lifecycle on the exact RC.
- [ ] Resolve #55 so Speech and Microphone authorization setup is Parents-gated;
      verify it on the exact signed iPhone and iPad build, then replace the
      blocked reviewer placeholder with the accepted parent-first steps.
- [ ] Run #22 on the same signed RC used for screenshots.
- [ ] Export iPhone and iPad images at the exact dimensions above and validate
      dimensions, color mode, alpha absence, fictional data, and ordering.
- [ ] Recount name, subtitle, promotional text, description, keywords, and
      Notes bytes after any edits.
- [ ] Confirm Support, Marketing, and Privacy URLs still return 200 and display
      content consistent with the RC.
- [ ] Enter real App Review contact information from #23/#26; never commit it to
      this repository unless the owner explicitly requests that record.
- [ ] Leave upload, Add for Review, Submit for Review, release method, and
      storefront availability to the human-gated #26 workflow.

## Apple primary sources

Only current Apple documentation was used for App Store constraints:

- [App information reference](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
  — 30-character name/subtitle limits, required Privacy Policy URL, Bundle ID,
  content-rights, age-rating, Kids selection, and category fields.
- [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
  — promotional-text, description, keyword, URL, copyright, and Notes limits.
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
  — accepted iPhone/iPad dimensions, one-to-ten count, formats, and no-alpha
  rule.
- [Upload app previews and screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots)
  — device-family wells and screenshot workflow.
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
  — accurate metadata, real app screenshots, fictional account information,
  Kids Category parental gates, privacy, analytics, and advertising rules.
- [Set an app age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating)
  — age questionnaire and the post-approval Made for Kids lock-in.
