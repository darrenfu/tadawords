# ADR-0001: Local-first Profile and Progress Sync

- **Status:** Accepted; the v0.7.0 source contract is implemented. Production CloudKit schema and physical-device acceptance remain open human gates.
- **Date:** 2026-07-13
- **Scope:** Kid Profiles, Read/Write pools, Profile settings, learning events and progress, Quest calendar, rewards, deletion, and family sharing
- **Tracking:** [Epic #40](https://github.com/darrenfu/tadawords/issues/40), [transport #44](https://github.com/darrenfu/tadawords/issues/44), [Profile data #45](https://github.com/darrenfu/tadawords/issues/45), [canonical progress #42](https://github.com/darrenfu/tadawords/issues/42), [deletion #19](https://github.com/darrenfu/tadawords/issues/19), [erasure lifecycle #57](https://github.com/darrenfu/tadawords/issues/57), [atomic apply #43](https://github.com/darrenfu/tadawords/issues/43), and [two-device acceptance #41](https://github.com/darrenfu/tadawords/issues/41)

## Context

Families may use Tada Words on more than one iPhone or iPad. A child must be able to finish a Quest without a network connection, then find the same Profile, word pools, learning history, calendar, and earned rewards on another authorized device.

Cloud sync is an enhancement, not the source of truth for a Quest. The child path must never wait for iCloud, show a blocking sync modal, or lose a locally completed attempt because a network request failed.

The v0.7.0 source implementation follows this contract. Simulator and deterministic transport evidence prove local merge and recovery behavior; they do not prove the Apple account, production CloudKit schema, push delivery, sharing, or destructive remote erasure on physical devices.

## Decision

Keep each device's inspectable local snapshots as the operational source of truth. After a local commit, a profile-scoped sync coordinator reconciles deterministic records through CloudKit. Family Sync remains off by default and is enabled separately by a parent on each device.

Use one CloudKit record zone per Profile, in the owner's private database or the accepted `CKShare` shared database. Do not add a separate app server for this implementation.

### What syncs

| Data | Cloud representation | Merge rule |
|---|---|---|
| Profile metadata, source avatar/photo, selected World/Icon/Treasure, grade and age | Mutable Profile record | Per-record logical revision; deterministic device-ID tie-break |
| Read and Write pool membership, including removal/reactivation | One mutable record per stable pool entry | Per-entry revision; normalized Profile + Mode + Word identity prevents duplicates |
| Quest, audio, notification, accessibility, and visible Profile preferences | Small mutable settings groups | Per-group revision; unrelated groups do not overwrite one another |
| Attempts and guardian corrections | Immutable records with stable UUIDs | Set union; a conflicting payload for the same UUID is quarantined and reported |
| Word progress and Ebbinghaus state | Rebuildable projection | Recompute from the merged attempt/correction history; never trust a competing snapshot as authoritative |
| Daily plan | One record per Profile + Mode + local day | Stable business key and deterministic winner; imported completions remap to the canonical plan |
| Today completion | One record per Profile + Mode + local day | Stable business key, so simultaneous offline completions cannot count twice |
| Practice Again completion | Immutable record with stable UUID | Set union |
| Reward grant | One record per Profile + World + Mode + local day | Stable business key; exactly one permanent reward per eligible Today completion |
| Calendar, World unlocks, Badge collection, scores, and reports | Derived read models | Rebuild from canonical completions, rewards, and attempts after every merge |

The last-opened Profile remains a device convenience and does not sync. OS notification requests and scheduled notification identifiers remain device-local; their parent-selected preference values sync and are reconciled separately on each device.

The selected handwriting/input tool is part of the Profile's interface settings and synchronizes. Hidden/default black ink color does not need a cloud record.

### What never syncs

- Raw microphone recordings.
- Voiceprint templates, enrollment samples, or local voiceprint readiness. Each Profile enrolls separately on each device and the template remains in that device's Keychain.
- Bundled picture-hint assets, which ship with each app version and are never cloud records.
- Downloaded canonical teacher-word audio.
- Rendered music, sound-effect, OCR, or recognition caches.

Picture hints arrive inside the app bundle and need no sync or download.
Teacher-audio caches are disposable and device-local; they are not Family Sync
payloads. A Parent flow on each receiving device prepares any Bella clip absent
from the approved bundle before the related word can become child-reachable.
Quest planning and playback never download on demand. Apple speech is the
catalog-miss fallback; corrupt, mismatched, and operational failures stay
visible.

Profile photos are not disposable caches. When a parent opts in, the prepared
source avatar is Profile data and syncs as a bounded `CKAsset`; the general
record envelope carries only its stable reference and validation metadata, not
JPEG/base64 bytes. Incoming bytes are checked against the Profile ID, content
type, dimensions, byte size, and checksum before they enter the durable inbox.

## Local-first write and outbox

1. Commit the Quest or parent edit to the local repository first.
2. Mark the Profile dirty in a durable, profile-level sync journal.
3. Return control to the child or parent without waiting for CloudKit.
4. Reconcile in the background when the app becomes active, after a parent taps **Sync now**, and after connectivity returns.
5. Clear a dirty Profile only after the resolved CloudKit write succeeds.

The sync journal stores only Profile/record keys, dirty/deleted operation and
revision, retry count/next retry, privacy-safe condition/error category, pending
count, and last attempt/success times. It contains no child nickname, word,
photo, or learning payload. Local snapshots remain the recovery fallback: at
bootstrap, a local manifest is compared with the last acknowledged manifest so
a crash between the local commit and journal update cannot silently lose a
change.

Retry uses bounded exponential backoff with jitter. A failed sync never rolls back a local write.

## Deterministic merge

Mutable records carry a persisted logical revision `(counter, deviceID)`. A local edit increments the greatest revision seen for that record. Higher counter wins; equal counters use the stable device ID. Wall-clock time remains useful for display and audit, but is not the only conflict authority.

Immutable events are unioned. Rebuildable state is regenerated after the union. Business invariants use stable record names rather than randomly generated IDs where the product permits only one result:

- `daily-plan/{profile}/{mode}/{day}`
- `today-completion/{profile}/{mode}/{day}`
- `reward/{profile}/{world}/{mode}/{day}`

All merge functions must be associative, commutative, and idempotent. Multi-device tests run the same record sets in different arrival orders and require byte-equivalent final local snapshots.

## Deletion and non-resurrection

A Profile deletion is terminal for that Profile ID. A deletion tombstone wins over every Profile record for the same ID regardless of timestamps, logical revisions, device IDs, or arrival order. Creating a child again creates a new Profile ID.

The tombstone is written before local Profile data is purged. It is retained in a small CloudKit deletion ledger containing no nickname, photo, words, or learning payload. All other private/shared Profile records are physically erased. An offline stale device must fetch the deletion ledger before it may push that Profile and must purge its local Profile, pools, settings, attempts, progress, calendar, rewards, handwriting preference, session pointer, and device voiceprint.

Do not garbage-collect a tombstone until the product has an explicit device-membership/acknowledgement protocol. Permanent minimal tombstones are the required first-release choice.

### Durable Profile-erasure lifecycle

The local deletion tombstone and a device-local, privacy-safe erasure lifecycle
are committed atomically. The lifecycle associates its Profile ID with only
state, resolved route, attempt count, retry timing, and a bounded error
category. Parent-visible status and exported diagnostics expose anonymous
aggregates only: never a Profile ID, nickname, words, photo, Apple account
identifier, share URL, or voice data.

Erasure follows this crash-safe order:

1. Persist `attemptStarted` with an unresolved route before calling CloudKit.
2. Require an exact transport disposition for the due tombstone key and
   revision, then persist the resolved owner or participant route.
3. Record the matching journal acknowledgement or failure.
4. Repair the lifecycle from the durable journal into `complete`,
   `waitingForConnection`, or `needsAttention`.

A generic transport success without an exact tombstone disposition cannot
complete erasure. This ordering also permits a restart between any two steps:
the next reconciliation replays or repairs the same idempotent operation rather
than guessing that deletion finished.

If an older build left a journal acknowledgement without durable route
evidence, migration does not call it complete. It atomically requeues the exact
tombstone, shows anonymous `needsAttention` state, and lets the next idempotent
transport pass recover an owner or participant disposition.

An owner route completes only after the deletion ledger is durable, the
Profile zone and payload assets have been erased, and the binding is terminal.
A participant route completes only after leave/revocation has been reconciled,
local participant payload assets have been purged, and the binding is terminal.
The completed state is terminal and is not requeued after an Apple-account
change.

Transport-only binding metadata preserves the originating Apple account. That
identifier never enters lifecycle state, diagnostics, or cloud payload. A
different signed-in account receives an account-category failure, needs parent
attention, and cannot acknowledge an old account's erasure. Returning to the
originating account may resume it. A genuinely fresh, never-synced unbound
Profile can resolve to the current owner route.

CloudKit deletion callbacks are account-order ambiguous. Before any live-account
lookup suspension, the client durably writes a no-payload marker containing only
the Profile ID, immutable zone/root route, origin-account fence, and observed
evidence kind. A successful fence atomically promotes that exact marker into an
explicit root, zone, or owner-ledger recovery fact. A mismatched account leaves
the marker dormant. When the origin account returns, the client directly
revalidates the exact root or control-ledger record; existence discards a false
marker, explicit absence takes the conservative owner-erase/participant-leave
route, and transient errors retain the marker. Active markers block uploads and
terminal commit removes every marker for that Profile.

For an owner ledger naming a previously unknown Profile, the deterministic
owner binding and marker are published in one metadata snapshot. The marker
records that the binding is provisional. Only an exact origin-account fetch
proving the control ledger absent may atomically remove both; an existing
binding, a legacy binding without that creation provenance, or a binding still
referenced by another marker is retained conservatively.

Offline and transient server failures remain `waitingForConnection` with a
retry time. Account, compatibility, corruption, conflict, or unknown failures
become `needsAttention`; **Try again** retains the same tombstone identity and
never recreates deleted child data. Parent UI presents only anonymous aggregate
counts and states. These source invariants still require signed Production
CloudKit acceptance on physical devices before release.

## Parent consent and visible state

Family Sync is a parent-only, sensitive action and remains off by default. Completing onboarding does not enable it. Turning it off stops future CloudKit access from this device but does not promise remote erasure; Profile deletion is the separate erasure action.

The Parent screen exposes honest, persistent states:

- **Off — this device only**
- **Syncing N changes**
- **Up to date at TIME**
- **Waiting for connection — N changes are safe on this device**
- **Sign in to iCloud to sync** / **iCloud is restricted**
- **Sync needs attention — local learning data is safe**, with **Try again**
- **Merged changes from another device**, as nonblocking recovery information

Status, pending count, last success, and privacy-safe error category survive an app restart. A parent may explicitly export a locally generated transport-state diagnostic; it never includes a child's Profile ID, words, nickname, photo, or voice data.

Malformed or identity-conflicting incoming data is quarantined instead of overwriting valid local data. The Parent screen reports that sync needs attention and offers retry/exported diagnostics; the child can continue practicing.

### Client and schema compatibility

Cloud records use a checksummed v2 envelope with an explicit schema version,
minimum readable version, bounded payload size, record kind, and logical
revision. Older compatible snapshots migrate before export. A client that sees
an unknown future kind or schema quarantines it without overwriting valid local
data. `letterKeyboard` remains a distinct attempt pace context; it is never
silently rewritten as handwriting for an older client.

## v0.7.0 implementation audit

| Area | Source implementation | Remaining live acceptance |
|---|---|---|
| Local-first boundary | Atomic local repositories, durable manifest comparison, exact-operation outbox, retry/backoff, separate private/shared engine state, and crash replay | Force-quit and reconnect on signed physical devices |
| Parent consent and status | Default-off per-device consent, parent authorization, durable pending/condition/retry/last-success state, Sync now, invitation actions, privacy-safe diagnostics export, recovery copy, and production-only Apple `UICloudSharingController` access management routed through the persisted owner/participant binding. Save/stop-sharing delegate events enter the same idempotent notification-reconciliation path used by background delivery. | Signed owner/participant access-management and revocation acceptance; human review of account prompts, sharing, VoiceOver, and background delivery |
| Profile/settings/pools | Stable Profile identity; independently mergeable settings groups; Profile-scoped handwriting tool; stable word business keys, revisions, aliases, deduplication, and removal/reactivation | Same-account and shared-account physical convergence |
| Profile photo | 512 px / 256 KiB prepared JPEG, general-envelope stripping, validated `CKAsset`, durable upload source, corrupt-asset quarantine, and acknowledgement cleanup | Physical photo transfer through the real container |
| Learning history | Immutable attempt/correction union, conflict quarantine, prompt-alias migration, deterministic progress and Ebbinghaus rebuild | Two devices completing real Read/Write Quests offline in both reconnect orders |
| Plans, completion, and rewards | Stable business keys, causal staging, deterministic calendar/world/badge/collection projections, and Practice Again UUID semantics | Physical calendar/reward comparison after background reconciliation |
| Deletion | Local ledger-before-purge, unconditional tombstone dominance, durable privacy-safe erasure lifecycle, exact owner/participant acknowledgement, account-provenance guard, restart repair, terminal completion, and stale-device upload barrier | Explicitly authorized test-only destructive CloudKit proof, including account switch-away/back and offline restart |
| Remote apply and UI | Profile-scoped durable apply transaction, exact pending bytes, commit receipts, bootstrap replay, notification reconciliation, and immediate Kid/Parent refresh without abandoning an active Quest | Real push/background delivery and human navigation recovery checks |
| Coverage | Machine-readable data manifest and five-layer acceptance matrix plus deterministic retry, corruption, ordering, restart, account, route, and two-device harnesses. Six Family Sync UI flows pass on both target simulators in the source batch, and only the 19 directly observed manifest rows receive simulator evidence. | Exact committed-HEAD simulator artifacts are mandatory delivery evidence; every matrix row still marked simulator, physical, or human remains pending |
| LocalQA | Explicit device-only bundle, no iCloud/APNs entitlement, safe simulator and signed-device UI validation | It intentionally cannot prove CloudKit behavior |

The source sequence in #44, #45, #42, #19, and #43 is implemented together in
v0.7.0 so the invariants are reviewed and tested as one coherent data contract.
The automated release gate is tracked in #41 and in the
[Family Sync acceptance matrix](FAMILY-SYNC-ACCEPTANCE-COVERAGE.md). Production acceptance remains the final
step; no simulator or fake transport result is promoted to live evidence.

## Required acceptance

Automated acceptance must cover opt-out, restartable outbox, offline retry, same-record conflict, different-record union, event-derived progress, duplicate Today completion, reward idempotency, deletion beating a later stale edit, corrupt remote quarantine, and convergence under permuted arrival order.

Live acceptance requires:

1. A paid Apple Developer Program Team with `iCloud.com.tadawords.app` attached to the App ID.
2. CloudKit development schema deployed and entitlements verified in a normally signed Release/TestFlight build. `TadaWordsLocalQA` is not sufficient.
3. Two physical devices on one iCloud account for private-database sync.
4. Two physical devices on different iCloud accounts for invitation/share acceptance.
5. Validate the production-only Apple `CKShare` access-management UI as both owner and participant; revoke/remove access and prove the persisted route becomes terminal without creating a private fallback.
6. Offline edits on both devices, reconnect in both orders, force-quit/restart during retry, opt-out/re-enable, and lost-network recovery.
7. Delete a Profile while another device is offline; prove the stale device cannot resurrect it and that non-tombstone cloud records are erased.
8. Confirm voiceprints remain independently enrolled per device and picture/teacher-audio caches re-download instead of syncing.

Until all eight live steps pass, product copy and release notes must describe Family Sync as under acceptance, not complete.
