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

The Bella catalog keeps the 1,166 owner-approved, reviewed, normalized,
non-personal preset baseline across two disjoint tiers: the most common 2,000
form the offline tier and an additional 4,000 form the PawGoo tier, for 6,000
Bella words total. Parents may nevertheless add any valid isolated English word
accepted by the app's existing one-word validator. A word outside both tiers is
rejected before ElevenLabs and played with on-device Apple speech; it is never
sent to ElevenLabs. Phrases and arbitrary free text remain out of scope.

The pinned catalog is
`Tools/Audio/Catalogs/TeacherWordCatalog-4000-v1.json`, SHA-256
`679a2884c353bf6ffcefd798bbf0fa624a0b6d5e86647136ed781e2d0ca4480b`.
It preserves the existing 500 bundled words and all 1,166 preset words, then
fills by `wordfreq` 3.1.1 rank with a lowercase dictionary-membership filter and
a reviewed Bella exclusion list. Its data attribution is CC BY-SA 4.0.

## Measured offline-pack storage

The frozen 500-word baseline contains 1,000 clips totaling 19,368,518 bytes.
The expanded 2,000-word pack contains 4,000 clips totaling 82,943,086 bytes
(82.94 MB / 79.10 MiB). The earlier linear estimates are retained for scale:

| Words | MP3 clips | Audio bytes | Binary size |
| ---: | ---: | ---: | ---: |
| 1,000 | 2,000 | 38.74 MB | 36.94 MiB |
| 2,000 | 4,000 | 82.94 MB measured | 79.10 MiB measured |
| 4,000 | 8,000 | 154.95 MB | 147.77 MiB |
| 8,000 | 16,000 | 309.90 MB | 295.54 MiB |

Allow another 5–10% for manifests, signing, packaging, and filesystem overhead.
The exact disjoint tiers contain 78,794 raw two-variant characters: 22,532
offline and 56,262 online. ElevenLabs applies a 10-credit minimum to these short
isolated-word requests. Under that observed rule, the 1,500 newly generated
offline words require 30,126 credits and fully materializing the 4,000 online
words requires about 81,174 credits, or 111,300 new credits total (about USD
11.13 at the API list rate). Only the offline 2,000 must be generated before
shipping; online clips remain lazy and consume credits on their first Parent
preparation. No additional plan or credit purchase is authorized by this
estimate.

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
