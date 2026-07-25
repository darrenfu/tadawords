#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
production_plist="$repo_root/Apps/TadaWordsApp/Info.plist"
localqa_plist="$repo_root/Apps/TadaWordsApp/InfoLocalQA.plist"
audio_relative="Sources/TadaWordsApplePlatform/Resources/Audio"
picture_relative="Sources/TadaWordsApplePlatform/Resources/PictureHints/Twemoji-17.0.3"
preset_relative="Sources/TadaWordsContent/Resources/PresetWords.json"
compatibility_relative="Apps/TadaWordsApp/PersistenceSchemaCompatibility.json"
guardian_notice_relative="Sources/TadaWordsGuardianFeatures/GuardianThirdPartyNoticesView.swift"
expected_teacher_audio_endpoint="https://audio.pawgoo.app"
zodiac_master_relative="DesignAssets/ZodiacAvatars/zodiac-avatar-master.png"
zodiac_readme_relative="DesignAssets/ZodiacAvatars/README.md"
zodiac_assets_relative="Apps/TadaWordsApp/Assets.xcassets"
rights_inventory_relative="Docs/APP_STORE_CONTENT_RIGHTS.md"

expected_audio_digest="4c2f6768dedf79c541cc63e8038b34d45f33105391b3a664abc6e6cd53a9b662"
expected_picture_digest="fbe89ce4496e0f50a59f93b3dc55f2e3e24eb1bcd463597c218a40e5f19d7a1a"
expected_zodiac_export_digest="68dc7150c9eb6403bded39ca61381ec40466953c26d14f6b5d67a455a930c142"

fail() {
    echo "content-inventory verification failed: $*" >&2
    exit 1
}

assert_equal() {
    local actual="$1"
    local expected="$2"
    local label="$3"
    [[ "$actual" == "$expected" ]] || fail "$label: expected $expected, found $actual"
}

assert_file() {
    [[ -f "$1" ]] || fail "missing $2: $1"
}

assert_sha256() {
    local path="$1"
    local expected="$2"
    local label="$3"
    local actual
    actual="$(shasum -a 256 "$path" | awk '{print $1}')"
    assert_equal "$actual" "$expected" "$label SHA-256"
}

count_files() {
    find "$1" -type f -name "$2" | awk 'END { print NR + 0 }'
}

stable_tree_digest() {
    local root="$1"
    local pattern="$2"
    (
        cd "$root"
        find . -type f -name "$pattern" -print \
            | LC_ALL=C sort \
            | while IFS= read -r path; do
                shasum -a 256 "$path"
            done
    ) | shasum -a 256 | awk '{print $1}'
}

stable_audio_tree_digest() {
    local root="$1"
    (
        cd "$root"
        find . -type f \( -name '*.mp3' -o -name '*.m4a' \) -print \
            | LC_ALL=C sort \
            | while IFS= read -r audio_file; do
                shasum -a 256 "$audio_file"
            done
    ) | shasum -a 256 | awk '{print $1}'
}

stable_path_digest() {
    local root="$1"
    local path_pattern="$2"
    (
        cd "$root"
        find . -type f -path "$path_pattern" -print \
            | LC_ALL=C sort \
            | while IFS= read -r file_path; do
                shasum -a 256 "$file_path"
            done
    ) | shasum -a 256 | awk '{print $1}'
}

