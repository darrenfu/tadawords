# Teacher-audio owner decisions

Status: pending explicit owner approval. None of the values below authorize an
external deployment, DNS/account mutation, secret creation, or shipping voice.

## Recommended frozen voice contract

- Voice: Bella — Professional, Bright, Warm
- Voice ID: `hpp4J3VqNfWAUOO0d1Us`
- Model: `eleven_multilingual_v2`
- Seed: `20260725`
- Provider speed: `0.70`
- Client playback rate: `20/21`
- Effective cadence: `2/3`
- Dictionary aliases: `a → ay`, `i → eye`, `come → kum`
- Output: MP3, 44.1 kHz, 128 kbps, mono

Evidence:

- The seeded Bella alias candidate passes 18/18 representative local
  SpeechTranscriber checks across Read and Write.
- All 18 clips pass exact format, duration, loudness, and protected-tail
  inspection.
- Human listening on the approved iPhone and iPad remains mandatory.

## Recommended runtime boundary

- Cloudflare Worker runtime in the owner-approved PawGoo account.
- Production hostname: `audio.pawgoo.app`.
- Development hostname: `audio-dev.pawgoo.app`.
- Production accepts only production App Attest keys and validation categories
  `2,4`.
- Development accepts only development App Attest keys and category `3`.
- Development and production use distinct Worker names, hostnames, secrets, D1,
  R2, KV, and Durable Object state.
- `workers.dev` remains disabled.

The current Cloudflare session and active `pawgoo.app` zone are discovery
evidence only. They are not deployment authority.

## Recommended cost and outage policy

- Global cache-miss ceiling: 500 generations and 8,000 characters per UTC day.
- Per-App-Attest-key cache-miss ceiling: 50 generations and 800 characters per
  UTC day.
- Cache hits do not consume generation budget.
- Provider timeout, circuit-open, quota exhaustion, or attestation failure is a
  typed Parent-retryable failure.
- Prepared clips remain locally playable offline.
- No Apple voice or alternative ElevenLabs voice fallback.

## Vocabulary and child-data decision

Recommended P0 policy: allow only the 1,166 reviewed, normalized, non-personal
catalog words. A directory-external word or non-null pronunciation key is
rejected before ElevenLabs unless a reviewed KV entry explicitly authorizes
that exact word/key pair.

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

Approval must explicitly cover:

1. the voice, sample, model, seed, speed, and dictionary;
2. the two hostnames/runtime/account and App Attest isolation;
3. quotas, retention, outage behavior, and Creator default history;
4. the reviewed-vocabulary limitation versus an expanded consent design.

After approval, replace the pending Worker values with the exact provider
dictionary/version and Cloudflare resource identifiers, provision independent
secrets, deploy development first, and keep the Release endpoint disabled until
production evidence passes.
