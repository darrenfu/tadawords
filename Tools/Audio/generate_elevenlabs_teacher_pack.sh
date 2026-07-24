#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIO_ROOT="$REPOSITORY_ROOT/Sources/TadaWordsApplePlatform/Resources/Audio"
MANIFEST="${1:-$AUDIO_ROOT/TeacherWords/ElevenLabs-Teacher-2000-v1/manifest.json}"
PACK_ROOT="$(dirname "$MANIFEST")"
CONCURRENCY="${ELEVENLABS_CONCURRENCY:-1}"
WORD_FILTER="${ELEVENLABS_WORDS:-}"
KEYCHAIN_SERVICE="${ELEVENLABS_KEYCHAIN_SERVICE:-app.tadawords.audio.elevenlabs}"

if [[ ! -f "$MANIFEST" ]]; then
  printf 'Missing approved ElevenLabs manifest: %s\n' "$MANIFEST" >&2
  exit 2
fi

for command in curl ffmpeg ffprobe jq; do
  if ! command -v "$command" >/dev/null; then
    printf 'Required command is unavailable: %s\n' "$command" >&2
    exit 2
  fi
done

if [[ -z "${ELEVENLABS_API_KEY:-}" ]]; then
  ELEVENLABS_API_KEY="$(
    security find-generic-password -w -s "$KEYCHAIN_SERVICE" 2>/dev/null
  )" || {
    printf \
      'No ElevenLabs key found in the environment or Keychain service %s\n' \
      "$KEYCHAIN_SERVICE" >&2
    exit 2
  }
fi

VOICE_ID="$(jq -er '.voice.id' "$MANIFEST")"
MODEL_ID="$(jq -er '.model' "$MANIFEST")"
OUTPUT_FORMAT="$(jq -er '.audio_format.provider_output_format' "$MANIFEST")"
SEED="$(jq -er '.seed' "$MANIFEST")"
VENDOR_SPEED="$(jq -er '.provider_speed' "$MANIFEST")"
TAIL_BREAK_SECONDS="$(
  jq -er '.provider_tail_break_seconds // 0' "$MANIFEST"
)"
SENTENCE_BOUNDARY="$(
  jq -er '.provider_sentence_boundary // ""' "$MANIFEST"
)"
RELEASE_PEAK_DBFS="$(
  jq -er '.release_post_processing.peak_dbfs // empty' "$MANIFEST"
)"
RELEASE_TAIL_PADDING_SECONDS="$(
  jq -er '.release_post_processing.tail_padding_seconds // empty' "$MANIFEST"
)"
RELEASE_ENCODER="$(
  jq -er '.release_post_processing.encoder // empty' "$MANIFEST"
)"
DICTIONARY_ID="$(jq -er '.pronunciation_dictionary.id // "none"' "$MANIFEST")"
DICTIONARY_VERSION_ID="$(
  jq -er '.pronunciation_dictionary.version_id // "none"' "$MANIFEST"
)"

if [[ "$(jq -r '.vendor' "$MANIFEST")" != "ElevenLabs" ]]; then
  printf 'Manifest vendor must be ElevenLabs\n' >&2
  exit 2
fi
if [[ "$(jq -r '.candidate_only // false' "$MANIFEST")" != "true" ]] &&
  [[ "$(jq -r '.voice.approval' "$MANIFEST")" != "approved" ]]
then
  printf 'Shipping manifest voice must be explicitly approved\n' >&2
  exit 2
fi
if [[ "$(jq -r '.candidate_only // false' "$MANIFEST")" != "true" ]] &&
  { [[ "$TAIL_BREAK_SECONDS" != "0" ]] ||
    [[ -n "$SENTENCE_BOUNDARY" ]] ||
    [[ "$RELEASE_PEAK_DBFS" != "-3" ]] ||
    [[ "$RELEASE_TAIL_PADDING_SECONDS" != "0.12" ]] ||
    [[ "$RELEASE_ENCODER" != "libmp3lame" ]]; }
then
  printf \
    'Shipping audio must use isolated-word input and canonical release processing\n' \
    >&2
  exit 2
fi
if [[ "$VOICE_ID" == pending-* || "$VOICE_ID" == replace-* ]]; then
  printf 'Manifest voice must be human-approved before generation\n' >&2
  exit 2
fi
if jq -e \
  'has("voice_overrides") or has("speed_overrides")' \
  "$MANIFEST" >/dev/null
then
  printf 'Per-word voice or speed overrides are forbidden\n' >&2
  exit 2
fi
if ! [[ "$SEED" =~ ^[0-9]+$ ]] ||
  ((SEED < 0 || SEED > 4294967295))
then
  printf 'Manifest seed must be an unsigned 32-bit integer\n' >&2
  exit 2
fi

is_valid_mp3() {
  local file="$1"
  [[ -s "$file" ]] &&
    ffprobe -v error \
      -select_streams a:0 \
      -show_entries stream=codec_name,sample_rate,channels \
      -of csv=p=0 "$file" 2>/dev/null |
      grep -q '^mp3,44100,1$'
}