verify_picture_pack() {
    local picture_root="$1"
    local manifest="$picture_root/manifest.json"
    local png_codes="$scratch/png-codes.txt"
    local manifest_codes="$scratch/manifest-codes.txt"

    assert_file "$manifest" "Twemoji manifest"
    assert_file "$picture_root/README.md" "Twemoji provenance README"
    assert_file "$picture_root/LICENSE-GRAPHICS.txt" "Twemoji graphics license"
    assert_equal "$(count_files "$picture_root" '*.png')" "74" "Twemoji PNG count"
    assert_equal "$(find "$picture_root" -maxdepth 1 -type f | awk 'END { print NR + 0 }')" "77" "Twemoji pack file count"
    assert_equal "$(jq -r '.name' "$manifest")" "Twemoji" "Twemoji manifest name"
    assert_equal "$(jq -r '.version' "$manifest")" "17.0.3" "Twemoji version"
    assert_equal "$(jq -r '.source_repository' "$manifest")" "https://github.com/jdecked/twemoji" "Twemoji source repository"
    assert_equal "$(jq -r '.source_commit' "$manifest")" "b6b55fef1e8636b540a6d016a4729ca8cdf2e60b" "Twemoji source commit"
    assert_equal "$(jq -r '.license' "$manifest")" "CC-BY-4.0" "Twemoji license"
    assert_equal "$(jq '.asset_codes | length' "$manifest")" "74" "Twemoji manifest asset count"
    assert_equal "$(jq '[.asset_codes[]] | unique | length' "$manifest")" "74" "Twemoji unique asset count"

    jq -r '.asset_codes[]' "$manifest" | LC_ALL=C sort >"$manifest_codes"
    find "$picture_root" -maxdepth 1 -type f -name '*.png' -print \
        | while IFS= read -r path; do
            basename "${path%.png}"
        done \
        | LC_ALL=C sort >"$png_codes"
    cmp -s "$manifest_codes" "$png_codes" \
        || fail "Twemoji manifest codes do not exactly match bundled PNG filenames"

    assert_sha256 "$manifest" "e2232045781f9984879eedcee3ae4cd410aa506daa77710e53f06759a29f7a27" "Twemoji manifest"
    assert_sha256 "$picture_root/LICENSE-GRAPHICS.txt" "8ae9438818c26e4873b91d8c6ad620526c011e27e125677f13031eda903f007c" "Twemoji license"
    assert_equal "$(stable_tree_digest "$picture_root" '*')" "$expected_picture_digest" "Twemoji complete-pack digest"
}

verify_audio_pack() {
    local audio_root="$1"
    local teacher_root="$audio_root/TeacherWords/ElevenLabs-Teacher-2000-v1"
    local aurora_root="$audio_root/VoiceAccents/Aurora-v1"
    local teacher_manifest="$teacher_root/manifest.json"
    local aurora_manifest="$aurora_root/manifest.json"

    assert_file "$teacher_manifest" "ElevenLabs teacher manifest"
    assert_file "$aurora_manifest" "Aurora manifest"
    assert_equal "$(jq -r '.vendor' "$teacher_manifest")" "ElevenLabs" "teacher vendor"
    assert_equal "$(jq -r '.model' "$teacher_manifest")" "eleven_multilingual_v2" "teacher model"
    assert_equal "$(jq -r '.voice.id' "$teacher_manifest")" "hpp4J3VqNfWAUOO0d1Us" "teacher voice"
    assert_equal "$(jq -r '.voice.approval' "$teacher_manifest")" "approved" "teacher approval"
    assert_equal "$(jq -r '.pack_version' "$teacher_manifest")" "3.0.0" "teacher pack version"
    assert_equal "$(jq -r '.created_on' "$teacher_manifest")" "2026-07-24" "teacher creation date"
    assert_equal "$(jq -r '.seed' "$teacher_manifest")" "20260725" "teacher seed"
    assert_equal "$(jq -r '.pronunciation_dictionary.id' "$teacher_manifest")" "jlikgZytU86rmsPnDwrK" "teacher dictionary"
    assert_equal "$(jq -r '.pronunciation_dictionary.version_id' "$teacher_manifest")" "E2NROj7X6ZT7VcK11GgH" "teacher dictionary version"
    assert_equal "$(jq -r '.release_post_processing.peak_dbfs' "$teacher_manifest")" "-3" "teacher release peak"
    assert_equal "$(jq -r '.release_post_processing.tail_padding_seconds' "$teacher_manifest")" "0.12" "teacher release tail"
    assert_equal "$(jq '.words | length' "$teacher_manifest")" "2000" "teacher manifest words"
    assert_equal "$(jq '[.words[]] | unique | length' "$teacher_manifest")" "2000" "teacher unique words"
    assert_equal "$(count_files "$teacher_root/read-hint" '*.mp3')" "2000" "teacher Read clips"
    assert_equal "$(count_files "$teacher_root/write-prompt" '*.mp3')" "2000" "teacher Write clips"
    assert_sha256 "$teacher_manifest" "6d973e4b40749af02bf3dee7ec2208443ae4a7ad686c8ac396be4cd73883d82b" "teacher manifest"

    while IFS= read -r word; do
        assert_file "$teacher_root/read-hint/$word.mp3" "Read clip for $word"
        assert_file "$teacher_root/write-prompt/$word.mp3" "Write clip for $word"
    done < <(jq -r '.words[]' "$teacher_manifest")

    assert_equal "$(jq -r '.vendor' "$aurora_manifest")" "Cartesia" "Aurora vendor"
    assert_equal "$(jq -r '.model' "$aurora_manifest")" "sonic-3.5" "Aurora model"
    assert_equal "$(jq -r '.voice.name' "$aurora_manifest")" "Aurora" "Aurora voice"
    assert_equal "$(jq -r '.pack_version' "$aurora_manifest")" "1.1.0" "Aurora pack version"
    assert_equal "$(jq -r '.created_on' "$aurora_manifest")" "2026-07-14" "Aurora creation date"
    assert_equal "$(jq '.correct | length' "$aurora_manifest")" "5" "Aurora positive transitions"
    while IFS= read -r relative_path; do
        assert_file "$aurora_root/$relative_path" "Aurora file $relative_path"
    done < <(
        jq -r '[.launch.file, .launch.rendering.ta_da_source, .correct[].file, .quest_complete.file] | unique[]' "$aurora_manifest"
    )
    assert_equal "$(count_files "$aurora_root" '*.m4a')" "8" "Aurora clip count"
    assert_equal "$(count_files "$audio_root" '*.mp3')" "4000" "total bundled MP3 clips"
    assert_equal "$(count_files "$audio_root" '*.m4a')" "8" "total bundled M4A clips"
    assert_equal "$(stable_audio_tree_digest "$audio_root")" "$expected_audio_digest" "complete audio digest"
}

