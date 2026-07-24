# Tada Words App Store privacy inventory — v0.7.4

**Source baseline:** `6753dd6462b55352ec98b62a725cc6c19cb7f7a5`
(`origin/main`, including merged v0.7.2 recovery, Family Sync, bundled hints,
and v0.7.3 Third-Party Notices)

**Release identity:** version `0.7.4`, build `2026071904`

**Audit date:** 2026-07-19

**Status:** draft for release-owner review; not legal advice and not an App
Store Connect submission

This is the source-backed privacy inventory for the Tada Words 1.0 release
candidate. It replaces the stale v0.6.3 audit from PR #29. The App Store
Privacy answers must be checked again against the exact signed build. A new
dependency, configured endpoint, Pawgoo server access, support workflow, or
retention practice can change the answers even when the user interface does
not change.

## Decision summary

The audited source keeps speech, OCR, handwriting, and
picture-hint lookup on the device. It contains no advertising, analytics,
crash-reporting, or tracking SDK and no third-party Swift package dependency.
The 74-picture Twemoji hint catalog is bundled; the old jsDelivr runtime request
is gone.

The production target contains one configured network feature: parent-opted-in
Family Sync through Apple's CloudKit private/shared databases, with Apple push
notifications used to wake reconciliation. Tada Words has no app-owned account
or database server in this source. A dormant HTTPS teacher-audio client exists,
but `TadaWordsTeacherAudioEndpoint` is absent from both production and LocalQA
configuration, so it is not reachable in the audited build.

The v0.7.8 source candidate adds a check-only child Speech/Microphone boundary
and a Parents-gated setup route. The complete shipping permission ownership
checklist is [`SYSTEM_PERMISSION_INVENTORY_v0.7.8.md`](SYSTEM_PERMISSION_INVENTORY_v0.7.8.md).
This source addendum does not replace the still-required exact signed iPhone and
iPad first-install, denied, authorized, and revoked acceptance.