prepare_release_mp3() {
  local input="$1"
  local output="$2"
  local measured_peak gain

  measured_peak="$(
    ffmpeg -hide_banner -nostats \
      -i "$input" \
      -af volumedetect \
      -f null /dev/null 2>&1 |
      awk '/max_volume:/ {value=$5} END {print value}'
  )"
  if ! [[ "$measured_peak" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    printf 'Unable to measure provider audio peak: %s\n' "$input" >&2
    return 1
  fi
  gain="$(
    awk \
      -v target="$RELEASE_PEAK_DBFS" \
      -v measured="$measured_peak" \
      'BEGIN {printf "%.3f", target - measured}'
  )"
  ffmpeg -v error -y \
    -i "$input" \
    -af "volume=${gain}dB,apad=pad_dur=${RELEASE_TAIL_PADDING_SECONDS}" \
    -ar 44100 \
    -ac 1 \
    -c:a "$RELEASE_ENCODER" \
    -b:a 128k \
    "$output"
}

generate_clip() {
  local text="$1"
  local relative_path="$2"
  local output="$PACK_ROOT/$relative_path"
  local temporary="${output%.mp3}.part.mp3"
  local payload headers response status attempt provider_text

  if is_valid_mp3 "$output"; then
    return 0
  fi

  mkdir -p "$(dirname "$output")"
  payload="$(mktemp)"
  headers="$(mktemp)"
  response="$(mktemp)"
  rm -f "$temporary"
  provider_text="$text"
  if [[ "$TAIL_BREAK_SECONDS" != "0" ]]; then
    provider_text="$text$SENTENCE_BOUNDARY <break time=\"${TAIL_BREAK_SECONDS}s\" />"
  fi

  jq -n \
    --arg text "$provider_text" \
    --arg model "$MODEL_ID" \
    --arg dictionary "$DICTIONARY_ID" \
    --arg dictionary_version "$DICTIONARY_VERSION_ID" \
    --argjson seed "$SEED" \
    --argjson speed "$VENDOR_SPEED" \
    '{
      text: $text,
      model_id: $model,
      seed: $seed,
      voice_settings: {
        stability: 0.75,
        similarity_boost: 0.75,
        style: 0,
        use_speaker_boost: true,
        speed: $speed
      }
    } + (
      if $dictionary == "none" or $dictionary_version == "none" then {}
      else {
        pronunciation_dictionary_locators: [{
          pronunciation_dictionary_id: $dictionary,
          version_id: $dictionary_version
        }]
      }
      end
    )' > "$payload"

  for attempt in 1 2 3 4 5; do
    status="$(
      curl -sS \
        -D "$headers" \
        -o "$response" \
        -w '%{http_code}' \
        "https://api.elevenlabs.io/v1/text-to-speech/$VOICE_ID?output_format=$OUTPUT_FORMAT" \
        -X POST \
        -H @<(printf 'xi-api-key: %s\n' "$ELEVENLABS_API_KEY") \
        -H 'Accept: audio/mpeg' \
        -H 'Content-Type: application/json' \
        --data-binary "@$payload" || true
    )"

    if [[ "$status" == "200" ]] &&
      grep -Eiq '^content-type:[[:space:]]*audio/mpeg' "$headers"
    then
      if is_valid_mp3 "$response" &&
        prepare_release_mp3 "$response" "$temporary" &&
        is_valid_mp3 "$temporary"
      then
        mv "$temporary" "$output"
        rm -f "$payload" "$headers" "$response"
        return 0
      fi
      rm -f "$temporary"
    fi

    if [[ "$status" == "429" || "$status" =~ ^5 ]]; then
      sleep "$((attempt * 2))"
      continue
    fi

    printf 'ElevenLabs rejected %s with HTTP %s\n' "$relative_path" "$status" >&2
    rm -f "$payload" "$headers" "$response" "$temporary"
    return 1
  done

  printf 'ElevenLabs generation exhausted retries: %s\n' "$relative_path" >&2
  rm -f "$payload" "$headers" "$response" "$temporary"
  return 1
}

worker() {
  local encoded="$1"
  local task text relative_path
  task="$(printf '%s' "$encoded" | base64 -D)"
  text="$(jq -r '.text' <<< "$task")"
  relative_path="$(jq -r '.relative_path' <<< "$task")"
  generate_clip "$text" "$relative_path"
}

export -f is_valid_mp3 prepare_release_mp3 generate_clip worker
export ELEVENLABS_API_KEY VOICE_ID MODEL_ID OUTPUT_FORMAT SEED VENDOR_SPEED
export TAIL_BREAK_SECONDS SENTENCE_BOUNDARY
export RELEASE_PEAK_DBFS RELEASE_TAIL_PADDING_SECONDS RELEASE_ENCODER
export DICTIONARY_ID DICTIONARY_VERSION_ID PACK_ROOT

jq -r --arg word_filter "$WORD_FILTER" '
  . as $manifest |
  .words[] as $word |
  select(
    $word_filter == "" or
    (($word_filter | split(",") | index($word)) != null)
  ) |
  (
    if ($manifest.pronunciation_dictionary.id // "none") == "none"
    then ($manifest.tts_text_overrides[$word] // $word)
    else $word
    end
  ) as $text |
  $manifest.variants | to_entries[] as $variant |
  {
    text: $text,
    relative_path: (
      $variant.value.directory + "/" + $word + ".mp3"
    )
  } | @base64
' "$MANIFEST" |
  xargs -n 1 -P "$CONCURRENCY" bash -c 'worker "$1"' _

printf 'ElevenLabs teacher generation complete. clips=%s\n' \
  "$(find "$PACK_ROOT" -type f -name '*.mp3' | wc -l | tr -d ' ')"