verify_preset_catalog() {
    local preset_catalog="$1"
    assert_file "$preset_catalog" "preset catalog"
    assert_equal "$(jq '.roots | length' "$preset_catalog")" "5" "preset root categories"
    assert_equal "$(jq '[.. | objects | select(has("words") and has("title"))] | length' "$preset_catalog")" "34" "preset leaf catalogs"
    assert_equal "$(jq '[.. | objects | select(has("words") and has("title")) | .words | length] | add' "$preset_catalog")" "1365" "preset word references"
    assert_equal "$(jq '[.. | objects | select(has("words") and has("title")) | .words[] | ascii_downcase] | unique | length' "$preset_catalog")" "1166" "preset unique normalized words"
    assert_equal "$(jq '.sources | length' "$preset_catalog")" "7" "preset method sources"
    assert_sha256 "$preset_catalog" "f5b0a273a816d97de265f82f8a16d56bc45cbc2be19d585dfda05449827e3fd0" "preset catalog"
}

verify_parent_notice_route() {
    local guardian_model="$1"
    local route_result
    route_result="$(
        awk '
            function finish_case() {
                if (case_has_notice && case_has_app_and_family) {
                    route_found = 1
                }
                case_has_notice = 0
                case_has_app_and_family = 0
            }

            /var parentSectionForBack: GuardianParentSection\?/ {
                in_parent_mapping = 1
                next
            }

            in_parent_mapping && /^        case / {
                finish_case()
            }

            in_parent_mapping && index($0, ".thirdPartyNotices") {
                case_has_notice = 1
            }

            in_parent_mapping && index($0, ".appAndFamily") {
                case_has_app_and_family = 1
            }

            in_parent_mapping && /^    }$/ {
                finish_case()
                in_parent_mapping = 0
            }

            END {
                if (route_found) {
                    print "routed"
                }
            }
        ' "$guardian_model"
    )"
    [[ "$route_result" == "routed" ]] \
        || fail "Third-Party Notices is not routed back to App & Family"
}

if [[ "${1:-}" == "--verify-parent-notice-route" ]]; then
    [[ "$#" -eq 2 ]] \
        || fail "usage: $0 --verify-parent-notice-route GuardianDashboardViewModel.swift"
    command -v awk >/dev/null || fail "awk is required"
    verify_parent_notice_route "$2"
    echo "Third-Party Notices route verified"
    exit 0
fi

for command in jq plutil shasum cmp awk; do
    command -v "$command" >/dev/null || fail "$command is required"
done

scratch="$(mktemp -d "${TMPDIR:-/tmp}/tada-content-inventory.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

