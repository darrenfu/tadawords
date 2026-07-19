# Family Sync data manifest

This document is the human-readable contract for
`FamilySyncDataManifest`. Every new persisted Profile field must be classified
here and in the machine-readable manifest before release. It defines intended
behavior; it is not evidence that the production CloudKit schema or two-device
acceptance has passed.

## Synchronized canonical data

| Owner | Fields | Cloud representation | Merge authority |
|---|---|---|---|
| Profile | Stable ID, display name, age, grade, source avatar reference, selected/starter World, guardian World overrides, selected cartoon icon, selected Treasure avatar, created/updated audit dates. The wire DTO omits voiceprint enrollment entirely, including sentinels | Profile record plus bounded photo `CKAsset` | Persisted logical revision; preserve device voiceprint state derived from the receiving device Keychain |
| Read settings | New/review limits, order, timer | Independent settings record | Group logical revision |
| Write settings | New/review limits, order, timer | Independent settings record | Group logical revision |
| Audio settings | Parent-selected durable audio preferences | Independent settings record | Group logical revision |
| Notification settings | Parent intent only | Independent settings record | Group logical revision; receiving device reconciles OS permission and requests locally |
| Interface settings | Left-handed layout and selected handwriting/input tool | Independent settings record | Group logical revision; legacy crayon/invalid values migrate to pencil |
| Word policy | Parent-selected word-source policy | Independent settings record | Group logical revision |
| Word pool | Profile, mode, normalized word, prompt, provenance, active state, queue metadata, persisted revision | One record per stable `Profile + Mode + normalized word` business key | Per-entry logical revision; same business key cannot create two active entries |
| Learning history | Attempts and guardian corrections | Immutable event records with stable UUIDs | Set union; conflicting bytes for one UUID are quarantined |
| Daily Quest history | Daily plans, Today completions, Practice Again completions, reward grants | Stable business-key records for singleton facts; UUID records for Practice Again | Canonical key merge and immutable-event union |
| Profile deletion | Profile ID and deletion revision only | Privacy-minimal deletion ledger outside the erasable Profile zone | Terminal tombstone always dominates; payload records/assets/share/zone are erased after the barrier is durable |

Prepared Profile photos are JPEG, at most 512 by 512 pixels and 256 KiB, with
content type, dimensions, byte size, Profile ID, and checksum validated before
replacement. An invalid incoming asset is quarantined and the existing avatar
is retained. The general Family Sync envelope carries only a stable asset
reference and metadata; the JPEG travels in a CloudKit `CKAsset`. Durable
upload-source files and fully hydrated inbox bytes are device-local recovery
artifacts and are removed after acknowledgement.

A completed terminal removal also purges the target Profile's transport inbox,
quarantine envelope, protected-record lock, CloudKit system fields, and staged
photo sources. Pending/outgoing engine changes for that Profile zone are
discarded. The database-scoped opaque `CKSyncEngine` change token is retained
so deleting one Profile does not reset unrelated zones; it is routing state,
not a child payload or upload source.

## Derived data

These values are rebuilt locally and never win a conflict as transported
snapshots:

- Word mastery, accuracy and response-time aggregates, help/uncertainty counts,
  independent-success dates, and Ebbinghaus `MemoryState`.
- The durable legacy-prompt alias index used to project immutable attempts
  under canonical WordPool prompt IDs; it is rebuilt from synchronized WordPool
  entry aliases and never rewrites an Attempt event.
- Quest calendar, qualifying days, scores, stars, reports, World and cartoon
  icon unlocks, Treasure collection, badges, and selected-Treasure validity.
- Last-sync presentation and notification schedules.

Rebuilds must be deterministic, idempotent, restartable, and produce equivalent
snapshots for every arrival permutation of the same canonical facts.

## Device-local data

- Last selected Profile and transient navigation/session state.
- Family Sync consent, account confirmation, durable journal/outbox, retry
  metadata, CloudKit bindings, record system fields, inbox/quarantine, and
  private/shared `CKSyncEngine` state. Terminal removal purges the target
  Profile/zone metadata while retaining unrelated zones and the shared
  database-level change token.
- Unacknowledged CKAsset upload source files and exact remote-apply payloads;
  successful commits retain only privacy-minimal receipts.
- OS notification permission, scheduled request identifiers, push token, and
  local delivery bookkeeping.
- Voiceprint template, enrollment samples/readiness, raw microphone audio, and
  recognition buffers.
- Hidden black ink color, eraser state, unfinished canvas strokes, and other
  transient input state.
- OCR source photos and recognition output after import review.
- Picture hints, teacher-word audio, music, sound effects, and other disposable
  caches.

Account-scoped transport metadata is cleared or quarantined on account change;
it must never be replayed into a newly confirmed account. Device-local child
data remains available while Family Sync is off or unavailable.

## Release gates

Source acceptance is tracked by
[#44](https://github.com/darrenfu/tadawords/issues/44),
[#45](https://github.com/darrenfu/tadawords/issues/45),
[#42](https://github.com/darrenfu/tadawords/issues/42),
[#19](https://github.com/darrenfu/tadawords/issues/19),
[#43](https://github.com/darrenfu/tadawords/issues/43), and
[#41](https://github.com/darrenfu/tadawords/issues/41). Production schema
deployment, destructive remote-erasure proof, and same-account/different-account
physical-device acceptance remain explicit human gates. The production source
includes Apple `UICloudSharingController` access management and routes it from
the persisted private-owner or shared-participant binding; owner removal,
participant leave, and revocation still require signed physical-device and
human acceptance. Create/accept invitation tests alone are not evidence of
those destructive access transitions.

The pre-1.0 reader accepts legacy Profile payloads that included a device-local
voiceprint sentinel, ignores that key, and preserves the receiving device's
Keychain-derived state. Current writers never emit the key. Signed multi-device
acceptance requires every test device to run the same release candidate; an old
binary reading a newly emitted photo payload is not a supported mixed-version
claim for this release.
