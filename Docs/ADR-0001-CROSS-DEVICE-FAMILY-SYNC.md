# ADR-0001: Local-first Profile and Progress Sync

- **Status:** Proposed for v0.3; implementation and live CloudKit acceptance are incomplete
- **Date:** 2026-07-13
- **Scope:** Kid Profiles, Read/Write pools, Profile settings, learning events and progress, Quest calendar, rewards, deletion, and family sharing

## Context

Families may use Tada Words on more than one iPhone or iPad. A child must be able to finish a Quest without a network connection, then find the same Profile, word pools, learning history, calendar, and earned rewards on another authorized device.

Cloud sync is an enhancement, not the source of truth for a Quest. The child path must never wait for iCloud, show a blocking sync modal, or lose a locally completed attempt because a network request failed.

The repository already contains a meaningful sync foundation. This ADR distinguishes that foundation from the work still required before cross-device sync can be called complete.

## Decision

Keep each device's inspectable local snapshots as the operational source of truth. After a local commit, a profile-scoped sync coordinator reconciles deterministic records through CloudKit. Family Sync remains off by default and is enabled separately by a parent on each device.

Use one CloudKit record zone per Profile, in the owner's private database or the accepted `CKShare` shared database. Do not add a separate app server for v0.3.

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

The selected handwriting tool should move into the Profile's interface settings when this feature is implemented. Hidden/default ink color does not need a cloud record.

### What never syncs

- Raw microphone recordings.
- Voiceprint templates, enrollment samples, or local voiceprint readiness. Each Profile enrolls separately on each device and the template remains in that device's Keychain.
- Downloaded picture hints.
- Downloaded canonical teacher-word audio.
- Rendered music, sound-effect, OCR, or recognition caches.

Picture and teacher-audio caches are disposable. A receiving device downloads an eligible asset on demand and continues with its offline fallback if the asset is unavailable.

Profile photos are not disposable caches. When a parent opts in, the prepared source avatar is Profile data and syncs; move it to a bounded `CKAsset` before production acceptance rather than embedding an unbounded image in a general payload.

## Local-first write and outbox

1. Commit the Quest or parent edit to the local repository first.
2. Mark the Profile dirty in a durable, profile-level sync journal.
3. Return control to the child or parent without waiting for CloudKit.
4. Reconcile in the background when the app becomes active, after a parent taps **Sync now**, and after connectivity returns.
5. Clear a dirty Profile only after the resolved CloudKit write succeeds.

The sync journal stores only Profile ID, dirty/deleted state, first/last queued time, retry count, next retry time, and last successful sync time. Local snapshots remain the recovery fallback: at bootstrap, a local manifest is compared with the last acknowledged manifest so a crash between the local commit and journal update cannot silently lose a change.

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

Do not garbage-collect a tombstone until the product has an explicit device-membership/acknowledgement protocol. Permanent minimal tombstones are the simpler v0.3 choice.

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

Status, pending count, last success, and privacy-safe error category survive an app restart. Detailed diagnostics stay on device and never include a child's words, nickname, photo, or voice data.

Malformed or identity-conflicting incoming data is quarantined instead of overwriting valid local data. The Parent screen reports that sync needs attention and offers retry/exported diagnostics; the child can continue practicing.

## Existing implementation audit

| Area | Present in the repository | Gap before completion |
|---|---|---|
| Local-first boundary | Quest and parent data live in atomic local JSON snapshots; sync runs after local work | No durable dirty-profile journal or persisted sync status |
| Parent consent | Persisted, versioned, default-off opt-in; corrupt preference fails closed | Needs signed Release device acceptance |
| Record coverage | Profiles, inactive/active pool entries, settings, attempts, corrections, progress, daily plans/completions, rewards, and Profile deletion records export | Settings are one coarse snapshot; pen preference is outside it; photo needs bounded asset handling |
| Conflict resolver | Timestamp, deletion-on-tie, device ID, and payload tie-break are deterministic | Newer stale Profile data can beat an older tombstone; clock skew is authoritative; no semantic business-key convergence tests |
| Learning history | Attempts/corrections use stable immutable IDs | Synced progress is currently last-writer-wins instead of rebuilt from the merged event history |
| Calendar/rewards | Plans, completions, and rewards are transported and incoming plan IDs are remapped | Simultaneous offline Today completions/rewards can violate one-per-day invariants and fail a sync apply |
| Profile deletion | Durable local tombstone, crash recovery, local purge, and outbound deletion record exist | Cloud child records are not physically erased; deletion is not unconditional; remote apply does not immediately refresh every child/session surface |
| Voiceprint | Export scrubs enrollment status; import preserves the local status; template is device Keychain data | Each real device still needs enrollment and deletion acceptance |
| CloudKit | Private/shared databases, per-Profile zone/root, query pagination, push, create invitation, and accept invitation exist | Only routing logic is unit-tested; no paid-Team/container/schema/two-device acceptance evidence |
| UI | Parent opt-in, manual sync, invitation, offline/unavailable/failure states exist | Status is actor-memory only; no pending count, durable retry state, conflict recovery receipt, or device list |
| LocalQA | Simulator and LocalQA intentionally use device-only transport and no iCloud entitlement | LocalQA can never prove cross-device sync |

## Minimal implementation sequence

1. Make Profile deletion unconditional in conflict resolution and add a deletion ledger plus CloudKit child-record erasure.
2. Add record schema versions, logical revisions, and a durable profile-level sync journal/status snapshot.
3. Add per-entry pool revisions and split settings into independently mergeable groups.
4. Stop treating synced `WordProgress` as authoritative; rebuild all progress from the merged attempts and corrections.
5. Introduce stable daily-plan, Today-completion, and reward business record names; add order-independent two-device convergence tests.
6. Refresh Profile/session/notification/UI projections immediately after applying remote records.
7. Complete real CloudKit acceptance before changing the feature status to implemented.

## Required acceptance

Automated acceptance must cover opt-out, restartable outbox, offline retry, same-record conflict, different-record union, event-derived progress, duplicate Today completion, reward idempotency, deletion beating a later stale edit, corrupt remote quarantine, and convergence under permuted arrival order.

Live acceptance requires:

1. A paid Apple Developer Program Team with `iCloud.com.tadawords.app` attached to the App ID.
2. CloudKit development schema deployed and entitlements verified in a normally signed Release/TestFlight build. `TadaWordsLocalQA` is not sufficient.
3. Two physical devices on one iCloud account for private-database sync.
4. Two physical devices on different iCloud accounts for invitation/share acceptance.
5. Offline edits on both devices, reconnect in both orders, force-quit/restart during retry, opt-out/re-enable, and lost-network recovery.
6. Delete a Profile while another device is offline; prove the stale device cannot resurrect it and that non-tombstone cloud records are erased.
7. Confirm voiceprints remain independently enrolled per device and picture/teacher-audio caches re-download instead of syncing.

Until all seven live steps pass, product copy and release notes must describe Family Sync as under acceptance, not complete.