source_version="$(plutil -extract CFBundleShortVersionString raw "$production_plist")"
source_build="$(plutil -extract CFBundleVersion raw "$production_plist")"
expected_version="${TADA_EXPECTED_VERSION:-$source_version}"
expected_build="${TADA_EXPECTED_BUILD:-$source_build}"
expected_bundle_id="${TADA_EXPECTED_BUNDLE_ID:-app.tadawords.app}"
expected_commit="${TADA_EXPECTED_COMMIT:-$(git -C "$repo_root" rev-parse HEAD)}"

assert_equal "$source_version" "$expected_version" "production plist version"
assert_equal "$source_build" "$expected_build" "production plist build"
assert_equal "$(plutil -extract CFBundleShortVersionString raw "$localqa_plist")" "$expected_version" "LocalQA plist version"
assert_equal "$(plutil -extract CFBundleVersion raw "$localqa_plist")" "$expected_build" "LocalQA plist build"
assert_equal "$(awk '/MARKETING_VERSION:/ { print $2; exit }' "$repo_root/project.yml")" "$expected_version" "project.yml version"
assert_equal "$(awk '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "$repo_root/project.yml")" "$expected_build" "project.yml build"

verify_audio_pack "$repo_root/$audio_relative"
verify_picture_pack "$repo_root/$picture_relative"
verify_preset_catalog "$repo_root/$preset_relative"
assert_sha256 "$repo_root/$compatibility_relative" "51f579dccf3d44c5b03176cbb6abc975e983b547f7be205867f1a65df8156676" "persistence compatibility table"
assert_sha256 "$repo_root/$zodiac_master_relative" "1abdc56e278d8ce8a476bde3beaa0d2c58f94057f09212bc6842d8f4df0f320f" "zodiac avatar master"
assert_equal "$(find "$repo_root/$zodiac_assets_relative" -type f -path '*/Zodiac*.imageset/*.png' | awk 'END { print NR + 0 }')" "12" "zodiac avatar export count"
assert_equal "$(stable_path_digest "$repo_root/$zodiac_assets_relative" './Zodiac*.imageset/*.png')" "$expected_zodiac_export_digest" "zodiac avatar export digest"
grep -Fq 'No third-party artwork was supplied as a reference' "$repo_root/$zodiac_readme_relative" \
    || fail "zodiac no-reference provenance statement is missing"
grep -Fq 'ORIGINAL character designs only' "$repo_root/$zodiac_readme_relative" \
    || fail "zodiac original-design prompt is missing"

rights_inventory="$repo_root/$rights_inventory_relative"
assert_file "$rights_inventory" "content-rights inventory"
grep -Fq 'No unresolved content-rights evidence blocker remains' "$rights_inventory" \
    || fail "content-rights conclusion is not finalized"
grep -Fq 'issues/33#issuecomment-5066488733' "$rights_inventory" \
    || fail "owner attestation pointer is missing"
grep -Fq '85a98c0275800457e53d8607312650a6621afd3ce2e2f165c0c6fa2ab47ee73f' "$rights_inventory" \
    || fail "private Pawgoo evidence index checksum is missing"
grep -Fq '71e3533be3361733cf5d13ae9fe5240a0e87e2d1c9aa8f854876a9e51175f24b' "$rights_inventory" \
    || fail "Cartesia invoice checksum pointer is missing"

guardian_notice="$repo_root/$guardian_notice_relative"
guardian_today="$repo_root/Sources/TadaWordsGuardianFeatures/GuardianTodayView.swift"
guardian_root="$repo_root/Sources/TadaWordsGuardianFeatures/GuardianRootView.swift"
guardian_model="$repo_root/Sources/TadaWordsGuardianFeatures/GuardianDashboardViewModel.swift"
assert_file "$guardian_notice" "Parent Third-Party Notices view"
grep -Fq 'static let title = "Third-Party Notices"' "$guardian_notice" \
    || fail "Third-Party Notices title is missing"
grep -Fq 'Twemoji graphics © X Corp. and other contributors.' "$guardian_notice" \
    || fail "Twemoji in-app copyright attribution is missing"
grep -Fq '74 unmodified graphics from jdecked/twemoji 17.0.3.' "$guardian_notice" \
    || fail "Twemoji in-app source, version, or unmodified quantity is missing"
