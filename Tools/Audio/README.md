# Tada Words offline audio generation

This directory contains reproducible teacher-audio generators. They never store
an API key in the repository.

The two-tier word catalog is rebuilt with pinned `wordfreq` data and the pinned
macOS lowercase dictionary filter:

```bash
python3 -m venv /private/tmp/tadawords-wordfreq
/private/tmp/tadawords-wordfreq/bin/pip install wordfreq==3.1.1
/private/tmp/tadawords-wordfreq/bin/python \
  Tools/Audio/build_teacher_word_catalog.py
```

`TeacherWordCatalog-4000-v1.json` keeps the existing 500 bundled words and all
1,166 preset words across two disjoint tiers: 2,000 offline Bella words and
4,000 additional PawGoo Bella words. The union therefore covers 6,000 words;
only words outside that union use Apple speech. wordfreq code is Apache 2.0 and
its derived data is CC BY-SA 4.0; the Parent-gated Third-Party Notices screen
carries attribution.

For the approved ElevenLabs pack, store the restricted development key in the
macOS Keychain service `app.tadawords.audio.elevenlabs` (or set
`ELEVENLABS_API_KEY` only in the active shell), then run:

```bash
Tools/Audio/generate_elevenlabs_teacher_pack.sh
```

The ElevenLabs generator refuses a pending voice, any per-word voice/speed
override, a non-ElevenLabs manifest, or a non-MP3 response. It generates the
manifest's Read and Write variants separately, defaults to one concurrent
request, retries only throttling/server failures, and never prints provider
response bodies. A comma-separated `ELEVENLABS_WORDS` filter supports bounded
sample and repair runs.

Shipping manifests pin seed `20260725`. The seed is part of the immutable
voice contract and PawGoo cache identity, so a regenerated cache miss makes the
same best-effort deterministic provider request. Existing unseeded QA
candidates remain listening-only evidence and cannot become the shipping pack.
The shipping provider request contains only the isolated normalized word.
Release preparation then applies one deterministic `-3 dBFS` peak target and
120 ms PCM tail pad before the final MP3 encode. This protects the final
consonant and bounds loudness without a per-word text, speed, or voice override.
`finalize_elevenlabs_teacher_pack.sh` reproduces that release transform from a
separate raw provider pack; it refuses to overwrite its own source.

`TadaWords-Teacher-v1.pls` is the reviewable Multilingual v2 alias proposal for
the sight-word letter names `a → ay`, `i → eye`, and the short-word
disambiguation `come → kum`. Multilingual v2 does not apply
pronunciation-dictionary phoneme rules. Once an approved dictionary ID and
version are present, the generator sends the original normalized word and lets
the same server-side dictionary transform both batch and PawGoo runtime
generation. Shipping manifests may not use local `tts_text_overrides`.

Inspect every manifest-declared clip before it can become a shipping pack:

```bash
Tools/Audio/inspect_teacher_audio_pack.sh \
  Sources/TadaWordsApplePlatform/Resources/Audio/TeacherWords/ElevenLabs-Teacher-500-v1/manifest.json
```

The inspection fails closed on a missing clip, wrong codec/sample rate/channel
count, out-of-range duration, less than 60 ms of protected tail, or a clipped
or inaudible peak. Human listening and speech-recognizer checks remain separate
acceptance gates.

The Cartesia generator remains only for the independently scoped Aurora
celebration/launch assets. Its former Katie teacher path is retired so a normal
generator run cannot reintroduce an alternative teacher voice. Set
`CARTESIA_API_KEY` only in the active shell, then run:

```bash
Tools/Audio/generate_cartesia_offline_pack.sh accents
```

The generator is resumable. It skips valid AAC files, limits concurrency to
the Cartesia Pro TTS limit of three, retries rate limits/server failures, and
keeps partial responses out of the app bundle.

Teacher variant speed and tail protection are contract-owned. The ElevenLabs
replacement uses provider speed `0.70` and client playback rate `20/21`, for an
effective two-thirds cadence. The inspector requires at least 60 ms of audible
release tail and rejects unsafe or clipped output.

The Aurora launch mark is not a single unconstrained TTS render. The generator
uses the versioned Aurora `Ta-da!` clip plus a temporary `words` render, trims
their silence, makes `ta` light and level, and applies a continuous rising pitch
map to one unrepeated `da` vowel. `words` falls across three stages and joins
through an 8 ms click-safe crossfade. FFmpeg must include the `rubberband`
filter, and the Rubber Band CLI must be installed for dynamic pitch maps.
Temporary component files are deleted and never enter the App bundle.

Roles are intentionally separate:

- The approved ElevenLabs voice is the only teacher for isolated Read hints and
  Write prompts. Shipping manifests allow no per-word voice or speed override.
- Aurora remains the independently scoped launch brand mark and short
  celebratory transition accent.

Guardian-entered words outside the bundled pack are checked through PawGoo.
Bella catalog hits are cached before the Pool mutation commits; an explicit
catalog miss may commit and uses device-local Apple speech. Child playback is
local-only. Apple speech is the catalog-miss fallback, while no alternative
ElevenLabs voice is permitted.
