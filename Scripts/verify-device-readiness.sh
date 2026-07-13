#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PROJECT="$ROOT/TadaWords.xcodeproj"
SCHEME="TadaWords"
INFO="$ROOT/Apps/TadaWordsApp/Info.plist"
PRIVACY="$ROOT/Apps/TadaWordsApp/PrivacyInfo.xcprivacy"
ICON_SET="$ROOT/Apps/TadaWordsApp/Assets.xcassets/AppIcon.appiconset"
DERIVED_DATA="$ROOT/.build/device-readiness-derived-data"
STATUS=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

pass() {
    printf 'PASS: %s\n' "$1"
}

blocked() {
    printf 'BLOCKED: %s\n' "$1"
    STATUS=1
}

command -v xcodegen >/dev/null 2>&1 || fail "XcodeGen is not installed"
command -v xcodebuild >/dev/null 2>&1 || fail "Xcode command-line tools are unavailable"

plutil -lint "$INFO" >/dev/null || fail "Info.plist is invalid"
plutil -lint "$PRIVACY" >/dev/null || fail "PrivacyInfo.xcprivacy is invalid"
pass "property lists are valid"

validate_landscape_orientations() {
    key=$1
    orientations=$(plutil -extract "$key" json -o - "$INFO" 2>/dev/null) \
        || fail "$key is missing"

    printf '%s' "$orientations" | grep -q 'UIInterfaceOrientationLandscapeLeft' \
        || fail "$key does not support Landscape Left"
    printf '%s' "$orientations" | grep -q 'UIInterfaceOrientationLandscapeRight' \
        || fail "$key does not support Landscape Right"
    if printf '%s' "$orientations" | grep -q 'Portrait'; then
        fail "$key must not contain a portrait orientation"
    fi

    orientation_count=$(
        printf '%s' "$orientations" \
            | grep -o 'UIInterfaceOrientation' \
            | wc -l \
            | tr -d ' '
    )
    test "$orientation_count" = 2 \
        || fail "$key must contain exactly the two landscape orientations"
}

validate_landscape_orientations UISupportedInterfaceOrientations
validate_landscape_orientations 'UISupportedInterfaceOrientations~ipad'
test "$(plutil -extract UIRequiresFullScreen raw -o - "$INFO" 2>/dev/null)" = true \
    || fail "UIRequiresFullScreen must be enabled"
pass "iPhone and iPad are locked to full-screen Landscape Left and Right"

for key in NSMicrophoneUsageDescription NSSpeechRecognitionUsageDescription; do
    test -n "$(plutil -extract "$key" raw -o - "$INFO" 2>/dev/null)" \
        || fail "$key is missing"
done
pass "microphone and speech usage descriptions are present"

for declaration in \
    NSPrivacyAccessedAPICategoryFileTimestamp \
    NSPrivacyAccessedAPICategorySystemBootTime \
    C617.1 \
    35F9.1; do
    grep -q "$declaration" "$PRIVACY" || fail "privacy declaration $declaration is missing"
done
pass "required-reason API declarations are present"

ICON=$(find "$ICON_SET" -maxdepth 1 -type f -name '*.png' -print -quit)
if test -z "$ICON"; then
    blocked "AppIcon.appiconset has no PNG; add a final 1024 x 1024 app icon"
else
    ICON_WIDTH=$(sips -g pixelWidth "$ICON" 2>/dev/null | awk '/pixelWidth:/ { print $2 }')
    ICON_HEIGHT=$(sips -g pixelHeight "$ICON" 2>/dev/null | awk '/pixelHeight:/ { print $2 }')
    ICON_ALPHA=$(sips -g hasAlpha "$ICON" 2>/dev/null | awk '/hasAlpha:/ { print $2 }')
    test "$ICON_WIDTH" = 1024 && test "$ICON_HEIGHT" = 1024 \
        || fail "the app icon must be 1024 x 1024"
    test "$ICON_ALPHA" = no || fail "the app icon must not contain transparency"
    pass "1024 x 1024 opaque app icon is present"
fi

(
    cd "$ROOT"
    xcodegen generate --spec project.yml >/dev/null
)
pass "Xcode project regenerated from project.yml"

rm -rf "$DERIVED_DATA"
for destination in "iPhone 17 Pro Max" "iPad Pro 13-inch (M5)"; do
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination "platform=iOS Simulator,name=$destination,OS=latest" \
        -derivedDataPath "$DERIVED_DATA" \
        CODE_SIGNING_ALLOWED=NO \
        build >/dev/null
done
pass "Release builds succeeded for iPhone 17 Pro Max and iPad Pro 13-inch"

BUILT_APP="$DERIVED_DATA/Build/Products/Release-iphonesimulator/Tada Words.app"
test -f "$BUILT_APP/PrivacyInfo.xcprivacy" \
    || fail "the built app does not contain PrivacyInfo.xcprivacy"
find "$BUILT_APP" -maxdepth 1 -type f -name 'AppIcon*.png' -print -quit | grep -q . \
    || fail "the asset compiler did not emit an app icon"
pass "the built app contains its privacy manifest and compiled app icon"

if xcrun devicectl list devices 2>/dev/null | grep -q 'connected'; then
    pass "a physical Apple device is connected"
else
    blocked "no connected physical iPhone or iPad"
fi

if security find-identity -v -p codesigning 2>/dev/null | grep -Eq '[1-9][0-9]* valid identities found'; then
    pass "a code-signing identity is available"
else
    blocked "no valid Apple code-signing identity; sign in and choose a Team in Xcode"
fi

exit "$STATUS"