grep -Fq 'Creative Commons Attribution 4.0 International license.' "$guardian_notice" \
    || fail "Twemoji in-app license description is missing"
grep -Fq 'remain available offline.' "$guardian_notice" \
    || fail "offline Third-Party Notices description is missing"
grep -Fq 'https://github.com/jdecked/twemoji' "$guardian_notice" \
    || fail "Twemoji in-app source URL is missing"
grep -Fq 'https://creativecommons.org/licenses/by/4.0/' "$guardian_notice" \
    || fail "Twemoji in-app license URL is missing"
grep -Fq 'accessibilityIdentifier("guardian.third-party-notices")' "$guardian_notice" \
    || fail "Third-Party Notices screen accessibility identifier is missing"
grep -Fq 'accessibilityIdentifier: "guardian.app.third-party-notices"' "$guardian_today" \
    || fail "App & Family notice entrance is missing"
grep -Fq 'case .thirdPartyNotices:' "$guardian_root" \
    || fail "Third-Party Notices destination is missing from GuardianRootView"
grep -Fq 'GuardianThirdPartyNoticesView(' "$guardian_root" \
    || fail "Third-Party Notices destination does not render its view"
verify_parent_notice_route "$guardian_model"

assert_sha256 "$repo_root/Apps/TadaWordsApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" "ce1782b295901de1a7cc82f6f61cfc5ffbebf9bc0745256a573058bd1281e637" "app icon"
assert_sha256 "$repo_root/Apps/TadaWordsApp/Assets.xcassets/TadaWordsMark.imageset/TadaWordsAppIcon.svg" "e47bfb19efa22e38db1b2a796bb47bb87993fc35b5ae4e6ba6624a9ec5e7b816" "Tada Words mark"
assert_sha256 "$repo_root/Apps/TadaWordsApp/Assets.xcassets/PawgooMark.imageset/pawgoo-mark.svg" "2653ed92cac054f5df24d1726a90cd8e147b7e784cd98653c26f99d08c05f6c9" "Pawgoo mark"
assert_sha256 "$repo_root/Tests/Fixtures/ChildSpeech/speechocean762-000010168-bye.wav" "807df45f3aec0718c30929595a9db1e99eab87134e6cdefe15551aa8c0a79db8" "child-speech fixture"

assert_equal "$(find "$repo_root/QAArtifacts" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) | awk 'END { print NR + 0 }')" "19" "tracked QA image count"
assert_equal "$(find "$repo_root/Sources" -path '*/Resources/*' -type f -name '*.json' | awk 'END { print NR + 0 }')" "4" "source resource JSON count"

if find "$repo_root/Apps" "$repo_root/Sources" -type f \( -iname '*.ttf' -o -iname '*.otf' \) | grep -q .; then
    fail "custom font file found under Apps or Sources"
fi

grep -Fq '.copy("Resources/Audio")' "$repo_root/Package.swift" || fail "Audio resource copy declaration missing"
grep -Fq '.copy("Resources/PictureHints")' "$repo_root/Package.swift" || fail "PictureHints resource copy declaration missing"
grep -Fq '74 small Twemoji PNG assets bundled' "$repo_root/THIRD_PARTY_NOTICES.md" || fail "bundled Twemoji notice missing"
grep -Fq 'does not fetch' "$repo_root/THIRD_PARTY_NOTICES.md" || fail "offline Twemoji notice missing"
grep -Fq 'jdecked/twemoji' "$repo_root/THIRD_PARTY_NOTICES.md" || fail "Twemoji source notice missing"
grep -Fq 'Creative Commons Attribution 4.0' "$repo_root/THIRD_PARTY_NOTICES.md" || fail "Twemoji license notice missing"

picture_service="$repo_root/Sources/TadaWordsApplePlatform/AppleWordPictureHintService.swift"
grep -Fq 'Bundle.module' "$picture_service" || fail "picture service is not bound to bundled resources"
if grep -Eiq 'https?://|URLSession|jsdelivr|cdn\.' "$picture_service"; then
    fail "picture service contains a runtime network/CDN path"
fi

assert_equal \
    "$(plutil -extract TadaWordsTeacherAudioEndpoint raw "$production_plist")" \
    "$expected_teacher_audio_endpoint" \
    "production teacher-audio endpoint"

