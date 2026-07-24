#!/usr/bin/env bash
set -euo pipefail

MANIFEST="${1:?Usage: inspect_teacher_audio_pack.sh path/to/manifest.json}"
PACK_ROOT="$(cd "$(dirname "$MANIFEST")" && pwd)"
MANIFEST="$PACK_ROOT/$(basename "$MANIFEST")"
MINIMUM_TAIL_SECONDS="${MINIMUM_TAIL_SECONDS:-0.06}"

for command in ffmpeg ffprobe jq shasum; do
  if ! command -v "$command" >/dev/null; then
    printf 'Required command is unavailable: %s\n' "$command" >&2
    exit 2
  fi
done

CONTAINER="$(jq -er '.audio_format.container' "$MANIFEST")"
SAMPLE_RATE="$(jq -er '.audio_format.sample_rate_hz' "$MANIFEST")"
CHANNELS="$(jq -er '.audio_format.channels' "$MANIFEST")"
PROVIDER_OUTPUT_FORMAT="$(
  jq -er '.audio_format.provider_output_format' "$MANIFEST"
)"
if [[ "$PROVIDER_OUTPUT_FORMAT" != "mp3_44100_128" ]]; then
  printf 'Unsupported provider output format\n' >&2
  exit 2
fi
BIT_RATE=128000
CANDIDATE_ONLY="$(jq -r '.candidate_only // false' "$MANIFEST")"
SEED="$(jq -r '.seed // "unseeded-candidate"' "$MANIFEST")"

if [[ "$(jq -r '.vendor' "$MANIFEST")" != "ElevenLabs" ]]; then
  printf 'Teacher-audio vendor must be ElevenLabs\n' >&2
  exit 1
fi
if [[ "$(jq -r '.model' "$MANIFEST")" != "eleven_multilingual_v2" ]]; then
  printf 'Unexpected teacher-audio model\n' >&2
  exit 1
fi
if [[ "$(jq -r '.provider_speed' "$MANIFEST")" != "0.7" ]]; then
  printf 'Teacher-audio provider speed must be 0.70\n' >&2
  exit 1
fi
if ! awk \
  -v value="$(jq -r '.client_playback_rate' "$MANIFEST")" \
  'BEGIN {target = 20 / 21; exit !(value > target - 0.000001 && value < target + 0.000001)}'
then
  printf 'Teacher-audio client playback rate must be 20/21\n' >&2
  exit 1
fi
if [[ "$(jq -r '.variants | keys | sort | join(",")' "$MANIFEST")" != \
  "read_hint,write_prompt" ]]
then
  printf 'Teacher-audio pack must contain exactly Read and Write variants\n' >&2
  exit 1
fi
if jq -e \
  'has("voice_overrides") or has("speed_overrides")' \
  "$MANIFEST" >/dev/null
then
  printf 'Per-word voice or speed overrides are forbidden\n' >&2
  exit 1
