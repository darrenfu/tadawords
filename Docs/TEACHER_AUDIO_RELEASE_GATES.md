# Teacher-audio release gates

This document separates the expanded bundled-audio artifact from the remaining
#74/#81 deployment and physical-device gates. Passing source tests or retaining
legacy QA resources does not make the replacement ready to ship.

## Frozen contract

The final teacher contract must freeze these values together:

- one human-approved ElevenLabs voice ID;
- `eleven_multilingual_v2`;
- one approved pronunciation-dictionary ID and version;
- provider speed `0.70`;
- isolated-word-only provider input with no sentence or SSML suffix;
- deterministic `-3 dBFS` peak normalization and 120 ms PCM tail padding;
- client playback rate `20/21`, for an effective practice cadence of `2/3`;
- contract version `elevenlabs-teacher-v1`;
- MP3 response and checksum validation;
- separate Read and Write variants for every word;
- no per-word ElevenLabs voice or speed override; Apple speech is the
  catalog-miss fallback only.

A paid monthly ElevenLabs plan is owner-confirmed. The API key remains outside
the repository and the app; the development key is restricted and stored in
the local Keychain. This confirmation does not replace voice listening,
commercial-rights, or exact-release evidence.

## Offline pack

The shipping pack contains exactly 2,000 normalized words × two variants =
4,000 clips. A separate, disjoint 4,000-word PawGoo tier brings total Bella
coverage to 6,000 words. The frozen 500-word manifest remains only as a
reproducibility baseline for rebuilding the disjoint catalog.
`Tools/Audio/generate_elevenlabs_teacher_pack.sh` generates only the manifest
contract. `Tools/Audio/inspect_teacher_audio_pack.sh` rejects missing or extra
clips, pending approval, wrong provider/model/speed/playback values, local text
overrides, bad encoding, unsafe duration/tail, clipping, and inaudible output.

`ElevenLabs-Teacher-2000-v1` passed the exact manifest contract, full-pack
acoustic inspection, a 20/20 representative SpeechTranscriber matrix, and the
source release-inventory digest on 2026-07-24. Physical listening on the exact
signed candidate remains mandatory.

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
only after every required word is bundled, cached, or explicitly confirmed
absent from the PawGoo catalog. Only the last case is eligible for device-local
Apple speech. Every other failed preparation leaves the prior Pool visible.

Child Quest planning and playback are strictly local. They read the bundle or
validated cache and use Apple speech for an approved catalog miss; they never
start a network request. Corrupt or mismatched clips and security/operational
failures remain visible. Apple speech is the catalog-miss fallback, not a mask
for those failures. A one-way request hash names the durable catalog-miss
marker, so a missing or corrupt Bella cache entry cannot be mistaken for an
approved Apple-speech fallback after relaunch.

## Owner decisions and remaining deployment actions

The exact proposal and approval record are maintained in
[`TEACHER_AUDIO_OWNER_DECISIONS.md`](TEACHER_AUDIO_OWNER_DECISIONS.md).

- Bella and the `a → ay`, `i → eye`, `come → kum` rules are owner-approved.
- ElevenLabs dictionary `jlikgZytU86rmsPnDwrK`, version
  `E2NROj7X6ZT7VcK11GgH`, contains the approved rules.
- The owner approved `audio.pawgoo.app`, `audio-dev.pawgoo.app`, and the current
  PawGoo Cloudflare account/zone.
- D1 and KV resources are provisioned. R2 subscription/buckets, environment
  secrets, development-first deployment, and end-to-end verification remain
  pending.

The production plist must not configure `TadaWordsTeacherAudioEndpoint` until
the production deployment and App Attest path pass end to end.

## Acceptance

1. Generate and inspect all 4,000 offline clips under the frozen contract.
2. Run the full Swift tests, formatting, lint, source inventory, and exact-pack
   inspection at the intended commit.
3. Deploy the PawGoo Worker only after its preflight, database migration, cache,
   App Attest, privacy-log, rate, budget, and circuit tests pass.
4. Configure Debug with only the verified development endpoint and Release
   with only the verified production endpoint. LocalQA remains endpoint-free.
5. Install the same PawGoo Development-signed normal build on the approved
   iPhone and iPad.
6. Prove bundled Bella playback, remote Bella preparation, cache reuse,
   relaunch, offline child playback, Apple speech for an explicit catalog miss,
   rate-limit failure, and corrupt-cache rejection on both device classes.
7. Re-run the privacy, content-rights, archive, and exact-HEAD release evidence
   against the unchanged candidate before guarded merge.
