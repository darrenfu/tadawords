# Tada Words shipping system-permission inventory — v0.7.8

**Source candidate:** `codex/issue55-parent-speech-permission-v0.7.8`

**Release identity:** version `0.7.8`, build `2026071908`

**Audit date:** 2026-07-20

**Status:** source and deterministic contract checklist. Exact signed first-install,
denied, authorized, and revoked verification on one iPhone and one iPad remains
required by issues #55 and #22 before App Store submission.

This inventory names every shipping iOS API or system picker that can request
access, the only adult-owned entry point allowed to reach it, and the behavior a
child sees when access is missing. A source or configuration change that adds a
permission API invalidates this checklist until the new entry point is audited.

## Permission request ownership

| System access | Requesting API or system surface | Adult-owned first-prompt entry point | Child behavior when unset, denied, restricted, or revoked | Source boundary |
| --- | --- | --- | --- | --- |
| Speech Recognition | `SFSpeechRecognizer.requestAuthorization` | Parent Gate → App & Family → Speech & Microphone → Set up access. Parent Gate → Kids → Voice setup may also request the same still-undetermined access before enrollment | Read Practice only reads current status. Record fails closed with “Ask a Parent”; it never calls a requesting API and never loops a system prompt | [`AppleSpeechPermissions.swift`](../Sources/TadaWordsApplePlatform/AppleSpeechPermissions.swift), [`TadaWordsApplicationView.swift`](../Sources/TadaWordsAppShell/TadaWordsApplicationView.swift), [`ReadQuestView.swift`](../Sources/TadaWordsFeatures/ReadQuestView.swift) |
| Microphone | `AVCaptureDevice.requestAccess(for: .audio)` | Parent Gate → App & Family → Speech & Microphone → Set up access. Parent Gate → Kids → Voice setup is the second adult-owned route | Same fail-closed child boundary as Speech Recognition. An already-authorized child records normally; revocation is noticed on the next check or recognition attempt | Same speech boundary plus [`AppleVoiceprintEnrollmentService.swift`](../Sources/TadaWordsApplePlatform/AppleVoiceprintEnrollmentService.swift) |
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

## Negative child-route contract

The same check-only `SpeechPermissionActions` value is retained by the child
root and passed into every Read presentation. App launch, Profile selection or
switch, Read entry, replay, cold relaunch, and the debug demo/deep-link fixture
cannot receive the Parents-only request closure. `TadaWordsFeatures` has no
dependency on `TadaWordsApplePlatform` and its public child permission
capability exposes `isAuthorized()` only.

Deterministic enforcement:

- [`ChildSpeechPermissionRouteContractTests.swift`](../Tests/TadaWordsAppShellTests/ChildSpeechPermissionRouteContractTests.swift)
  scans every child-feature source for requesting APIs and locks AppShell
  composition to a check-only child input plus a separate Guardian request
  output.
- [`ChildSpeechPermissionBoundaryTests.swift`](../Tests/TadaWordsFeaturesTests/ChildSpeechPermissionBoundaryTests.swift)
  verifies authorized compatibility and fail-closed unavailability.
- [`GuardianSpeechPermissionTests.swift`](../Tests/TadaWordsGuardianFeaturesTests/GuardianSpeechPermissionTests.swift)
  verifies that opening Parents reads status without prompting and that only the
  explicit setup action requests access and publishes the separate Speech and
  Microphone results.
- [`AppleSpeechAdapterTests.swift`](../Tests/TadaWordsApplePlatformTests/AppleSpeechAdapterTests.swift)
  verifies separate request plans for still-undetermined Speech and Microphone
  states.
- [`SystemPermissionInventoryContractTests.swift`](../Tests/TadaWordsContentTests/SystemPermissionInventoryContractTests.swift)
  locks every shipping usage-description key and known requesting API or system
  surface to this inventory and to its audited adult-owned source site.

## Exact-release manual acceptance still required

On the exact signed release candidate, preserve installed data and verify:

1. Fresh install: launch, Profile creation/selection, Read entry, replay, app
   relaunch, and Profile switch display no Speech or Microphone system alert.
2. Parents setup: each still-undetermined permission is requested only after
   Parent Gate → App & Family → Speech & Microphone → Set up access.
3. Denied/restricted: Parents shows the separate status and Settings guidance;
   child Record shows Ask a Parent without another prompt.
4. Authorized: Read records and completes normally without another parent step.
5. Revoked in iOS Settings: the next child Record fails closed, no learning
   attempt is counted for the permission failure, and returning to Parents shows
   the new status.
6. Repeat the matrix on one physical iPhone and one physical iPad; source tests,
   simulator checks, installation success, and signed-device behavior remain
   separate evidence.