fi
if [[ "$CANDIDATE_ONLY" != "true" ]]; then
  if [[ "$(jq -r '.voice.approval' "$MANIFEST")" != "approved" ]]; then
    printf 'Shipping teacher voice requires explicit approval\n' >&2
    exit 1
  fi
  if [[ "$(jq -r '.voice.id' "$MANIFEST")" != \
    "hpp4J3VqNfWAUOO0d1Us" ]]
  then
    printf 'Shipping teacher voice must be the approved Bella identity\n' >&2
    exit 1
  fi
  if [[ "$(jq -r '.pronunciation_dictionary.id' "$MANIFEST")" != \
    "jlikgZytU86rmsPnDwrK" ]] ||
    [[ "$(jq -r '.pronunciation_dictionary.version_id' "$MANIFEST")" != \
      "E2NROj7X6ZT7VcK11GgH" ]]
  then
    printf 'Shipping teacher pack must use the approved dictionary version\n' >&2
    exit 1
  fi
  if [[ "$(jq -r '.pronunciation_dictionary.rules_sha256' "$MANIFEST")" != \
    "422ff6c9b6571fd4f3ab80a1a4d52411cc91effb946de476d668863fc747b537" ]]
  then
    printf 'Shipping dictionary rules digest is not approved\n' >&2
    exit 1
  fi
  if [[ "$(jq '.words | length' "$MANIFEST")" -ne 2000 ]]; then
    printf 'Shipping teacher pack must contain exactly 2000 words\n' >&2
    exit 1
  fi
  if [[ "$(jq '[.words[]] | unique | length' "$MANIFEST")" -ne 2000 ]] ||
    jq -e '.words[] | select(test("^[a-z]+$") | not)' "$MANIFEST" >/dev/null
  then
    printf 'Shipping teacher words must be unique normalized alphabetic entries\n' >&2
    exit 1
  fi
  if jq -e 'has("tts_text_overrides")' "$MANIFEST" >/dev/null; then
    printf 'Shipping pronunciation changes must use the versioned dictionary\n' >&2
    exit 1
  fi
  if [[ "$SEED" != "20260725" ]]; then
    printf 'Shipping teacher pack must use canonical seed 20260725\n' >&2
    exit 1
  fi
  if [[ "$(jq -r '.provider_tail_break_seconds' "$MANIFEST")" != "0" ]] ||
    [[ -n "$(jq -r '.provider_sentence_boundary' "$MANIFEST")" ]]
  then
    printf \
      'Shipping teacher provider input must contain only the isolated word\n' \
      >&2
    exit 1
  fi
  if [[ "$(jq -r '.release_post_processing.peak_dbfs' "$MANIFEST")" != "-3" ]] ||
    [[ "$(jq -r '.release_post_processing.tail_padding_seconds' "$MANIFEST")" != \
      "0.12" ]] ||
    [[ "$(jq -r '.release_post_processing.encoder' "$MANIFEST")" != \
      "libmp3lame" ]]
  then
    printf 'Shipping teacher pack release processing is not canonical\n' >&2
    exit 1
  fi
fi

case "$CONTAINER" in
  mp3)
    CODEC="mp3"
    EXTENSION="mp3"
    ;;
  m4a)
    CODEC="aac"
    EXTENSION="m4a"
    ;;
  *)
    printf 'Unsupported teacher-audio container: %s\n' "$CONTAINER" >&2
    exit 2
    ;;
esac

EXPECTED_COUNT="$(
  jq '[.words[] as $word | .variants[]] | length' "$MANIFEST"
)"
ACTUAL_COUNT=0
MINIMUM_DURATION=999
MAXIMUM_DURATION=0
MINIMUM_TAIL=999
MAXIMUM_TAIL=0
FAILURE_COUNT=0

