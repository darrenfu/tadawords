#!/usr/bin/env bash
set -euo pipefail

: "${CARTESIA_API_KEY:?Set CARTESIA_API_KEY in this shell only}"

REPOSITORY_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AUDIO_ROOT="$REPOSITORY_ROOT/Sources/TadaWordsApplePlatform/Resources/Audio"
TEACHER_ROOT="$AUDIO_ROOT/TeacherWords/Katie-500-v1"
ACCENT_ROOT="$AUDIO_ROOT/VoiceAccents/Aurora-v1"
CONCURRENCY="${CARTESIA_CONCURRENCY:-3}"
API_VERSION="2026-03-01"
MODEL_ID="sonic-3.5"

is_valid_m4a() {
  local file="$1"
  [[ -s "$file" ]] &&
    ffprobe -v error \
      -select_streams a:0 \
      -show_entries stream=codec_name,sample_rate,channels \
      -of csv=p=0 "$file" 2>/dev/null |
      grep -q '^aac,44100,1$'
}

generate_clip() {
  local text="$1"
  local speed="$2"
  local voice_id="$3"
  local dictionary_id="$4"
  local output="$5"
  local emotion="${6:-}"

  if is_valid_m4a "$output"; then
    return 0
  fi

  mkdir -p "$(dirname "$output")"
  local payload wav response temporary status attempt
  payload="$(mktemp)"
  wav="$(mktemp -t tada-cartesia).wav"
  response="$(mktemp)"
  temporary="${output%.m4a}.part.m4a"
  rm -f "$temporary"

  jq -n \
    --arg text "$text" \
    --arg voice "$voice_id" \
    --arg dictionary "$dictionary_id" \
    --arg model "$MODEL_ID" \
    --arg emotion "$emotion" \
    --argjson speed "$speed" \
    '{
      model_id: $model,
      transcript: $text,
      voice: {mode: "id", id: $voice},
      output_format: {
        container: "wav",
        encoding: "pcm_s16le",
        sample_rate: 44100
      },
      language: "en",
      pronunciation_dict_id: $dictionary,
      generation_config: (
        {volume: 1, speed: $speed} +
        (if $emotion == "" then {} else {emotion: $emotion} end)
      )
    }' > "$payload"

  for attempt in 1 2 3 4 5; do
    status="$(curl -sS \
      -o "$response" \
      -w '%{http_code}' \
      https://api.cartesia.ai/tts/bytes \
      -X POST \
      -H "Authorization: Bearer $CARTESIA_API_KEY" \
      -H "Cartesia-Version: $API_VERSION" \
      -H 'Content-Type: application/json' \
      --data-binary "@$payload" || true)"

    if [[ "$status" == "200" ]]; then
      mv "$response" "$wav"
      ffmpeg -v error -y \
        -i "$wav" \
        -map_metadata -1 \
        -ac 1 \
        -ar 44100 \
        -c:a aac \
        -b:a 64k \
        "$temporary"
      mv "$temporary" "$output"
      if ! is_valid_m4a "$output"; then
        rm -f "$payload" "$wav" "$response" "$output"
        return 1
      fi
      rm -f "$payload" "$wav" "$response"
      return 0
    fi

    if [[ "$status" == "429" || "$status" =~ ^5 ]]; then
      sleep "$((attempt * 2))"
      continue
    fi

    printf 'Cartesia rejected %s with HTTP %s: ' "$output" "$status" >&2
    head -c 400 "$response" >&2 || true
    printf '\n' >&2
    rm -f "$payload" "$wav" "$response" "$temporary"
    return 1
  done

  printf 'Cartesia generation exhausted retries: %s\n' "$output" >&2
  rm -f "$payload" "$wav" "$response" "$temporary"
  return 1
}

worker() {
  local encoded="$1"
  local task text speed voice dictionary relative_path emotion
  task="$(printf '%s' "$encoded" | base64 -D)"
  text="$(jq -r '.text' <<< "$task")"
  speed="$(jq -r '.speed' <<< "$task")"
  voice="$(jq -r '.voice_id' <<< "$task")"
  dictionary="$(jq -r '.dictionary_id' <<< "$task")"
  relative_path="$(jq -r '.relative_path' <<< "$task")"
  emotion="$(jq -r '.emotion // ""' <<< "$task")"
  generate_clip \
    "$text" "$speed" "$voice" "$dictionary" \
    "$AUDIO_ROOT/$relative_path" "$emotion"
}

export -f is_valid_m4a generate_clip worker
export CARTESIA_API_KEY AUDIO_ROOT API_VERSION MODEL_ID

generate_accents() {
  local manifest="$ACCENT_ROOT/manifest.json"
  jq -r '
    . as $manifest |
    ([.launch] + .correct + [.quest_complete])[] |
    {
      text: .text,
      speed: .speed,
      emotion: (.emotion // $manifest.emotion // ""),
      voice_id: $manifest.voice.id,
      dictionary_id: $manifest.pronunciation_dictionary_id,
      relative_path: ("VoiceAccents/Aurora-v1/" + .file)
    } | @base64
  ' "$manifest" |
    xargs -n 1 -P "$CONCURRENCY" bash -c 'worker "$1"' _
}

generate_teacher_words() {
  local manifest="$TEACHER_ROOT/manifest.json"
  local word_filter="${CARTESIA_WORDS:-}"
  jq -r --arg word_filter "$word_filter" '
    . as $manifest |
    .words[] as $word |
    select(
      $word_filter == "" or
      (($word_filter | split(",") | index($word)) != null)
    ) |
    ($manifest.tts_text_overrides[$word] // $word) as $text |
    $manifest.variants | to_entries[] as $variant |
    {
      text: $text,
      speed: (
        $manifest.speed_overrides[$word][$variant.key] // $variant.value.speed
      ),
      voice_id: (
        $manifest.voice_overrides[$word].id // $manifest.voice.id
      ),
      dictionary_id: $manifest.pronunciation_dictionary_id,
      relative_path: (
        "TeacherWords/Katie-500-v1/" + $variant.value.directory + "/" + $word + ".m4a"
      )
    } | @base64
  ' "$manifest" |
    xargs -n 1 -P "$CONCURRENCY" bash -c 'worker "$1"' _
}

case "${1:-all}" in
  accents)
    generate_accents
    ;;
  teacher)
    generate_teacher_words
    ;;
  all)
    generate_accents
    generate_teacher_words
    ;;
  *)
    echo "Usage: $0 [all|teacher|accents]" >&2
    exit 2
    ;;
esac

printf 'Cartesia offline generation complete. clips=%s\n' \
  "$(find "$AUDIO_ROOT" -type f -name '*.m4a' | wc -l | tr -d ' ')"
