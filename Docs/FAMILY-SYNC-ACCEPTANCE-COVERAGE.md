# Family Sync acceptance coverage

`FamilySyncAcceptanceCoverageMatrix` is the machine-readable release matrix.
It has one row for every field in `FamilySyncDataManifest` and exactly one
evidence item at each required level:

| Level | What counts as passed | Current state |
|---|---|---|
| Unit | A named, existing Swift test file covering the field's local rule | Passed where a concrete suite is recorded; otherwise pending |
| Integration | A named, existing Swift harness covering repository, coordinator, or CloudKit interaction | Passed where a concrete harness is recorded; disposable-cache sync-boundary checks remain pending |
| Simulator | Named Family Sync UI test plus an exact-HEAD simulator E2E artifact | Passed only for the 19 rows observed by the six-flow UI suite; every other row remains pending |
| Physical device | Exact-HEAD signed iPhone and iPad artifact | **Pending for every manifest field** |
| Human | Recorded review of sharing, account prompts, background delivery, accessibility, and recovery copy | **Pending for every manifest field** |

Source and simulator tests do not imply physical-device or human acceptance. Consequently
`FamilySyncAcceptanceCoverageMatrix.releaseAccepted` is currently `false`.

The current source batch passed all six Family Sync flows on both iPhone 17
Pro Max and iPad Pro 13-inch (M5) simulators running iOS 26.5. The matrix maps
only these observed fields to a named test method: Profile ID/name; active
Read/Write Pool membership; Read/Write settings; immutable attempts and rebuilt
progress; daily completion/reward facts; durable apply/journal state;
terminal deletion and remembered-child cleanup; badge/report projections; and
Parent sync status. The exact committed HEAD must rerun both artifacts before
merge. Profile photos, corrections/routes/aliases, causal pending facts,
CloudKit bindings/engine state, caches, voiceprints, notifications, handwriting,
Calendar, World unlocks, physical-device evidence, and human evidence remain
pending.

## Automated evidence groups

The matrix names concrete suites rather than self-referential code markers.
The major integration evidence is grouped as follows:

| Data boundary | Integration evidence |
|---|---|
| Profile and device-local voice status | `RepositoryFamilySyncRecordStoreTests` |
| Prepared Profile photo | `CloudKitProfilePhotoAssetTests` |
| Read/Write word pools and legacy aliases | `RepositoryFamilySyncWordBusinessKeyHarnessTests` |
| Settings groups | `RepositoryFamilySyncRecordStoreTests` |
| Attempts, corrections, aliases, and rebuilt progress | `RepositoryFamilySyncCausalOrderHarnessTests` |
| Daily plans, completions, and rewards | `RepositoryFamilySyncCausalOrderHarnessTests` |
| Terminal deletion and privacy | `FamilySyncDeletionDominanceHarnessTests` and `CloudKitFamilyDeletionSemanticsHarnessTests` |
| Durable outbox and two-device faults | `FamilySyncTwoDeviceFaultHarnessTests` |
| Crash-safe apply and receipts | `FamilySyncDurableReplayCoordinatorHarnessTests` |
| Cloud routing, account isolation, and durable inbox | `CloudKitFamilySyncRoutingTests` and `CloudKitFamilySyncDurableInboxHarnessTests` |
| Child/Parent UI refresh after commit | `FamilySyncUIReceiptRefreshHarnessTests` and `FamilySyncGuardianReceiptRefreshHarnessTests` |

Passing entries point to actual files below `Tests/`. The coverage test fails if
a file is missing, a manifest row lacks one of the five levels, an evidence ID
is duplicated, or a passing entry uses a generic `code:` marker.

Terminal-deletion source evidence additionally proves restart-safe,
Profile-scoped removal of transport inbox/quarantine/system/protected metadata
and staged photo sources while preserving unrelated zones. Engine pending and
outgoing changes are scrubbed by Profile zone; the opaque database-level change
token remains scoped transport state rather than being misreported as erased.

## Outstanding device gates

The six-flow simulator gate covers remote Profile/settings/pool/progress/reward
apply, offline pending state, restart recovery, quarantine, signed-out and
restricted iCloud states, and deletion-driven navigation recovery. Passing
rows name the individual method in
`Tests/TadaWordsUITests/TadaWordsFamilySyncUITests.swift`; fields that the UI
does not observe remain pending instead of inheriting a blanket pass.

The physical gate requires the same exact build on an iPhone and iPad. The
same-account private-database flow and different-account `CKShare` invitation
flow must both pass, including offline edits, reconnect in both orders,
force-quit during retry, background/foreground delivery, notification
reconciliation, and deletion while another device is offline. The source uses
Apple's production-only `UICloudSharingController`, routed to the persisted
private-owner or shared-participant root/share. Owner removal, participant
leave, and revocation still remain pending until that real UI passes on the
signed iPhone/iPad build.

The human gate additionally reviews Parent copy, VoiceOver, Dynamic Type,
account prompts, participant-removal copy, and confirms that logs/diagnostics
contain no child name, words, photo, voice sample, or voiceprint data.

To change any device or human evidence item to `passed`, record an artifact
locator tied to the exact Git commit, build configuration, OS/device, test
steps, and result. A source-only PR must leave these items pending.
