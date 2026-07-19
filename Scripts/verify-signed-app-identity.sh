#!/bin/sh

set -eu

usage() {
    cat >&2 <<'EOF'
Usage: verify-signed-app-identity.sh APP_PATH VERSION BUILD COMMIT BUNDLE_ID [TEAM_ID]

Verifies that a signed physical-device .app carries the exact release-batch
identity expected for installation.
EOF
    exit 2
}

test "$#" -eq 5 || test "$#" -eq 6 || usage

APP=$1
EXPECTED_VERSION=$2
EXPECTED_BUILD=$3
EXPECTED_COMMIT=$4
EXPECTED_BUNDLE_ID=$5
EXPECTED_TEAM=${6:-}
INFO="$APP/Info.plist"

test -d "$APP" || {
    printf 'FAIL: app bundle not found: %s\n' "$APP" >&2
    exit 1
}
test -f "$INFO" || {
    printf 'FAIL: app Info.plist not found: %s\n' "$INFO" >&2
    exit 1
}

case "$EXPECTED_COMMIT" in
    *[!0-9a-fA-F]* | '')
        printf 'FAIL: expected commit must be hexadecimal\n' >&2
        exit 1
        ;;
esac
test "${#EXPECTED_COMMIT}" -eq 40 || {
    printf 'FAIL: expected commit must be the full 40-character HEAD SHA\n' >&2
    exit 1
}

actual_version=$(plutil -extract CFBundleShortVersionString raw -o - "$INFO")
actual_build=$(plutil -extract CFBundleVersion raw -o - "$INFO")
actual_commit=$(plutil -extract TadaWordsGitCommit raw -o - "$INFO")
actual_bundle_id=$(plutil -extract CFBundleIdentifier raw -o - "$INFO")

assert_equal() {
    label=$1
    expected=$2
    actual=$3
    test "$expected" = "$actual" || {
        printf 'FAIL: %s mismatch; expected=%s actual=%s\n' \
            "$label" "$expected" "$actual" >&2
        exit 1
    }
    printf 'PASS: %s=%s\n' "$label" "$actual"
}

assert_equal version "$EXPECTED_VERSION" "$actual_version"
assert_equal build "$EXPECTED_BUILD" "$actual_build"
assert_equal commit "$EXPECTED_COMMIT" "$actual_commit"
assert_equal bundle-id "$EXPECTED_BUNDLE_ID" "$actual_bundle_id"

codesign --verify --deep --strict "$APP"
printf 'PASS: code signature is structurally valid\n'

signature=$(codesign -dvv "$APP" 2>&1)
printf '%s\n' "$signature" | grep -q '^TeamIdentifier=' || {
    printf 'FAIL: signed app has no TeamIdentifier\n' >&2
    exit 1
}
team=$(printf '%s\n' "$signature" | awk -F= '/^TeamIdentifier=/ {print $2; exit}')
test -n "$team" && test "$team" != "not set" || {
    printf 'FAIL: signed app does not carry a development TeamIdentifier\n' >&2
    exit 1
}
if test -n "$EXPECTED_TEAM"; then
    assert_equal team-id "$EXPECTED_TEAM" "$team"
fi
printf 'PASS: TeamIdentifier=%s\n' "$team"
printf 'READY: signed app identity matches the release batch\n'
