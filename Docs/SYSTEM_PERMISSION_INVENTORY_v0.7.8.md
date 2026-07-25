# Tada Words shipping system-permission inventory — v0.7.38

**Source candidate:** `agent/batch-child-speech-permissions-v0.7.38`

**Release identity:** version `0.7.38`, build `2026072412`

**Audit date:** 2026-07-24

**Status:** source and deterministic contract checklist. Exact signed first-install,
partial-authorization, denied, authorized, and revoked verification on one
iPhone and one iPad remains required by issues #125 and #22 before App Store
submission.

This inventory names every shipping iOS API or system picker that can request
access, every audited entry point allowed to reach it, and the behavior a child
sees when access is missing. A source or configuration change that adds a
permission API invalidates this checklist until the new entry point is audited.

## Permission request ownership

| System access | Requesting API or system surface | Audited first-prompt entry point | Child behavior when unset, denied, restricted, or revoked | Source boundary |
| --- | --- | --- | --- | --- |
| Speech Recognition | `SFSpeechRecognizer.requestAuthorization` | The first microphone tap in active child Read play when Speech Recognition is `.notDetermined`; or Parent Gate → App & Family → Speech & Microphone → Set up access | The child tap requests Speech Recognition first. If both permissions become authorized, that same tap continues into recording. Denied, restricted, or revoked access is not re-requested and fails closed with “Ask a Parent” recovery. App Store 1.0 has no voice-setup route | [`AppleSpeechPermissions.swift`](../Sources/TadaWordsApplePlatform/AppleSpeechPermissions.swift), [`TadaWordsApplicationView.swift`](../Sources/TadaWordsAppShell/TadaWordsApplicationView.swift), [`ReadQuestView.swift`](../Sources/TadaWordsFeatures/ReadQuestView.swift) |
| Microphone | `AVCaptureDevice.requestAccess(for: .audio)` | The same child microphone tap when Microphone is `.notDetermined`, after the Speech Recognition request finishes; or the Parents setup route | Prompts never overlap. If Speech Recognition is already authorized, only Microphone is requested. Already-authorized children record without new UI. Denied, restricted, or revoked access fails closed with the existing Ask a Parent / Settings route | Same speech boundary plus [`TadaWordsApp.swift`](../Apps/TadaWordsApp/TadaWordsApp.swift) |
| Camera | `UIImagePickerController` with `.camera`, which presents the OS-owned request when required | Parent Gate → Words & Practice → Manage Words → Scan a word sheet → Camera; or Parent Gate → Kids → Edit → Camera | No child route owns a camera picker | [`GuardianQuickAddView.swift`](../Sources/TadaWordsGuardianFeatures/GuardianQuickAddView.swift), [`GuardianProfilesView.swift`](../Sources/TadaWordsGuardianFeatures/GuardianProfilesView.swift) |
| Photo Library | `PhotosPicker`, which presents the OS-owned selection/access surface | Parent Gate → Words & Practice → Manage Words → Choose Photos; or Parent Gate → Kids → Edit → Photo Library | No child route owns a photo-library picker | [`GuardianQuickAddView.swift`](../Sources/TadaWordsGuardianFeatures/GuardianQuickAddView.swift), [`GuardianProfilesView.swift`](../Sources/TadaWordsGuardianFeatures/GuardianProfilesView.swift) |
| Notifications | `UNUserNotificationCenter.requestAuthorization` | Parent Gate → App & Family → Notifications, only after a parent enables at least one reminder and saves | No child route requests notification access. Denied access removes pending Profile reminders while practice remains usable | [`GuardianDashboardViewModel.swift`](../Sources/TadaWordsGuardianFeatures/GuardianDashboardViewModel.swift), [`AppleLearningNotificationScheduler.swift`](../Sources/TadaWordsApplePlatform/AppleLearningNotificationScheduler.swift) |
| Device owner authentication / Face ID when available | `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` | After the Parent Gate, only an explicit sensitive action: delete Profile, export learning data, enable Family Sync, create/accept/manage family access | No child route evaluates device-owner authentication | [`AppleSensitiveGuardianActionAuthorizer.swift`](../Sources/TadaWordsApplePlatform/AppleSensitiveGuardianActionAuthorizer.swift), [`SensitiveGuardianActions.swift`](../Sources/TadaWordsDomain/SensitiveGuardianActions.swift) |

