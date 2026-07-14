# Tada Words offline audio generation

This directory contains the reproducible Cartesia batch generator. It never
stores an API key in the repository. Set `CARTESIA_API_KEY` only in the active
shell, then run:

```bash
Tools/Audio/generate_cartesia_offline_pack.sh all
```

The generator is resumable. It skips valid AAC files, limits concurrency to
the Cartesia Pro TTS limit of three, retries rate limits/server failures, and
keeps partial responses out of the app bundle.

After changing a pronunciation dictionary, regenerate only selected words with
a comma-separated filter:

```bash
CARTESIA_WORDS=near,bun,chick \
  Tools/Audio/generate_cartesia_offline_pack.sh teacher
```

Roles are intentionally separate:

- Katie: canonical isolated word pronunciation for Read hints and Write prompts;
  manifest-declared per-word voice/speed overrides are allowed only after
  objective pronunciation QA rejects the canonical render.
- Aurora: the launch brand mark and short celebratory transition accents.

Apple `en-US` speech remains the no-network fallback for guardian-entered words
that are not present in the bundled 500-word pack.
