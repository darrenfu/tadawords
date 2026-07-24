# Teacher-audio owner decisions

Status: owner-updated on 2026-07-24. The approval covers the exact voice,
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
- PawGoo's explicit catalog-miss response (`422`) authorizes device-local
  Apple `en-US` speech for that word. Authentication, integrity, rate-limit,
  timeout, and provider failures remain visible and never trigger fallback.
- No alternative ElevenLabs voice is permitted.

## Vocabulary and child-data decision

The Bella online catalog keeps the 1,166 owner-approved, reviewed,
normalized, non-personal preset baseline and expands to 4,000 selected words.
The most common 2,000 form the offline tier. Parents may nevertheless add any
valid isolated English word accepted by the app's existing one-word validator.
A word outside the catalog is rejected before ElevenLabs and played with
on-device Apple speech; it is never sent to ElevenLabs. Phrases and arbitrary
free text remain out of scope.

The pinned catalog is
`Tools/Audio/Catalogs/TeacherWordCatalog-4000-v1.json`, SHA-256
`cdefd533c299b5aef001d1d42020e0ca0f9645630992f583f5804763f7569499`.
It preserves the existing 500 bundled words and all 1,166 preset words, then
fills by `wordfreq` 3.1.1 rank with a lowercase dictionary-membership filter and
a reviewed Bella exclusion list. Its data attribution is CC BY-SA 4.0.

## Measured offline-pack storage

The current 500-word pack contains two MP3 variants per word. Its 1,000 clips
total 19,368,518 bytes, or 38,737 bytes per word on average. Linear estimates:

| Words | MP3 clips | Audio bytes | Binary size |
| ---: | ---: | ---: | ---: |
| 1,000 | 2,000 | 38.74 MB | 36.94 MiB |
| 2,000 | 4,000 | 77.47 MB | 73.89 MiB |
| 4,000 | 8,000 | 154.95 MB | 147.77 MiB |
| 8,000 | 16,000 | 309.90 MB | 295.54 MiB |

Allow another 5–10% for manifests, signing, packaging, and filesystem overhead.
The exact 4,000-word catalog contains 50,136 two-variant characters. After
crediting the existing 500-word pack, completing every remaining Bella clip
uses 45,902 Multilingual-v2 credits (official API list price: about USD 4.59).
Only the offline 2,000 must be generated before shipping; online-only clips may
remain lazy and consume credits on first Parent preparation.

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
3. the quotas, retention windows, typed outage behavior, and
   ElevenLabs Creator default history;
4. the 1,166-word Bella boundary instead of arbitrary provider text.

On 2026-07-24 the owner superseded the prior client restriction: any valid
isolated English word may enter a Pool, and an explicit PawGoo catalog miss
uses device-local Apple speech. The no-alternative-ElevenLabs-voice rule remains.

The exact dictionary is `jlikgZytU86rmsPnDwrK`, version
`E2NROj7X6ZT7VcK11GgH`. Development must deploy and pass end-to-end verification
before production. The Release endpoint stays disabled until production
evidence passes.