## System services that do not present a user permission prompt

| Service | Trigger owner | Contract |
| --- | --- | --- |
| APNs remote-notification registration | Parent enables Family Sync; the app then registers for silent reconciliation wakes | `registerForRemoteNotifications()` has no user-facing alert. Notification payload content is ignored. APNs status is not presented as proof that CloudKit sync works |
| CloudKit private/shared databases and share UI | Parent enables Family Sync or explicitly creates, accepts, or manages a family share | iCloud account/share sheets are Apple-owned service surfaces, not child permission routes. Family Sync remains off by default per device |
| External Privacy, Support, and license links | Parent taps a link after the Parent Gate | External navigation is parent initiated and is not treated as a device-permission request |

## Contextual child-route contract

The same `SpeechPermissionActions` value is retained by the child root and
passed into every Read presentation. App launch, Profile selection or switch,
Read entry, replay, and cold relaunch never request access by themselves. Only
an active microphone tap calls `authorizeMicrophoneTap()`. The debug
demo/deep-link fixture remains a deterministic authorized fixture and never
shows a system prompt.

`TadaWordsFeatures` still has no dependency on `TadaWordsApplePlatform` and
cannot call Apple permission APIs directly. AppShell composes the contextual
action: it reads current state, invokes the shared request controller only when
at least one permission is `.notDetermined`, and otherwise returns the existing
authorized or fail-closed result. The controller serializes the request
sequence. Rapid repeated taps cannot overlap it; cancellation after the first
prompt prevents the second prompt and any stale recording continuation.

Deterministic enforcement:

- [`ChildSpeechPermissionRouteContractTests.swift`](../Tests/TadaWordsAppShellTests/ChildSpeechPermissionRouteContractTests.swift)
  scans every child-feature source for direct Apple requesting APIs, locks the
  AppShell composition to the contextual action, and requires navigation and
  background cancellation.
- [`ChildSpeechPermissionBoundaryTests.swift`](../Tests/TadaWordsFeaturesTests/ChildSpeechPermissionBoundaryTests.swift)
  verifies one action resolution per tap and fail-closed unavailability.
- [`GuardianSpeechPermissionTests.swift`](../Tests/TadaWordsGuardianFeaturesTests/GuardianSpeechPermissionTests.swift)
  verifies that opening Parents reads status without prompting and that only the
  explicit setup action requests access and publishes the separate Speech and
  Microphone results.
- [`AppleSpeechAdapterTests.swift`](../Tests/TadaWordsApplePlatformTests/AppleSpeechAdapterTests.swift)
  verifies separate request plans, deterministic Speech-then-Microphone order,
  overlap rejection, and cancellation between prompts.
- [`SystemPermissionInventoryContractTests.swift`](../Tests/TadaWordsContentTests/SystemPermissionInventoryContractTests.swift)
  locks every shipping usage-description key and known requesting API or system
  surface to this inventory and to its audited platform source site.

## Exact-release manual acceptance still required

On the exact signed release candidate, preserve installed data and verify:

1. First-install-equivalent isolated LocalQA state: launch, Profile
   creation/selection, Read entry, replay, app relaunch, and Profile switch
   display no Speech or Microphone alert until the microphone is tapped. That
   tap requests Speech Recognition, then Microphone, then continues directly
   into recording when both are granted.
2. Partial authorization: request only the remaining `.notDetermined`
   permission. The Parents setup route remains available and uses the same
   serialized controller.
3. Denied/restricted: Parents shows the separate status and Settings guidance;
   child Record shows Ask a Parent without another prompt.
4. Authorized: Read records and completes normally with no new permission UI or
   delay.
5. Revoked in iOS Settings: the next child Record fails closed, no learning
   attempt is counted for the permission failure, and returning to Parents shows
   the new status.
6. Rapid repeated taps, navigation away, app backgrounding, and relaunch never
   overlap prompts or start a stale recording.
7. Repeat the matrix on one physical iPhone and one physical iPad without
   uninstalling or resetting existing app data. Use an isolated LocalQA plan
   for destructive permission-state preparation. Source tests, simulator
   checks, installation success, and signed-device behavior remain separate
   evidence.
