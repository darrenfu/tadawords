# Voiceprint App Store 1.0 release fallback — v0.7.32

## Decision

No qualified COPPA conclusion was available for the retained derived
voiceprint in time for this batch. The release owner therefore invoked the
conservative fallback recorded in issue #76:

- App Store 1.0 does not expose voiceprint enrollment.
- Read Practice does not load or use a retained template for speaker matching.
- The microphone permission text covers spoken Read Practice only.
- The binary keeps the device-local repository solely for privacy cleanup.

This is a product-scope decision, not a legal conclusion. Issue #76 remains
open for written treatment of transient Read speech, parent-provided
Profile/photo data, persistent identifiers, and optional CloudKit Family Sync.

## Persistent-state boundary

An existing pre-release template is not migrated, synchronized, read by Read
Practice, or exposed through Parent UI. It remains deletable through both
existing fail-closed paths:

1. In-app Profile deletion deletes that Profile UUID's template before the
   deletion barrier can commit.
2. A proven fresh installation clears the app-exclusive
   `com.tadawords.device-voiceprints` service before creating or using local
   Profile data.

The v0.7.32 update does not silently erase a template merely because the
feature is unavailable. If a later legal/product decision reintroduces
voiceprint functionality, it requires a new explicit release decision,
disclosure review, compatibility plan, and exact-artifact acceptance.

## Enforced source boundary

- `VoiceprintReleasePolicy.shipsEnrollmentAndSpeakerMatching` is `false`.
- Production composition does not construct
  `AppleVoiceprintEnrollmentService`.
- Production speech recognition does not inject `AppleVoiceprintVerifier`.
- Parent Profile cards do not render the voice-setup action while the release
  policy is disabled.
- The production Keychain repository remains injected into bootstrap and
  Profile deletion so cleanup behavior cannot regress.

## Verification

- Domain policy test asserts the 1.0 flag is disabled.
- App Store contract tests reject production enrollment/verifier composition,
  reject stale voice-setup permission wording, and require the cleanup
  repository.
- Existing fresh-install, Profile-deletion, and signed Security-framework
  lifecycle tests remain applicable to retained-template cleanup.

## Rollback

Revert this batch only after a replacement owner/counsel decision defines the
lawful release behavior. Re-enabling only the UI is not an acceptable rollback:
enrollment, speaker matching, disclosures, persisted-state treatment, and
exact-device evidence must move together.
