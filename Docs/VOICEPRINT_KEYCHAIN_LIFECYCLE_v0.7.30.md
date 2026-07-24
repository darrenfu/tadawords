# Voiceprint Keychain lifecycle — v0.7.30

## Owner-approved 1.0 contract

- An ordinary app update preserves the device voiceprint.
- Profile deletion deletes that Profile UUID's voiceprint before the deletion
  barrier can commit and fails closed if Keychain deletion fails.
- App removal is not described as guaranteed physical Keychain erasure.
- When bootstrap proves that the Tada Words Application Support data directory
  was absent at startup, it clears every generic-password item in the
  app-exclusive `com.tadawords.device-voiceprints` service before writing any
  local marker or Profile. Failure blocks bootstrap and remains retryable.
- Templates use `WhenUnlockedThisDeviceOnly`, set Keychain synchronization to
  false, and never enter CloudKit.

This is the product/privacy retention contract approved in issue #28. It is not
a claim about undocumented iOS uninstall behavior.

## Evidence layers

| Boundary | Evidence |
| --- | --- |
| Bootstrap ordering | `FreshInstallationVoiceprintIsolationTests` proves fresh-install reset precedes Profile seeding, upgrades preserve templates, reset failure leaves no initialization marker, and retry succeeds. |
| Profile deletion | `RepositoryFamilySyncDeletionPrivacyHarnessTests` proves voiceprint deletion precedes local JSON purge and the terminal barrier; failure stops before destructive progress. |
| Real Security framework | `KeychainVoiceprintLifecycleDeviceTests` runs the production `KeychainDeviceVoiceprintRepository` in a signed physical-device test host. It proves retained items survive repository/process recreation, the fresh-install reset removes every item in the scoped service, a neighboring service remains intact, attributes are `WhenUnlockedThisDeviceOnly` and non-synchronizing, and an empty reset is idempotent. |
| Shipping composition | `TadaWordsApp` constructs the production repository with the fixed `com.tadawords.device-voiceprints` service and passes it through the Profile mutation gate to production bootstrap. |

The physical-device test deliberately uses UUID-scoped test service names. It
never reads, writes, or deletes the production voiceprint service and does not
require uninstalling the user's app or clearing app data. It supplies a
non-destructive uninstall/reinstall-equivalent state: retained real Keychain
items plus a newly constructed production repository, followed by the same
service-scoped reset production bootstrap invokes when its app-container marker
is absent.

## Public wording

Use this distinction consistently:

> Removing Tada Words may not immediately erase a device-only voiceprint from
> the iOS Keychain. On the next proven fresh launch, Tada Words clears its
> dedicated voiceprint service before creating or using any Profile data.
> Deleting a Profile from inside the app deletes that Profile's voiceprint.

Do not say that uninstall alone guarantees irreversible deletion. Deployment
and exact-release comparison of Pawgoo's Privacy and Support pages remain
tracked by #54.

## Sources

- Runtime repository:
  `Sources/TadaWordsApplePlatform/KeychainDeviceVoiceprintRepository.swift`
- Fresh-install gate:
  `Sources/TadaWordsAppShell/ApplicationBootstrap.swift`
- Production composition: `Apps/TadaWordsApp/TadaWordsApp.swift`
- Apple DTS discussion of uninstall behavior:
  <https://developer.apple.com/forums/thread/36442>
- Decision and acceptance tracker:
  <https://github.com/darrenfu/tadawords/issues/28>
