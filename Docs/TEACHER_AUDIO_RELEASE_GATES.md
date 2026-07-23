# Teacher-audio release gates

This document separates the existing bundled-audio baseline from the #74/#81
replacement. Passing source tests or retaining the legacy Katie resources does
not make the replacement ready to ship.

## Frozen contract

The final teacher contract must freeze these values together:

- one human-approved ElevenLabs voice ID;
- `eleven_multilingual_v2`;
- one approved pronunciation-dictionary ID and version;
- provider speed `0.70`;
- client playback rate `20/21`, for an effective practice cadence of `2/3`;
- contract version `elevenlabs-teacher-v1`;
- MP3 response and checksum validation;
- separate Read and Write variants for every word;
- no per-word voice or speed override and no alternative-voice fallback.

A paid monthly ElevenLabs plan is owner-confirmed. The API key remains outside
the repository and the app; the development key is restricted and stored in
the local Keychain. This confirmation does not replace voice listening,
commercial-rights, or exact-release evidence.

## Offline pack

The shipping pack contains exactly 500 normalized words × two variants = 1,000
clips. `Tools/Audio/generate_elevenlabs_teacher_pack.sh` generates only the
manifest contract. `Tools/Audio/inspect_teacher_audio_pack.sh` rejects missing
or extra clips, pending approval, wrong provider/model/speed/playback values,
local text overrides, bad encoding, unsafe duration/tail, clipping, and
inaudible output.

The repository's `Katie-500-v1` resources are the current compatibility
baseline, not the replacement pack. They remain until the approved ElevenLabs
pack is complete and the release change intentionally replaces them.

## Runtime preparation

The PawGoo runtime uses distinct production and development Workers. Production
accepts only production App Attest keys and TestFlight/App Store validation
categories. The Development-signed P0 build uses a separate hostname, Worker,
secrets, D1, R2, KV, and Durable Object state that accept only development App
Attest keys/category. Neither environment may accept the other's keys. Both
must enforce per-install rate and budget limits, deduplicate concurrent
generation, cache immutable audio by contract, validate provider responses,
fail closed under the circuit breaker, and emit only privacy-safe operational
logs.

The iOS app sends no Profile ID, child name, learning history, recording,
transcript, or provider credential. A Parent import may prepare a normalized
word, usage, and immutable contract metadata. The Pool mutation becomes visible
only after every required clip is bundled or cached. A failed preparation
leaves the prior Pool visible.

Child Quest planning and playback are strictly local. They may read the bundle
or validated cache but never start a network request. A missing, corrupt, or
mismatched clip fails visibly; it never substitutes Apple speech or another
voice.

## Open owner and deployment decisions

The exact proposal and approval record are maintained in
[`TEACHER_AUDIO_OWNER_DECISIONS.md`](TEACHER_AUDIO_OWNER_DECISIONS.md).

- Human listening must select and approve the canonical voice.
- The proposed `a → ay`, `i → eye`, and `come → kum` alias dictionary must be
  approved and created as one versioned ElevenLabs dictionary.
- The PawGoo Worker hostname and Cloudflare zone/account must be approved before
  resource creation, DNS changes, secrets, or deployment.

Until all three are resolved, the production plist must not configure
`TadaWordsTeacherAudioEndpoint`.

## Acceptance

1. Generate and inspect all 1,000 clips under the frozen contract.
2. Run the full Swift tests, formatting, lint, source inventory, and exact-pack
   inspection at the intended commit.
3. Deploy the PawGoo Worker only after its preflight, database migration, cache,
   App Attest, privacy-log, rate, budget, and circuit tests pass.
4. Configure Debug with only the verified development endpoint and Release
   with only the verified production endpoint. LocalQA remains endpoint-free.
5. Install the same PawGoo Development-signed normal build on the approved
   iPhone and iPad.
6. Prove bundled playback, Parent preparation, cache reuse, relaunch, offline
   child playback, rate-limit failure, corrupt-cache rejection, and no
   alternative voice on both device classes.
7. Re-run the privacy, content-rights, archive, and exact-HEAD release evidence
   against the unchanged candidate before guarded merge.