echo "source inventory verified: $expected_version ($expected_build), 4,000 Bella MP3, 8 Aurora M4A, 74 offline Twemoji PNGs, 12 zodiac avatar exports, four package JSON files plus one app schema JSON, no custom fonts"
echo "content-rights evidence pointers and in-app Twemoji attribution verified; #32 and #33 are reconciled for this exact content set"

if [[ "$#" -eq 0 ]]; then
    echo "archive inspection skipped: pass a .xcarchive or .app path to verify the built product"
    exit 0
fi
[[ "$#" -eq 1 ]] || fail "usage: $0 [TadaWords.xcarchive|TadaWords.app]"

input_path="$1"
if [[ "$input_path" == *.xcarchive ]]; then
    app_path="$(find "$input_path/Products/Applications" -maxdepth 1 -type d -name '*.app' -print -quit)"
else
    app_path="$input_path"
fi
[[ -n "${app_path:-}" && -d "$app_path" ]] || fail "no .app found under $input_path"

app_info="$app_path/Info.plist"
assert_file "$app_info" "archive Info.plist"
assert_equal "$(plutil -extract CFBundleShortVersionString raw "$app_info")" "$expected_version" "archive version"
assert_equal "$(plutil -extract CFBundleVersion raw "$app_info")" "$expected_build" "archive build"
assert_equal "$(plutil -extract CFBundleIdentifier raw "$app_info")" "$expected_bundle_id" "archive bundle ID"
assert_equal "$(plutil -extract TadaWordsGitCommit raw "$app_info")" "$expected_commit" "archive embedded commit"
assert_equal \
    "$(plutil -extract TadaWordsTeacherAudioEndpoint raw "$app_info")" \
    "$expected_teacher_audio_endpoint" \
    "archive teacher-audio endpoint"

archive_audio_root="$(find "$app_path" -type d -path '*/Audio' -print -quit)"
archive_picture_root="$(find "$app_path" -type d -path '*/PictureHints/Twemoji-17.0.3' -print -quit)"
archive_preset="$(find "$app_path" -type f -name 'PresetWords.json' -print -quit)"
[[ -n "$archive_audio_root" ]] || fail "Audio resource root missing from archive"
[[ -n "$archive_picture_root" ]] || fail "Twemoji resource root missing from archive"
[[ -n "$archive_preset" ]] || fail "PresetWords.json missing from archive"

verify_audio_pack "$archive_audio_root"
verify_picture_pack "$archive_picture_root"
verify_preset_catalog "$archive_preset"
archive_assets="$(find "$app_path" -type f -name 'Assets.car' -print -quit)"
[[ -n "$archive_assets" ]] || fail "compiled asset catalog missing from archive"
command -v assetutil >/dev/null || fail "assetutil is required for archive inspection"
assetutil --info "$archive_assets" >"$scratch/assets.json"
for zodiac_name in ZodiacRat ZodiacOx ZodiacTiger ZodiacRabbit ZodiacDragon ZodiacSnake ZodiacHorse ZodiacGoat ZodiacMonkey ZodiacRooster ZodiacDog ZodiacPig; do
    jq -e --arg name "$zodiac_name" 'any(.[]; .Name? == $name)' "$scratch/assets.json" >/dev/null \
        || fail "$zodiac_name is missing from compiled Assets.car"
done
archive_compatibility="$app_path/PersistenceSchemaCompatibility.json"
assert_file "$archive_compatibility" "archive persistence compatibility table"
assert_sha256 "$archive_compatibility" "51f579dccf3d44c5b03176cbb6abc975e983b547f7be205867f1a65df8156676" "archive persistence compatibility table"
assert_equal "$(count_files "$app_path" '*.json')" "5" "archive JSON count"

excluded_pattern='(^|/)(QAArtifacts|DesignAssets|Tests|Fixtures)(/|$)|speechocean|LICENSE_SOURCE|SHA256SUMS|\.(wav|ttf|otf)$'
if find "$app_path" -type f | grep -E "$excluded_pattern"; then
    fail "test/design-only content found in archive"
fi

echo "archive inventory verified: $app_path"
echo "compiled zodiac avatars, in-app Twemoji attribution, and reconciled rights evidence verified at exact source HEAD"