while IFS=$'\t' read -r word directory; do
  file="$PACK_ROOT/$directory/$word.$EXTENSION"
  if [[ ! -f "$file" ]]; then
    printf 'Missing teacher-audio clip: %s\n' "$file" >&2
    FAILURE_COUNT="$((FAILURE_COUNT + 1))"
    continue
  fi

  codec="$(
    ffprobe -v error -select_streams a:0 \
      -show_entries stream=codec_name -of default=nw=1:nk=1 "$file"
  )"
  sample_rate="$(
    ffprobe -v error -select_streams a:0 \
      -show_entries stream=sample_rate -of default=nw=1:nk=1 "$file"
  )"
  channels="$(
    ffprobe -v error -select_streams a:0 \
      -show_entries stream=channels -of default=nw=1:nk=1 "$file"
  )"
  bit_rate="$(
    ffprobe -v error -select_streams a:0 \
      -show_entries stream=bit_rate -of default=nw=1:nk=1 "$file"
  )"
  duration="$(
    ffprobe -v error \
      -show_entries format=duration -of default=nw=1:nk=1 "$file"
  )"
  tail="$(
    ffmpeg -hide_banner -i "$file" \
      -af silencedetect=noise=-45dB:d=0.03 -f null - 2>&1 |
      awk '
        /silence_end:/ {last_end=$5; last_duration=$8}
        END {
          if (last_end != "") printf "%.6f", last_duration
        }
      '
  )"
  peak="$(
    ffmpeg -hide_banner -i "$file" -af volumedetect -f null - 2>&1 |
      awk '/max_volume:/ {peak=$5} END {print peak}'
  )"

  clip_failed=false
  if [[ "$codec" != "$CODEC" ||
    "$sample_rate" != "$SAMPLE_RATE" ||
    "$channels" != "$CHANNELS" ||
    "$bit_rate" != "$BIT_RATE" ]]
  then
    printf \
      'Unexpected audio format for %s: %s/%s/%s/%s\n' \
      "$file" "$codec" "$sample_rate" "$channels" "$bit_rate" >&2
    clip_failed=true
  fi
  if ! awk -v value="$duration" 'BEGIN {exit !(value >= 0.1 && value <= 5)}'; then
    printf 'Out-of-range duration for %s: %s\n' "$file" "$duration" >&2
    clip_failed=true
  fi
  if [[ -z "$tail" ]] ||
    ! awk -v value="$tail" -v minimum="$MINIMUM_TAIL_SECONDS" \
    'BEGIN {exit !(value >= minimum)}'
  then
    printf \
      'Insufficient protected tail for %s: %s\n' \
      "$file" "${tail:-none}" >&2
    clip_failed=true
  fi
  if ! awk -v value="$peak" 'BEGIN {exit !(value <= -1 && value >= -20)}'; then
    printf 'Unsafe or inaudible peak for %s: %s dB\n' "$file" "$peak" >&2
    clip_failed=true
  fi
  if [[ "$clip_failed" == true ]]; then
    FAILURE_COUNT="$((FAILURE_COUNT + 1))"
    continue
  fi

  MINIMUM_DURATION="$(
    awk -v a="$MINIMUM_DURATION" -v b="$duration" \
      'BEGIN {print (b < a ? b : a)}'
  )"
  MAXIMUM_DURATION="$(
    awk -v a="$MAXIMUM_DURATION" -v b="$duration" \
      'BEGIN {print (b > a ? b : a)}'
  )"
  MINIMUM_TAIL="$(
    awk -v a="$MINIMUM_TAIL" -v b="$tail" \
      'BEGIN {print (b < a ? b : a)}'
  )"
  MAXIMUM_TAIL="$(
    awk -v a="$MAXIMUM_TAIL" -v b="$tail" \
      'BEGIN {print (b > a ? b : a)}'
  )"
  ACTUAL_COUNT="$((ACTUAL_COUNT + 1))"
done < <(
  jq -r '
    .words[] as $word |
    .variants[] |
    [$word, .directory] | @tsv
  ' "$MANIFEST"
)

if [[ "$ACTUAL_COUNT" -ne "$EXPECTED_COUNT" ]]; then
  printf \
    'Teacher-audio clip count mismatch: expected=%s actual=%s\n' \
    "$EXPECTED_COUNT" "$ACTUAL_COUNT" >&2
  FAILURE_COUNT="$((FAILURE_COUNT + 1))"
fi

PACK_FILE_COUNT="$(
  while IFS= read -r directory; do
    find "$PACK_ROOT/$directory" -type f -name "*.$EXTENSION" -print
  done < <(jq -r '.variants[].directory' "$MANIFEST") |
    wc -l |
    tr -d ' '
)"
if [[ "$PACK_FILE_COUNT" -ne "$EXPECTED_COUNT" ]]; then
  printf \
    'Teacher-audio directory contains undeclared clips: expected=%s actual=%s\n' \
    "$EXPECTED_COUNT" "$PACK_FILE_COUNT" >&2
  FAILURE_COUNT="$((FAILURE_COUNT + 1))"
fi

if [[ "$FAILURE_COUNT" -ne 0 ]]; then
  printf 'Teacher-audio inspection failed. invalid_clips=%s\n' \
    "$FAILURE_COUNT" >&2
  exit 1
fi

printf \
  'Teacher-audio inspection passed. clips=%s duration=%s..%ss tail=%s..%ss manifest_sha256=%s\n' \
  "$ACTUAL_COUNT" \
  "$MINIMUM_DURATION" \
  "$MAXIMUM_DURATION" \
  "$MINIMUM_TAIL" \
  "$MAXIMUM_TAIL" \
  "$(shasum -a 256 "$MANIFEST" | awk '{print $1}')"
