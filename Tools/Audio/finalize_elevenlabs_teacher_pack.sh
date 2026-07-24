#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
  printf 'Usage: %s RAW_PACK_ROOT [SHIPPING_MANIFEST]\n' "$0" >&2
  exit 2
fi

REPOSITORY_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIO_ROOT="$REPOSITORY_ROOT/Sources/TadaWordsApplePlatform/Resources/Audio"
RAW_PACK_ROOT="$(cd "$1" && pwd)"
MANIFEST="$(
  cd "$(dirname "${2:-$AUDIO_ROOT/TeacherWords/ElevenLabs-Teacher-500-v1/manifest.json}")"
  printf '%s/%s\n' "$PWD" "$(basename "${2:-$AUDIO_ROOT/TeacherWords/ElevenLabs-Teacher-500-v1/manifest.json}")"
)"
PACK_ROOT="$(dirname "$MANIFEST")"
CONCURRENCY="${TEACHER_AUDIO_FINALIZE_CONCURRENCY:-4}"

for command in ffmpeg ffprobe jq; do
  if ! command -v "$command" >/dev/null; then
    printf 'Required command is unavailable: %s\n' "$command" >&2
    exit 2
  fi
done
if [[ ! -f "$MANIFEST" ]]; then
  printf 'Missing shipping manifest: %s\n' "$MANIFEST" >&2
  exit 2
fi
if [[ "$RAW_PACK_ROOT" == "$PACK_ROOT" ]]; then
  printf 'Raw and shipping pack roots must be different\n' >&2
  exit 2
fi
if ! [[ "$CONCURRENCY" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Finalization concurrency must be a positive integer\n' >&2
  exit 2
fi

RELEASE_PEAK_DBFS="$(jq -er '.release_post_processing.peak_dbfs' "$MANIFEST")"
RELEASE_TAIL_PADDING_SECONDS="$(
  jq -er '.release_post_processing.tail_padding_seconds' "$MANIFEST"
)"
RELEASE_ENCODER="$(jq -er '.release_post_processing.encoder' "$MANIFEST")"
if [[ "$RELEASE_PEAK_DBFS" != "-3" ]] ||
  [[ "$RELEASE_TAIL_PADDING_SECONDS" != "0.12" ]] ||
  [[ "$RELEASE_ENCODER" != "libmp3lame" ]]
then
  printf 'Shipping release processing is not canonical\n' >&2
  exit 2
fi

finalize_clip() {
  local relative_path="$1"
  local input="$RAW_PACK_ROOT/$relative_path"
  local output="$PACK_ROOT/$relative_path"
  local temporary="${output%.mp3}.finalizing.mp3"
  local measured_peak gain

  if [[ ! -f "$input" ]]; then
    printf 'Missing raw provider clip: %s\n' "$input" >&2
    return 1
  fi
  measured_peak="$(
    ffmpeg -hide_banner -nostats \
      -i "$input" \
      -af volumedetect \
      -f null /dev/null 2>&1 |
      awk '/max_volume:/ {value=$5} END {print value}'
  )"
  if ! [[ "$measured_peak" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    printf 'Unable to measure raw provider audio peak: %s\n' "$input" >&2
    return 1
  fi
  gain="$(
    awk \
      -v target="$RELEASE_PEAK_DBFS" \
      -v measured="$measured_peak" \
      'BEGIN {printf "%.3f", target - measured}'
  )"
  mkdir -p "$(dirname "$output")"
  rm -f "$temporary"
  ffmpeg -v error -y \
    -i "$input" \
    -af "volume=${gain}dB,apad=pad_dur=${RELEASE_TAIL_PADDING_SECONDS}" \
    -ar 44100 \
    -ac 1 \
    -c:a "$RELEASE_ENCODER" \
    -b:a 128k \
    "$temporary"
  if ! ffprobe -v error \
    -select_streams a:0 \
    -show_entries stream=codec_name,sample_rate,channels \
    -of csv=p=0 "$temporary" 2>/dev/null |
    grep -q '^mp3,44100,1$'
  then
    printf 'Finalized clip has an invalid format: %s\n' "$relative_path" >&2
    rm -f "$temporary"
    return 1
  fi
  mv "$temporary" "$output"
}

export -f finalize_clip
export RAW_PACK_ROOT PACK_ROOT RELEASE_PEAK_DBFS
export RELEASE_TAIL_PADDING_SECONDS RELEASE_ENCODER

jq -r '
  .words[] as $word |
  .variants[] |
  .directory + "/" + $word + ".mp3"
' "$MANIFEST" |
  xargs -n 1 -P "$CONCURRENCY" bash -c 'finalize_clip "$1"' _

printf 'Teacher-audio release finalization complete. clips=%s\n' \
  "$(find "$PACK_ROOT" -type f -name '*.mp3' | wc -l | tr -d ' ')"
