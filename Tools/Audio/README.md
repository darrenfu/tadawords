# Tada Words offline audio generation

This directory contains reproducible teacher-audio generators. They never store
an API key in the repository.

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

The legacy Cartesia generator remains for the independently scoped Aurora
celebration/launch assets. Set `CARTESIA_API_KEY` only in the active shell, then
run:

```bash
Tools/Audio/generate_cartesia_offline_pack.sh all
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

After changing a pronunciation dictionary, regenerate only selected words with
a comma-separated filter:

```bash
CARTESIA_WORDS=near,bun,chick \
  Tools/Audio/generate_cartesia_offline_pack.sh teacher
```

Roles are intentionally separate:

- The approved ElevenLabs voice is the only teacher for isolated Read hints and
  Write prompts. Shipping manifests allow no per-word voice or speed override.
- Aurora remains the independently scoped launch brand mark and short
  celebratory transition accent.

Guardian-entered words outside the bundled 500-word pack must be prepared
through PawGoo and cached before the Pool mutation commits. Child playback is
local-only and has no Apple or alternative-voice fallback.