Family Sync is a required 1.0 capability under the approved product decision in
issue [#18](https://github.com/darrenfu/tadawords/issues/18), but it remains off
by default on every device. A parent must explicitly enable it on each device.
Local practice remains available while sync is off, offline, or recovering.

Do **not** publish App Store Privacy answers yet. The source supports a
conditional **No data collected** draft, but the release owner still needs to
attest the operating practices that source cannot prove, and these release
gates remain open:

1. Deploy and physically accept the production CloudKit schema, sharing,
   background delivery, and test-only destructive erasure in issue
   [#19](https://github.com/darrenfu/tadawords/issues/19).
2. Physically verify the implemented fail-closed Keychain cleanup across a
   signed uninstall/reinstall on iPhone and iPad in issue
   [#28](https://github.com/darrenfu/tadawords/issues/28).
3. Correct the live Pawgoo privacy/support copy described below.
4. Confirm that Pawgoo has no CloudKit server/API access and does not export or
   retain user CloudKit records.
5. Confirm the support mailbox's retention/use and whether parent-initiated
   support qualifies for Apple's optional-disclosure exception.
6. Scan and observe the exact signed iPhone/iPad release candidate. Confirm
   that the teacher-audio endpoint remains absent and that no new SDK or domain
   has appeared.

`PrivacyInfo.xcprivacy` currently declares no collected data. That remains a
candidate declaration, not proof that the final App Store Connect answers are
complete.

## Apple definition used by this audit

Apple defines collection as transmitting data off the device in a way that lets
the developer or a third-party partner access it longer than needed to service
the request in real time. Data handled only on the device is outside that
definition. Apple also says developers are not responsible for declaring data
Apple collects independently through an Apple framework/service, while data
the developer obtains from that service still must be assessed. Developers
must account for integrated third-party partners and their own operating
practices. See
[App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
and
[Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy).

## Runtime data-flow inventory

**Current deletion limitation:** the Parent flow refuses to delete the only
remaining Profile and the app has no separate Delete All App Data/reset path.
Therefore every Profile-deletion statement below applies only when another
Profile remains. This is not a complete in-app erasure choice for a one-Profile
family and remains a release blocker in #19.

| Flow | Data and purpose | Device boundary and destination | Access, retention, linkage, tracking | Choice and deletion | Source evidence |
| --- | --- | --- | --- | --- | --- |
| Read-practice microphone and speech | One short utterance, transient PCM, on-device transcript, confidence, answer decision, response time, and optional local speaker-confidence signal | Raw PCM and recognition stay on device. `requiresOnDeviceRecognition` is mandatory; unsupported devices fail closed | PCM is held in memory for the recognition session, capped at 15 seconds, then released. Raw audio and transcript are not persisted or synced. Attempt facts may persist/sync. No tracking | A parent preauthorizes Speech and Microphone from App & Family. Child Record only checks existing status and fails closed with Ask a Parent if access is unset, denied, restricted, or revoked. Profile deletion removes persisted Profile-owned attempt data locally and enters the sync deletion flow | [`AppleSpeechPermissions.swift`](../Sources/TadaWordsApplePlatform/AppleSpeechPermissions.swift), [`ReadQuestView.swift`](../Sources/TadaWordsFeatures/ReadQuestView.swift), [`SYSTEM_PERMISSION_INVENTORY_v0.7.8.md`](SYSTEM_PERMISSION_INVENTORY_v0.7.8.md) |
| Dormant pre-release derived voiceprint | A template may remain from an earlier pre-release installation | On device only | App Store 1.0 does not expose enrollment and Read Practice does not construct a speaker verifier, so it cannot read or use the template. Existing templates remain `WhenUnlockedThisDeviceOnly`, explicitly non-synchronizing, and excluded from CloudKit. No tracking | Profile deletion explicitly deletes the matching template. On a proven fresh install, bootstrap clears only Tada Words' voiceprint service before any local marker or Profile is written; a reset failure blocks bootstrap and remains retryable. The v0.7.32 update does not silently erase an existing template. The signed physical-device lifecycle proof remains the cleanup evidence | [`VOICEPRINT_1_0_RELEASE_FALLBACK_v0.7.32.md`](VOICEPRINT_1_0_RELEASE_FALLBACK_v0.7.32.md), [`KeychainDeviceVoiceprintRepository.swift`](../Sources/TadaWordsApplePlatform/KeychainDeviceVoiceprintRepository.swift), [`ApplicationBootstrap.swift`](../Sources/TadaWordsAppShell/ApplicationBootstrap.swift), [`VOICEPRINT_KEYCHAIN_LIFECYCLE_v0.7.30.md`](VOICEPRINT_KEYCHAIN_LIFECYCLE_v0.7.30.md) |
| Camera/photo word-sheet import | Parent-selected images and on-device Vision OCR fragments used to propose words | No image or OCR request leaves the device | Source images and unapproved OCR output are transient. Only words the parent reviews and imports enter the Pool. No tracking | Camera/photo choice and explicit import review. Dismissal discards unapproved output; imported words can be deleted individually, in bulk, or as a Pool | [`AppleImageTextRecognitionService.swift`](../Sources/TadaWordsApplePlatform/AppleImageTextRecognitionService.swift), [`GuardianQuickAddView.swift`](../Sources/TadaWordsGuardianFeatures/GuardianQuickAddView.swift) |
| Profile photo | Parent-selected camera/library image, resized JPEG, dimensions, size, content type, checksum, and Profile association | Stored locally. When Family Sync is enabled, only the prepared JPEG travels to Apple CloudKit as a `CKAsset` | The original camera/library image is not synchronized. The prepared image is at most 512×512 and 256 KiB. Apple and authorized share participants receive it through CloudKit. No source path gives Pawgoo access. No tracking | Parent selects the photo. Profile deletion purges the local photo and stages CloudKit erasure; production proof remains open in #19 | [`ProfilePhotoPreparation.swift`](../Sources/TadaWordsGuardianFeatures/ProfilePhotoPreparation.swift), [`CloudKitProfilePhotoAsset.swift`](../Sources/TadaWordsApplePlatform/CloudKitProfilePhotoAsset.swift) |
| Handwriting recognition | Vector strokes and temporary raster passes used by on-device Vision; recognition decision and timing | Strokes, rasters, and recognition candidates stay on device | Unfinished strokes and transient recognition data are not persisted or synced. Attempt outcome, timing, help, and input context may persist/sync. No tracking | Child writes and submits. Clear/session transition discards the canvas. Profile deletion removes Profile-owned attempt facts | [`AppleHandwritingRecognitionService.swift`](../Sources/TadaWordsApplePlatform/AppleHandwritingRecognitionService.swift), [`HandwritingCanvasView.swift`](../Sources/TadaWordsFeatures/HandwritingCanvasView.swift) |
| Typed spelling | In-app A–Z key taps, submitted spelling decision, timing, help, and input context | On device; canonical attempt fact may sync | Draft keystrokes are transient. The submitted attempt fact is linked to Profile/prompt IDs. No tracking | Child initiates and submits; Profile deletion follows the common attempt-data path | [`SpellQuestView.swift`](../Sources/TadaWordsFeatures/SpellQuestView.swift), [`RepositoryFamilySyncRecordStore.swift`](../Sources/TadaWordsContent/RepositoryFamilySyncRecordStore.swift) |
| Local app files | Profiles, Pools, canonical learning facts, settings, quests, session/onboarding state, deletion ledger, a random per-install UUID, and sync recovery state | App-private Application Support files; the classified subset below can be copied to CloudKit only after opt-in | JSON snapshots use explicit forward-only schemas. A future schema fails before bootstrap writes and reports only store/version boundaries. Records link by stable Profile/event IDs. The random UUID is not an Apple hardware, advertising, or account identifier; its value enters synchronized logical-revision envelopes only to deterministically resolve equal revisions. A production fresh install also seeds a random Profile UUID instead of a bundled child identity. No tracking | Parent creates/imports data. Profile deletion removes Profile-owned local records after the terminal barrier only when another Profile remains. There is no complete in-app final-Profile/delete-all path yet. App-container removal is OS-managed; on the next proven fresh launch the separate Tada Words voiceprint Keychain service is cleared before seeding | [`ApplicationBootstrap.swift`](../Sources/TadaWordsAppShell/ApplicationBootstrap.swift), [`TadaWordsApp.swift`](../Apps/TadaWordsApp/TadaWordsApp.swift), [`FAMILY-SYNC-DATA-MANIFEST.md`](FAMILY-SYNC-DATA-MANIFEST.md) |
| Local notifications | Parent-selected reminder preferences; generic notification title/body; OS request IDs | Notification content and schedules stay with `UNUserNotificationCenter`. Preferences may sync; OS authorization and scheduled IDs do not | Notification copy avoids child names and words. Request IDs include a local Profile UUID and are held by iOS. No tracking | A parent enables reminders under App & Family → Notifications; only that save path may request iOS notification permission. Turning settings off or deleting a Profile removes its scheduled requests | [`AppleLearningNotificationScheduler.swift`](../Sources/TadaWordsApplePlatform/AppleLearningNotificationScheduler.swift), [`SYSTEM_PERMISSION_INVENTORY_v0.7.8.md`](SYSTEM_PERMISSION_INVENTORY_v0.7.8.md) |
| Family Sync | Canonical Profile, Pool, settings, attempt/correction, daily-plan/completion/reward, and deletion facts; bounded photo asset; common envelope metadata including a random per-install logical-revision UUID | Yes, after explicit parent opt-in, to Apple's private/shared CloudKit databases. APNs remote notification wakes reconciliation; the app ignores notification payload content | Apple and invited share participants have access according to CloudKit controls. The source has no Pawgoo server-reader path. Record linkage uses stable Profile/event/business-key IDs. The opaque installation UUID is used only as an equal-revision tie-breaker, not advertising, cross-app tracking, hardware identification, or account identity. No advertising or tracking purpose | Off by default per device. Turning it off stops future lifecycle/manual/background sync but does not erase uploaded records. Profile deletion is the erasure action only while another Profile remains; production proof and a complete final-Profile/delete-all path remain open in #19 | [`CloudKitFamilySyncTransport.swift`](../Sources/TadaWordsApplePlatform/CloudKitFamilySyncTransport.swift), [`TadaWordsAppDelegate.swift`](../Apps/TadaWordsApp/TadaWordsAppDelegate.swift), [`FamilySyncDataManifest.swift`](../Sources/TadaWordsDomain/FamilySyncDataManifest.swift) |
| Profile deletion ledger | Profile ID, revision counter, revision device ID, and envelope schema, plus CloudKit system record metadata | Retained in the owner's CloudKit control zone to prevent stale-device resurrection | App-authored fields contain no nickname, photo, word, learning event, or voice data. CloudKit also maintains system metadata for the record. The Profile zone/share/assets are designed to be erased after the barrier. No tracking | Parent authorization required. Owner erasure, participant leave, and revocation paths exist in source; deletion of the sole Profile is currently blocked, and signed production destructive acceptance remains open | [`CloudKitFamilyDeletionLedger.swift`](../Sources/TadaWordsApplePlatform/CloudKitFamilyDeletionLedger.swift), [`RepositoryFamilySyncDeletionPrivacyHarnessTests.swift`](../Tests/TadaWordsContentTests/RepositoryFamilySyncDeletionPrivacyHarnessTests.swift) |
| Picture hints | Concrete-word lookup and a child-safe Twemoji PNG | Bundle only. No runtime URL request | 74 unique PNGs are bundled. Abstract/function words have no mapping. No request logging, cache download, or tracking | Shown only after the practice assistance rule permits it. Removing the app removes bundled/cache copies | [`AppleWordPictureHintService.swift`](../Sources/TadaWordsApplePlatform/AppleWordPictureHintService.swift), [`Package.swift`](../Package.swift) |
| Third-Party Notices | Offline Twemoji attribution, pinned source/version, unmodified status, and CC BY 4.0 terms | Notice text stays in the bundle. Only a parent's explicit tap opens the GitHub source or Creative Commons license in the external browser | No Profile, word, learning, photo, voice, or device identifier is appended to either URL. Normal open-web policy applies. No tracking SDK | Available behind the Parent Gate; external navigation is parent initiated | [`GuardianThirdPartyNoticesView.swift`](../Sources/TadaWordsGuardianFeatures/GuardianThirdPartyNoticesView.swift), [`APP_STORE_CONTENT_RIGHTS.md`](APP_STORE_CONTENT_RIGHTS.md) |
| Teacher word audio | Bundled Katie/Aurora clip or offline Apple speech. Dormant client payload contains word, optional pronunciation key, usage, speed, and contract version | Current configuration: bundle/Apple speech only. If an HTTPS `TadaWordsTeacherAudioEndpoint` is added later, that JSON would go to the configured server and an MP3 would return | Current app contains no endpoint or provider credential. Any future endpoint needs a new server-retention/provider audit. Received audio would be cached under a one-way SHA-256 filename. No current tracking | No current remote choice because the path is inactive. Enabling an endpoint invalidates this inventory | [`TadaWordsApp.swift`](../Apps/TadaWordsApp/TadaWordsApp.swift), [`RemoteTeacherWordAudioProvider.swift`](../Sources/TadaWordsApplePlatform/RemoteTeacherWordAudioProvider.swift) |
| Parent learning-report export | Word, mode, first-attempt count, correct count, accuracy, and mean seconds in CSV | Leaves the app only when an authorized parent invokes the iOS share sheet and chooses a destination | Tada Words does not upload the CSV. The selected destination's policy applies. No automatic retention or tracking by this app | Sensitive Parent action authorization, followed by an explicit share-sheet choice each time | [`GuardianReportsView.swift`](../Sources/TadaWordsGuardianFeatures/GuardianReportsView.swift), [`GuardianModels.swift`](../Sources/TadaWordsGuardianFeatures/GuardianModels.swift) |
| Family Sync diagnostic export | Generated timestamp, enabled flag, coarse transport state, pending/retry count, next retry, and last-success timestamp | Leaves the app only when a parent explicitly chooses a share-sheet destination | Deliberately excludes Profile ID, child name, words, photo, voice sample, voiceprint, and repository payload. Destination policy applies. No tracking | Parent explicitly shares each report | [`GuardianPlatformViews.swift`](../Sources/TadaWordsGuardianFeatures/GuardianPlatformViews.swift) |
| OS diagnostics | Bootstrap failure category/store/schema boundary and speech-framework error domain/code | Written to Apple's local unified logging system; no app network exporter exists | No nickname, word, photo, voice sample, transcript, voiceprint, stroke, or repository payload is logged by these paths. OS retention/access policy applies. No analytics or tracking | Automatic on technical failure; removed under OS log lifecycle | [`ApplicationBootstrap.swift`](../Sources/TadaWordsAppShell/ApplicationBootstrap.swift), [`AppleSpeechRecognitionService.swift`](../Sources/TadaWordsApplePlatform/AppleSpeechRecognitionService.swift) |
| Privacy and support resources | Opens Pawgoo Privacy or Support in the external browser; a parent may later email `support@pawgoo.app` and voluntarily include contact/message content | HTTPS request to `pawgoo.app`; optional support message travels through the parent's chosen mail service to Pawgoo support | Normal web/network metadata reaches Pawgoo/hosting providers. Support staff can read voluntarily sent email/message content under Pawgoo's mailbox retention practice. The app does not append child data. Apple separately exempts app-enabled navigation of the open web from web-traffic declaration. No advertising/tracking SDK in the app | Links are behind the Parent Gate. Sending support content is parent-initiated outside the app. Parent can instead use in-app local deletion/permission guidance | [`GuardianTodayView.swift`](../Sources/TadaWordsGuardianFeatures/GuardianTodayView.swift), live [Privacy](https://pawgoo.app/en/tadawords/privacy) and [Support](https://pawgoo.app/en/support) pages |
| Face ID/device authentication | OS result used to authorize sensitive Parent actions | Biometric data does not enter Tada Words | The app receives only authentication success/failure from LocalAuthentication. No biometric template, retention, linkage, or tracking by the app | Triggered for sensitive Parent actions when available; device passcode fallback follows OS policy | [`AppleSensitiveGuardianActionAuthorizer.swift`](../Sources/TadaWordsApplePlatform/AppleSensitiveGuardianActionAuthorizer.swift), [`Info.plist`](../Apps/TadaWordsApp/Info.plist) |

## Family Sync payload boundary

The machine-readable
[`FamilySyncDataManifest`](../Sources/TadaWordsDomain/FamilySyncDataManifest.swift)
is the release contract. A regression test locks the sensitive boundary so a
voiceprint cannot silently become a synchronized field.

### Synchronized canonical facts

- Profile stable ID, nickname, age, grade, source avatar choice, World/icon/
  Treasure choices, created/updated metadata, and the bounded prepared Profile
  photo plus validated attachment metadata. The dedicated Profile wire payload
  does not encode `voiceprintStatus` at all—not even a `notEnrolled` sentinel.
  A receiving device preserves the enrollment state derived from its own
  Keychain.
- Independent Read, Write, audio, notification-intent, interface, handwriting-
  tool, and word-policy settings.
- Parent-approved Pool prompts, normalized words, provenance, active state,
  queue metadata, aliases, and logical revisions.
- Immutable attempts and guardian corrections. Attempt payloads can include the
  practiced prompt relationship, outcome, timing, confidence, help/retry
  context, device family, and input-method context; they do not contain raw
  speech, speech transcript, handwriting strokes, OCR source, or voiceprint.
- Daily plans, Today/Practice Again completion facts, reward grants, and causal
  staging records.
- The privacy-minimal terminal Profile-deletion ledger.
- Every record's common envelope: record/Profile identity, kind and schema
  boundaries, update/deletion state, payload/checksum/size, and logical
  revision. The revision's device ID is a random UUID created by this app for
  the installation and is used only to converge equal revisions; it is not an
  Apple hardware ID, IDFA, account ID, or cross-app identifier.

### Derived locally, never authoritative transport

- Word mastery, accuracy/timing/help aggregates, Ebbinghaus `MemoryState`, and
  the legacy-prompt alias projection.
- Calendar, scores, stars, reports, World/icon unlocks, Treasure/badges, and
  selected-Treasure validity.
- Last-sync presentation and local notification schedules.

These views are rebuilt deterministically from synchronized canonical facts.
CloudKit must not win a conflict with a transported progress/report snapshot.

### Device-local and excluded from CloudKit

- Last-selected Profile and transient navigation/session state.
- Per-device Family Sync opt-in, account confirmation, outbox/journal/retry,
  CloudKit bindings/system fields, inbox/quarantine, `CKSyncEngine` tokens, APNs
  token, and local notification request IDs.
- The `device-identity.txt` file itself. Its opaque UUID value is intentionally
  copied into the synchronized logical-revision envelope as described above.
- Exact pending remote-apply payloads and photo upload-source files used for
  crash recovery. They are purged after acknowledgement; only privacy-minimal
  receipts remain.
- Voiceprint template/readiness, enrollment samples, and raw recognition PCM.
- OCR images/output after review, handwriting strokes/raster/candidates, hidden
  ink/eraser state, and unfinished input.
- Picture, teacher-audio, music, and sound-effect assets/caches.

### CloudKit operator boundary

Production source constructs container `iCloud.com.tadawords.app`, uses a
private zone per owned Profile, and uses shared-database routes for accepted
shares. Simulator and LocalQA compositions do not carry production iCloud
entitlements or a real CloudKit transport.

Apple documents the container's
[private database](https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase)
and
[shared database](https://developer.apple.com/documentation/cloudkit/ckcontainer/sharedclouddatabase).
Source inspection can prove there is no Pawgoo reader in this app; it cannot
prove that no separate dashboard, server credential, export, or operational
process exists. The release owner must attest that boundary.

## Manifest, permissions, and disclosure reconciliation

| Surface | Current declaration/behavior | Audit result |
| --- | --- | --- |
| `PrivacyInfo.xcprivacy` | Tracking false; no tracking domains; empty collected-data array; File Timestamp reason `C617.1`; System Boot Time reason `35F9.1`; app-container User Defaults reason `CA92.1` | The three required-reason declarations cover the audited source, including the Profile-scoped handwriting-tool preference in `UserDefaults`. Keep the manifest and conditional no-Pawgoo-collection design provisional until the owner attestations and exact signed-build scan pass |
| Microphone | Spoken Read Practice; raw audio not saved/uploaded | Matches source. Voice setup and speaker matching are not included in App Store 1.0 |
| Speech Recognition | On-device comparison | Matches source; unsupported on-device recognition fails closed |
| Camera | Parent-selected Profile photo or word-sheet OCR | Matches source; prepared Profile photo may later sync through CloudKit after opt-in |
| Photo Library | Parent-selected Profile photo or word-sheet OCR | Matches source with the same CloudKit qualification |
| Face ID | Protects sensitive Parent sharing/deletion actions | Matches source; app receives no biometric data |
| Notifications/background mode | Local family reminders plus CloudKit remote-notification reconciliation | Source matches. OS authorization/request IDs and APNs token remain local; remote payload content is ignored by the app delegate |
| Production entitlements | APNs and CloudKit through `iCloud.com.tadawords.app`; no KVS entitlement | APNs/CloudKit match production Family Sync. No `NSUbiquitousKeyValueStore` use exists in audited source; the unused KVS entitlement was removed in v0.7.12 |
| LocalQA entitlements | Empty; sharing false; no background mode | Matches device-only QA composition |
| Parent resources | Protected Privacy and Support links plus local Profile-deletion and iOS-permission instructions | Present and regression-covered. External pages require a network connection |
| Third-Party Notices | Offline exact Twemoji attribution plus parent-triggered source/license links | Matches the bundled assets and content-rights inventory; no child-facing or automatic request |
| First-run/Family Sync disclosure | Sync is off until Parent opt-in; Profile/word/learning/settings/reward facts may go to iCloud; raw recordings and voiceprints do not | Matches source. Turning sync off stops later calls but does not erase prior CloudKit records |

The privacy manifest uses Apple's required-reason API shape; see
[Describing data use in privacy manifests](https://developer.apple.com/documentation/BundleResources/describing-data-use-in-privacy-manifests).

## Live Pawgoo policy/support mismatches

The audit re-fetched both public URLs on 2026-07-19. Both returned HTTP 200.
The deployed JavaScript asset was `assets/index-A0SJyuQY.js`, SHA-256
`1dc31afa65050902972da6af476c098f36ae22f5f246f89e811caf8409529635`.
No website was modified during this audit.

| Live wording/meaning | Current source reality | Required action |
| --- | --- | --- |
| Picture-hint downloads require a connection and download an optional hint | All picture hints are now bundled and resolved with `Data(contentsOf:)`; there is no hint URLSession path | Remove the CDN/download/internet-requirement language and describe bundled offline hints |
| Deletion “stops the deleted profile from returning” | Source has a terminal ledger, stale-device barrier, and owner/participant removal paths, but production destructive CloudKit proof is still open | Qualify the public guarantee until #19 passes, then align the final verified behavior |
| Parent deletion/data-control copy implies every Profile can be removed | The app refuses to delete the only remaining Profile and has no complete Delete All App Data/reset path | Treat this as a release blocker in #19; add an authorized final-Profile/full-erasure flow and only then claim complete in-app deletion |
| Local data remains until a parent deletes, resets app data, or removes the app | App-container data follows that model. Because iOS does not guarantee Keychain cleanup at uninstall time, the next proven fresh launch clears only Tada Words' `ThisDeviceOnly` voiceprint service before creating local state and fails closed if that reset fails; ordinary upgrades preserve enrollment | Signed physical-device coverage uses retained real Keychain items and a new production-repository instance to prove the reset non-destructively. Publish the matching policy/support wording under #54 |
| Family Sync is optional/off by default and covers “selected profile and learning records” | Per-device opt-in/off-by-default is correct. Family Sync is nevertheless required for the 1.0 product, and the payload includes all classified durable Profile-owned canonical facts, not only an unspecified selection | Keep opt-in wording; expand scope to Profile metadata/photo, Pools, settings, canonical learning/daily/reward facts, and deletion ledger; keep device-local exclusions explicit |
| Support says deletion stops return | Same unproven production-erasure issue as the privacy page | Make Support and Privacy use the same qualified, verified deletion language |

These mismatches are release blockers for a truthful submission. Issues #19
and #28 cover deletion proof and signed Keychain-lifecycle verification. Issue #54 owns exact-RC
alignment and deployment evidence for the Pawgoo Privacy and Support pages;
this source-only batch did not mutate the public site.

## Draft App Store Privacy answers

### Conditional recommended answer set

Use this only after every gate in the Decision summary passes:

| App Store Connect prompt | Draft answer |
| --- | --- |
| Do you or your third-party partners collect data from this app? | **No, we do not collect data from this app** |
| Data types | None |
| Data used to track the user | No |
| Privacy Policy URL | `https://pawgoo.app/en/tadawords/privacy` after the live mismatches are corrected |
| Privacy Choices URL | Owner decision. Use only a page that actually explains/handles the supported choices; do not add a cosmetic URL |

This draft treats on-device processing as not collected; Apple CloudKit as an
Apple-operated user service that Pawgoo does not access; parent-chosen exports
as user-directed transfers; and support contact as either outside the app or
within Apple's optional-disclosure criteria. Each assumption needs release-
owner confirmation. Source code alone cannot finalize it.

### Conditional support-contact disclosure

If the final support workflow or mailbox practice does **not** meet every Apple
optional-disclosure criterion, add this data rather than preserving the empty
answer by assumption:

| Data type | Purpose | Linked to identity | Tracking |
| --- | --- | --- | --- |
| Contact Info → Email Address | App Functionality → Customer Support | Yes | No |
| User Content → Customer Support | App Functionality → Customer Support | Yes | No |

### Conditional installation Device ID disclosure

Every synchronized record includes a random per-install UUID as the logical-
revision tie-breaker. It is not an Apple hardware identifier, IDFA, account ID,
or cross-app identifier, but it is stable for the app installation and reaches
Apple CloudKit/share participants with Profile-scoped records. The release
owner must classify it against the exact App Store Privacy questionnaire and
the final Pawgoo CloudKit-access operating boundary.

If those facts do not support the conditional **No data collected** answer,
declare `Identifiers → Device ID` for App Functionality with the truthful
linked-to-user result rather than omitting the UUID. Source code alone cannot
decide Pawgoo access/retention or the final questionnaire treatment.

For data provided in an app interface, the optional-disclosure exception
requires optional and infrequent submission, clear disclosure of the submitted
elements, the user's name/account name prominently displayed beside them,
affirmative submission each time, and no tracking, advertising, marketing, or
unrelated use. Navigation to the open web is a separate Apple example. The
release owner must verify which rule applies to the final web/mail flow and the
actual mailbox practice.

### Stop-and-re-audit triggers

- `TadaWordsTeacherAudioEndpoint` becomes present in any shipping configuration.
- Pawgoo gains CloudKit server/API, dashboard, export, support attachment, or
  other record access.
- A login/account, analytics, crash, telemetry, advertising, attribution, or
  purchase SDK is added.
- A new non-Apple destination/domain or third-party package appears.
- A new data type, support workflow, retention practice, notification payload,
  or user-directed export appears.
- Apple changes the questionnaire instructions in a way that affects CloudKit,
  user-directed transfers, or optional support disclosure.

Do not guess categories after one of these triggers. Re-inventory the exact
shipping behavior and obtain the operator's retention/access facts.

## Release blockers and owner attestations

| Gate | Required evidence/decision | Tracker |
| --- | --- | --- |
| Production CloudKit schema and destructive erasure | Signed test-only owner Profile deletion, offline stale-device reconnect, zone/share/asset inspection, participant leave, and revocation | [#19](https://github.com/darrenfu/tadawords/issues/19) |
| Voiceprint after app removal | Run the signed `KeychainVoiceprintLifecycleDeviceTests` on the exact candidate. It uses retained real Keychain items in isolated services to prove repository recreation preserves them until the same scoped fresh-install reset removes them, while never uninstalling the user's app or touching production voiceprints. Update deployed site copy separately | [lifecycle record](VOICEPRINT_KEYCHAIN_LIFECYCLE_v0.7.30.md), [#28](https://github.com/darrenfu/tadawords/issues/28), and [Apple DTS forum guidance](https://developer.apple.com/forums/thread/36442) |
| Family Sync physical acceptance | Same-account private sync, different-Apple-ID sharing, background delivery, recovery, and accessibility on exact signed iPhone/iPad RC | [#22](https://github.com/darrenfu/tadawords/issues/22) plus Family Sync acceptance Issues |
| App Store container/configuration | Final App ID/container/App Store Connect configuration and production schema | [#23](https://github.com/darrenfu/tadawords/issues/23) |
| Distribution decisions | **Resolved for 1.0:** Made for Kids 6–8, Free with no IAP/ads, United States only, no pre-order, and manual release. #65 must enter the exact values; #26 retains submission and release authority | [decision record](APP_STORE_RELEASE_DECISIONS_v0.7.27.md), [#24](https://github.com/darrenfu/tadawords/issues/24), [#26](https://github.com/darrenfu/tadawords/issues/26) |
| Pawgoo live copy | Remove old hint-download statements; qualify deletion; clarify Keychain lifecycle and full sync scope | [#54](https://github.com/darrenfu/tadawords/issues/54); no public-site mutation in this batch |
| Complete child-data erasure | Allow the authorized parent to delete the final Profile and all associated local/CloudKit data, or provide an equally complete Delete All Data flow that returns to first-run without resurrection | [#19](https://github.com/darrenfu/tadawords/issues/19) |
| Pawgoo CloudKit access | Owner attests that no separate server credential, dashboard, export, or support process reads/retains CloudKit records | Release-owner attestation |
| Installation Device ID classification | Confirm the random per-install logical-revision UUID is handled consistently in the final Privacy Report and App Store Privacy questionnaire; if the conditional no-collection assumptions do not hold, disclose Device ID for App Functionality rather than guessing | Release-owner/privacy review |
| Support retention/use | Owner confirms mailbox retention, uses, access, deletion response, and optional-disclosure eligibility | Release-owner/privacy review |
| Remote teacher audio | Exact signed plist/project scan proves endpoint absent | Exact signed-RC gate |
| Dependency/domain scan | No new SDK, package, framework destination, or unexpected iPhone/iPad traffic | Exact signed-RC gate |

## Edge-case matrix

| Case | Expected privacy behavior |
| --- | --- |
| Family Sync never enabled | Production learning remains local. No lifecycle/manual/background CloudKit sync is registered for Profile data |
| Family Sync enabled | Only classified canonical facts and prepared Profile photo use Apple private/shared CloudKit. Voiceprint/raw audio/OCR/strokes/caches remain local |
| Family Sync later disabled | Future sync calls and remote-notification registration stop; already uploaded records are not erased merely by opting out |
| Offline | Learning, OCR, picture hints, bundled audio, Apple on-device speech/Vision, and local saves continue. CloudKit remains pending and retries after connectivity returns |
| iCloud unavailable/account changed | Child practice remains local. Transport fails closed, reports a coarse Parent status, and does not replay old-account metadata into a newly confirmed account |
| Permission denied | Camera/photo, microphone/speech, notification, or biometric-dependent action fails/remains unavailable. No fallback upload path exists |
| Share participant revoked or leaves | Route becomes terminal; it must not silently create a private owner fallback. Signed production proof remains required |
| Profile photo corrupt/oversize | Incoming asset is quarantined and existing avatar retained; invalid bytes are not installed as Profile state |
| Future local snapshot schema | App fails before bootstrap writes, preserves files, and shows privacy-safe update guidance without child content |
| Parent CSV/diagnostic export | Nothing leaves until the parent selects a share-sheet destination; destination policy applies |
| Support contact | App does not attach child data. Parent chooses what to send outside the app; final disclosure depends on actual support practices |
| Fresh offline install | Bundled picture hints and covered teacher audio work without a third-party asset request |

## Exact signed-release verification plan

1. Record branch, exact commit, `CFBundleShortVersionString`,
   `CFBundleVersion`, bundle ID, signing team, entitlements, embedded commit,
   `PrivacyInfo.xcprivacy`, resolved frameworks, and resource list from the
   signed `.app`/`.ipa`.
   Confirm the archive declares File Timestamp `C617.1`, System Boot Time
   `35F9.1`, and app-container User Defaults `CA92.1` exactly once.
2. Search source, generated project, final Info.plist, linked frameworks, and
   resolved dependencies for URLSession, CloudKit, analytics, telemetry,
   crash-reporting, advertising, attribution, and account code. Prove
   `TadaWordsTeacherAudioEndpoint` is absent.
3. With Family Sync off, run fresh/install-preserving iPhone and iPad tests
   online and offline. Exercise Read, voice setup, OCR, Profile photo,
   handwriting/spelling, hints, notifications, CSV/diagnostic share sheets,
   and Parent links. Deny every permission and confirm there is no upload
   fallback.
4. Observe traffic on both device classes. Expected app destinations are the
   parent-triggered `pawgoo.app` resources and Apple system services. No
   unexplained non-Apple runtime destination is acceptable.
5. Enable Family Sync on signed production-capable test builds. Verify the
   manifest's record classes and bounded CKAsset only; verify voiceprint/raw
   audio/OCR/strokes/caches never appear. Decode every actual repository record
   kind against the reviewed recursive JSON-shape contract, including enum
   associated values, array elements, and raw-value wrappers.
6. Complete same-account, different-Apple-ID share, background APNs wake,
   offline recovery, account-change, participant leave/revocation, and test-
   only terminal deletion acceptance. Inspect the real container after erasure.
7. Reconcile the exact build, this inventory, the live Privacy/Support pages,
   in-app disclosure, permission strings, privacy manifest, App Store Connect
   answers, and operator attestations. Any mismatch blocks submission.

This pre-1.0 migration guarantees that the current client can read legacy
Profile payloads and preserves their exact CKAsset checksum during hydration.
It does not claim that an old installed binary can read a newly emitted
Profile-photo payload. All Family Sync acceptance devices must be upgraded to
the same release candidate before the signed multi-device test; mixed-version
compatibility remains out of scope until a versioned wire cutover is designed.

## Change control

Any new commit after evidence collection invalidates that evidence. Any new
dependency, domain, endpoint, server access, data type, notification payload,
support/export flow, account system, or retention practice invalidates the
draft answer set. Update this versioned inventory before uploading the affected
build.
