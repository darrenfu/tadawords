# Teacher-audio owner decisions

Status: owner-approved on 2026-07-23. The approval covers the exact voice,
dictionary, runtime boundary, quotas, retention, outage policy, and reviewed
vocabulary below. It does not substitute for exact-pack inspection, deployment
verification, physical-device acceptance, or guarded merge.

## Approved frozen voice contract

- Voice: Bella — Professional, Bright, Warm
- Voice ID: `hpp4J3VqNfWAUOO0d1Us`
- Model: `eleven_multilingual_v2`
- Seed: `20260725`
- Provider speed: `0.70`
- Provider input: the isolated normalized word only, with no text suffix
- Release processing: fixed `-3 dBFS` peak target and `0.12` second PCM tail pad
- Client playback rate: `20/21`
- Effective cadence: `2/3`
- Dictionary aliases: `a → ay`, `i → eye`, `come → kum`
- Output: MP3, 44.1 kHz, 128 kbps, mono

Evidence:

- The seeded Bella alias candidate passes 18/18 representative local
  SpeechTranscriber checks across Read and Write.
- All 18 clips pass exact format, duration, loudness, and protected-tail
  inspection.
- The owner explicitly approved Bella and the three alias rules on 2026-07-23.
- Exact shipping-pack listening on the approved iPhone and iPad remains
  mandatory.

## Approved runtime boundary

- Cloudflare Worker runtime in the owner-approved PawGoo account.
- Production hostname: `audio.pawgoo.app`.
- Development hostname: `audio-dev.pawgoo.app`.
- Production accepts only production App Attest keys and validation categories
  `2,4`.
- Development accepts only development App Attest keys and category `3`.
- Development and production use distinct Worker names, hostnames, secrets, D1,
  R2, KV, and Durable Object state.
- `workers.dev` remains disabled.

The owner explicitly approved the current PawGoo Cloudflare account and active
`pawgoo.app` zone on 2026-07-23. R2 subscription activation, Worker deployment,
and DNS creation remain separate state-changing actions and require their own
verified execution evidence.

## Approved cost and outage policy

- Global cache-miss ceiling: 500 generations and 8,000 characters per UTC day.
- Per-App-Attest-key cache-miss ceiling: 50 generations and 800 characters per
  UTC day.
- Cache hits do not consume generation budget.
- Provider timeout, circuit-open, quota exhaustion, or attestation failure is a
  typed Parent-retryable failure.
- Prepared clips remain locally playable offline.
- No Apple voice or alternative ElevenLabs voice fallback.

## Vocabulary and child-data decision

P0 policy: allow only the 1,166 owner-approved, reviewed, normalized,
non-personal catalog words. A directory-external word or non-null pronunciation
key is rejected before ElevenLabs unless a reviewed KV entry explicitly
authorizes that exact word/key pair.

This policy deliberately does not claim that every arbitrary Parent-entered
name or word is supported. Supporting arbitrary text instead requires a
separate owner-approved Parents-only disclosure/consent, deletion, retention,
and Kids privacy design. It must not be enabled implicitly.

## Retention and deletion

- Challenges: expired/consumed rows removed within 24 hours.
- App Attest keys and Apple fraud receipts: removed after 180 inactive days.
- Generation ledger: 180 days.
- Durable Object rate/budget counters: 48 hours.
- Privacy-safe Worker logs: seven days.
- R2 audio: contract lifetime; delete when the contract retires.
- ElevenLabs Creator history: provider-default retention; P0 does not claim
  Enterprise Zero Retention Mode.

Deployment requires verifying the exact Cloudflare log-retention setting and
scheduled deletion behavior against these values.

## Approval record

On 2026-07-23 the owner explicitly approved:

1. Bella, the reviewed sample, Multilingual v2, seed `20260725`, provider speed
   `0.70`, client rate `20/21`, and `a → ay`, `i → eye`, `come → kum`;
2. `audio.pawgoo.app`, `audio-dev.pawgoo.app`, the current PawGoo Cloudflare
   account/zone, and strict production/development App Attest isolation;
3. the quotas, retention windows, typed outage behavior, no fallback, and
   ElevenLabs Creator default history;
4. the 1,166-word reviewed-vocabulary boundary instead of arbitrary text.

The exact dictionary is `jlikgZytU86rmsPnDwrK`, version
`E2NROj7X6ZT7VcK11GgH`. Development must deploy and pass end-to-end verification
before production. The Release endpoint stays disabled until production
evidence passes.
