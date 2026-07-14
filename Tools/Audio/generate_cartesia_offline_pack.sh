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

trim_silence_to_wav() {
  local input="$1"
  local output="$2"
  ffmpeg -v error -y \
    -i "$input" \
    -af \
    'aformat=sample_rates=44100:channel_layouts=mono,
     silenceremove=start_periods=1:start_duration=0.01:start_threshold=-45dB,
     areverse,
     silenceremove=start_periods=1:start_duration=0.01:start_threshold=-45dB,
     areverse' \
    -c:a pcm_s16le \
    "$output"
}

compose_launch() {
  local ta_da_source="$1"
  local word_source="$2"
  local output="$3"
  local directory="$4"
  local ta_da_wav="$directory/ta-da.wav"
  local word_wav="$directory/word.wav"
  local temporary="${output%.m4a}.part.m4a"

  if [[ "$(ffmpeg -hide_banner -filters 2>/dev/null)" != *rubberband* ]]; then
    printf 'FFmpeg rubberband filter is required for launch prosody\n' >&2
    return 1
  fi

  trim_silence_to_wav "$ta_da_source" "$ta_da_wav"
  trim_silence_to_wav "$word_source" "$word_wav"

  local ta_da_duration word_duration syllable_boundary
  local da_first_end da_second_end word_first_end word_second_end
  ta_da_duration="$(ffprobe -v error \
    -show_entries format=duration -of default=nw=1:nk=1 "$ta_da_wav")"
  word_duration="$(ffprobe -v error \
    -show_entries format=duration -of default=nw=1:nk=1 "$word_wav")"
  syllable_boundary="$(ffmpeg -hide_banner -i "$ta_da_wav" \
    -af 'silencedetect=noise=-38dB:d=0.015' -f null - 2>&1 |
    awk '/silence_end:/ {print $5; exit}')"
  if [[ -z "$syllable_boundary" ]]; then
    syllable_boundary="$(awk -v duration="$ta_da_duration" \
      'BEGIN {printf "%.6f", duration * 0.34}')"
  fi

  read -r da_first_end da_second_end <<< "$(awk \
    -v start="$syllable_boundary" -v end="$ta_da_duration" \
    'BEGIN {
      step = (end - start) / 3
      printf "%.6f %.6f", start + step, start + (2 * step)
    }')"
  read -r word_first_end word_second_end <<< "$(awk \
    -v end="$word_duration" \
    'BEGIN {printf "%.6f %.6f", end / 3, (2 * end) / 3}')"

  rm -f "$temporary"
  ffmpeg -v error -y \
    -i "$ta_da_wav" \
    -i "$word_wav" \
    -filter_complex \
    "[0:a]atrim=start=0:end=$syllable_boundary,asetpts=PTS-STARTPTS[ta];
     [0:a]atrim=start=$syllable_boundary:end=$da_first_end,
       asetpts=PTS-STARTPTS,
       rubberband=tempo=0.70:pitch=1.00:transients=smooth:formant=preserved:pitchq=quality[da1];
     [0:a]atrim=start=$da_first_end:end=$da_second_end,
       asetpts=PTS-STARTPTS,
       rubberband=tempo=0.70:pitch=1.08:transients=smooth:formant=preserved:pitchq=quality[da2];
     [0:a]atrim=start=$da_first_end:end=$da_second_end,
       asetpts=PTS-STARTPTS,
       rubberband=tempo=0.70:pitch=1.18:transients=smooth:formant=preserved:pitchq=quality[da3];
     [da1][da2]acrossfade=d=0.020:c1=tri:c2=tri[da12];
     [da12][da3]acrossfade=d=0.020:c1=tri:c2=tri[da];
     [ta][da]concat=n=2:v=0:a=1[ta_da];
     [1:a]atrim=start=0:end=$word_first_end,
       asetpts=PTS-STARTPTS,
       rubberband=tempo=0.95:pitch=1.00:transients=smooth:formant=preserved:pitchq=quality[word1];
     [1:a]atrim=start=$word_first_end:end=$word_second_end,
       asetpts=PTS-STARTPTS,
       rubberband=tempo=0.95:pitch=0.94:transients=smooth:formant=preserved:pitchq=quality[word2];
     [1:a]atrim=start=$word_second_end:end=$word_duration,
       asetpts=PTS-STARTPTS,
       rubberband=tempo=0.95:pitch=0.88:transients=smooth:formant=preserved:pitchq=quality[word3];
     [word1][word2]acrossfade=d=0.015:c1=tri:c2=tri[word12];
     [word12][word3]acrossfade=d=0.015:c1=tri:c2=tri[words];
     [ta_da][words]acrossfade=d=0.050:c1=tri:c2=tri,
       afade=t=in:st=0:d=0.010,
       apad=pad_dur=0.060[out]" \
    -map '[out]' \
    -map_metadata -1 \
    -ar 44100 \
    -ac 1 \
    -c:a aac \
    -b:a 64k \
    "$temporary"
  mv "$temporary" "$output"
  is_valid_m4a "$output"
}

generate_launch() (
  local manifest="$ACCENT_ROOT/manifest.json"
  local output="$ACCENT_ROOT/$(jq -r '.launch.file' "$manifest")"
  if is_valid_m4a "$output"; then
    return 0
  fi

  local directory voice dictionary emotion word_text word_speed ta_da_source
  directory="$(mktemp -d -t tada-launch)"
  trap 'rm -rf "$directory"' EXIT
  voice="$(jq -r '.voice.id' "$manifest")"
  dictionary="$(jq -r '.pronunciation_dictionary_id' "$manifest")"
  emotion="$(jq -r '.emotion // ""' "$manifest")"
  word_text="$(jq -r '.launch.rendering.word_text' "$manifest")"
  word_speed="$(jq -r '.launch.rendering.word_speed' "$manifest")"
  ta_da_source="$ACCENT_ROOT/$(jq -r \
    '.launch.rendering.ta_da_source' "$manifest")"

  generate_clip \
    "$word_text" "$word_speed" "$voice" "$dictionary" \
    "$directory/word.m4a" "$emotion"
  compose_launch "$ta_da_source" "$directory/word.m4a" "$output" "$directory"
)

generate_accents() {
  local manifest="$ACCENT_ROOT/manifest.json"
  jq -r '
    . as $manifest |
    (.correct + [.quest_complete])[] |
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
  generate_launch
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
