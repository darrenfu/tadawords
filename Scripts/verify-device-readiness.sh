#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PROJECT="$ROOT/TadaWords.xcodeproj"
SCHEME="TadaWords"
LOCAL_SCHEME="TadaWordsLocalQA"
INFO="$ROOT/Apps/TadaWordsApp/Info.plist"
LOCAL_INFO="$ROOT/Apps/TadaWordsApp/InfoLocalQA.plist"
ENTITLEMENTS="$ROOT/Apps/TadaWordsApp/TadaWords.entitlements"
LOCAL_ENTITLEMENTS="$ROOT/Apps/TadaWordsApp/TadaWordsLocalQA.entitlements"
LOCAL_SCHEME_FILE="$PROJECT/xcshareddata/xcschemes/TadaWordsLocalQA.xcscheme"
PRIVACY="$ROOT/Apps/TadaWordsApp/PrivacyInfo.xcprivacy"
ICON_SET="$ROOT/Apps/TadaWordsApp/Assets.xcassets/AppIcon.appiconset"
DERIVED_DATA="$ROOT/.build/device-readiness-derived-data"
LOCAL_DERIVED_DATA="$ROOT/.build/local-qa-readiness-derived-data"
PAWGOO_TEAM="7R78Q4HP86"
NORMAL_BUNDLE_ID="app.tadawords.app"
NORMAL_UI_TEST_BUNDLE_ID="app.tadawords.app.uitests"
LOCAL_BUNDLE_ID="com.tadawords.app.localqa"
LOCAL_UI_TEST_BUNDLE_ID="com.tadawords.app.uitests"
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
plutil -lint "$LOCAL_INFO" >/dev/null || fail "InfoLocalQA.plist is invalid"
plutil -lint "$ENTITLEMENTS" >/dev/null \
    || fail "TadaWords.entitlements is invalid"
plutil -lint "$LOCAL_ENTITLEMENTS" >/dev/null \
    || fail "TadaWordsLocalQA.entitlements is invalid"
plutil -lint "$PRIVACY" >/dev/null || fail "PrivacyInfo.xcprivacy is invalid"
pass "property lists are valid"

validate_orientation_envelope() {
    plist=$1
    key=$2
    allows_upside_down=$3
    orientations=$(plutil -extract "$key" json -o - "$plist" 2>/dev/null) \
        || fail "$key is missing from $(basename "$plist")"

    printf '%s' "$orientations" | grep -q '"UIInterfaceOrientationPortrait"' \
        || fail "$key in $(basename "$plist") does not support Portrait"
    printf '%s' "$orientations" | grep -q 'UIInterfaceOrientationLandscapeLeft' \
        || fail "$key in $(basename "$plist") does not support Landscape Left"
    printf '%s' "$orientations" | grep -q 'UIInterfaceOrientationLandscapeRight' \
        || fail "$key in $(basename "$plist") does not support Landscape Right"

    if test "$allows_upside_down" = true; then
        printf '%s' "$orientations" | grep -q 'UIInterfaceOrientationPortraitUpsideDown' \
            || fail "$key in $(basename "$plist") must support iPad Portrait Upside Down"
        expected_count=4
    else
        if printf '%s' "$orientations" | grep -q 'UIInterfaceOrientationPortraitUpsideDown'; then
            fail "$key in $(basename "$plist") must not support iPhone Portrait Upside Down"
        fi
        expected_count=3
    fi

    orientation_count=$(
        printf '%s' "$orientations" \
            | grep -o 'UIInterfaceOrientation' \
            | wc -l \
            | tr -d ' '
    )
    test "$orientation_count" = "$expected_count" \
        || fail "$key in $(basename "$plist") has an unexpected orientation declaration"
}

for plist in "$INFO" "$LOCAL_INFO"; do
    validate_orientation_envelope "$plist" UISupportedInterfaceOrientations false
    validate_orientation_envelope "$plist" 'UISupportedInterfaceOrientations~ipad' true
    test "$(plutil -extract UIRequiresFullScreen raw -o - "$plist" 2>/dev/null)" = true \
        || fail "UIRequiresFullScreen must be enabled in $(basename "$plist")"
done
pass "global orientation envelope supports parent rotation on iPhone and iPad"

for plist in "$INFO" "$LOCAL_INFO"; do
    for key in NSMicrophoneUsageDescription NSSpeechRecognitionUsageDescription; do
        test -n "$(plutil -extract "$key" raw -o - "$plist" 2>/dev/null)" \
            || fail "$key is missing from $(basename "$plist")"
    done
done
pass "microphone and speech usage descriptions are present"

BACKGROUND_MODES=$(plutil -extract UIBackgroundModes json -o - "$INFO" 2>/dev/null) \
    || fail "UIBackgroundModes is missing from Info.plist"
printf '%s' "$BACKGROUND_MODES" | grep -q '"remote-notification"' \
    || fail "Info.plist must enable the remote-notification background mode"
test "$(plutil -extract aps-environment raw -o - "$ENTITLEMENTS" 2>/dev/null)" \
    = '$(APS_ENVIRONMENT)' \
    || fail "production APNs entitlement must bind to APS_ENVIRONMENT"
test "$(plutil -extract 'com\.apple\.developer\.icloud-container-environment' raw -o - "$ENTITLEMENTS" 2>/dev/null)" \
    = '$(ICLOUD_CONTAINER_ENVIRONMENT)' \
    || fail "production CloudKit entitlement must bind to ICLOUD_CONTAINER_ENVIRONMENT"
test "$(plutil -extract 'com\.apple\.developer\.devicecheck\.appattest-environment' raw -o - "$ENTITLEMENTS" 2>/dev/null)" \
    = '$(APP_ATTEST_ENVIRONMENT)' \
    || fail "App Attest entitlement must bind to APP_ATTEST_ENVIRONMENT"
test "$(plutil -extract 'keychain-access-groups.0' raw -o - "$ENTITLEMENTS" 2>/dev/null)" \
    = '$(AppIdentifierPrefix)app.tadawords.app' \
    || fail "normal app keychain access must stay bound to the PawGoo app identifier"
if plutil -extract com.apple.developer.ubiquity-kvstore-identifier raw -o - \
    "$ENTITLEMENTS" >/dev/null 2>&1; then
    fail "the unused KVS entitlement must not be present in the normal app"
fi
if plutil -extract UIBackgroundModes json -o - "$LOCAL_INFO" >/dev/null 2>&1; then
    fail "LocalQA must not advertise remote notification background delivery"
fi
if plutil -extract aps-environment raw -o - "$LOCAL_ENTITLEMENTS" >/dev/null 2>&1; then
    fail "LocalQA must not contain an APNs entitlement"
fi
pass "production background sync capability is declared and LocalQA remains isolated"

for plist in "$INFO" "$LOCAL_INFO"; do
    test "$(plutil -extract TadaWordsGitCommit raw -o - "$plist" 2>/dev/null)" \
        = '$(TADA_GIT_COMMIT)' \
        || fail "TadaWordsGitCommit must bind to TADA_GIT_COMMIT in $(basename "$plist")"
done
pass "source property lists bind the installed app to its Git commit"

test "$(plutil -extract CFBundleDisplayName raw -o - "$LOCAL_INFO")" = "Tada Words QA" \
    || fail "LocalQA display name must be Tada Words QA"
test "$(plutil -extract CKSharingSupported raw -o - "$LOCAL_INFO")" = false \
    || fail "LocalQA must declare CKSharingSupported=false"
if grep -q 'com.apple.developer.icloud' "$LOCAL_ENTITLEMENTS"; then
    fail "LocalQA entitlements must not contain iCloud capabilities"
fi
pass "LocalQA is visibly named and statically device-only"

for declaration in \
    NSPrivacyAccessedAPICategoryFileTimestamp \
    NSPrivacyAccessedAPICategorySystemBootTime \
    NSPrivacyAccessedAPICategoryUserDefaults \
    C617.1 \
    35F9.1 \
    CA92.1; do
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

"$ROOT/Scripts/generate-xcode-project.sh" >/dev/null
pass "Xcode project regenerated from project.yml"

if grep -q 'DEVELOPMENT_TEAM = 6S245NCUPQ' "$PROJECT/project.pbxproj"; then
    fail "the generated project must not retain the Personal Team"
fi
test -f "$LOCAL_SCHEME_FILE" || fail "TadaWordsLocalQA scheme is missing"
LOCAL_ACTION_COUNT=$(grep -c 'buildConfiguration = "LocalQA"' "$LOCAL_SCHEME_FILE" || true)
test "$LOCAL_ACTION_COUNT" = 5 \
    || fail "LocalQA run, test, profile, analyze, and archive actions must all use LocalQA"
pass "generated schemes exclude the Personal Team and keep every LocalQA action isolated"

for configuration in Debug Release; do
    NORMAL_BUILD_SETTINGS=$(
        xcodebuild \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -configuration "$configuration" \
            -sdk iphonesimulator \
            -showBuildSettings 2>/dev/null
    )
    printf '%s\n' "$NORMAL_BUILD_SETTINGS" \
        | grep -q "PRODUCT_BUNDLE_IDENTIFIER = $NORMAL_BUNDLE_ID" \
        || fail "normal $configuration bundle identifier is incorrect"
    printf '%s\n' "$NORMAL_BUILD_SETTINGS" \
        | grep -q "DEVELOPMENT_TEAM = $PAWGOO_TEAM" \
        || fail "normal $configuration must be pinned to PawGoo"
    if test "$configuration" = Debug; then
        EXPECTED_ICLOUD_ENVIRONMENT=Development
        EXPECTED_APP_ATTEST_ENVIRONMENT=development
        printf '%s\n' "$NORMAL_BUILD_SETTINGS" \
            | grep -q 'INFOPLIST_KEY_TadaWordsTeacherAudioEndpoint = https://audio-dev.pawgoo.app' \
            || fail "normal Debug teacher-audio endpoint is incorrect"
    else
        EXPECTED_ICLOUD_ENVIRONMENT=Production
        EXPECTED_APP_ATTEST_ENVIRONMENT=production
        if printf '%s\n' "$NORMAL_BUILD_SETTINGS" \
            | grep -Eq '^[[:space:]]*INFOPLIST_KEY_TadaWordsTeacherAudioEndpoint ='; then
            fail "normal Release must not configure a teacher-audio endpoint before production verification"
        fi
    fi
    printf '%s\n' "$NORMAL_BUILD_SETTINGS" \
        | grep -q "ICLOUD_CONTAINER_ENVIRONMENT = $EXPECTED_ICLOUD_ENVIRONMENT" \
        || fail "normal $configuration CloudKit environment is incorrect"
    printf '%s\n' "$NORMAL_BUILD_SETTINGS" \
        | grep -q "APP_ATTEST_ENVIRONMENT = $EXPECTED_APP_ATTEST_ENVIRONMENT" \
        || fail "normal $configuration App Attest environment is incorrect"

    UI_TEST_BUILD_SETTINGS=$(
        xcodebuild \
            -project "$PROJECT" \
            -target TadaWordsUITests \
            -configuration "$configuration" \
            -sdk iphonesimulator \
            -showBuildSettings 2>/dev/null
    )
    printf '%s\n' "$UI_TEST_BUILD_SETTINGS" \
        | grep -q "PRODUCT_BUNDLE_IDENTIFIER = $NORMAL_UI_TEST_BUNDLE_ID" \
        || fail "normal UI-test $configuration bundle identifier is incorrect"
    printf '%s\n' "$UI_TEST_BUILD_SETTINGS" \
        | grep -q "DEVELOPMENT_TEAM = $PAWGOO_TEAM" \
        || fail "normal UI-test $configuration must be pinned to PawGoo"
done
pass "normal app and UI-test Debug/Release identities are pinned to PawGoo"

LOCAL_BUILD_SETTINGS=$(
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$LOCAL_SCHEME" \
        -configuration LocalQA \
        -sdk iphonesimulator \
        -showBuildSettings 2>/dev/null
)
printf '%s\n' "$LOCAL_BUILD_SETTINGS" \
    | grep -q "PRODUCT_BUNDLE_IDENTIFIER = $LOCAL_BUNDLE_ID" \
    || fail "LocalQA bundle identifier is incorrect"
if printf '%s\n' "$LOCAL_BUILD_SETTINGS" \
    | grep -Eq '^[[:space:]]*DEVELOPMENT_TEAM = [^[:space:]]+'; then
    fail "LocalQA must remain team-flexible in committed settings"
fi
if printf '%s\n' "$LOCAL_BUILD_SETTINGS" \
    | grep -Eq '^[[:space:]]*APS_ENVIRONMENT = [^[:space:]]+'; then
    fail "LocalQA must not inherit an APNs environment build setting"
fi
if printf '%s\n' "$LOCAL_BUILD_SETTINGS" \
    | grep -Eq '^[[:space:]]*ICLOUD_CONTAINER_ENVIRONMENT = [^[:space:]]+'; then
    fail "LocalQA must not inherit a CloudKit environment build setting"
fi
if printf '%s\n' "$LOCAL_BUILD_SETTINGS" \
    | grep -Eq '^[[:space:]]*APP_ATTEST_ENVIRONMENT = [^[:space:]]+'; then
    fail "LocalQA must not inherit an App Attest environment build setting"
fi
if printf '%s\n' "$LOCAL_BUILD_SETTINGS" \
    | grep -Eq '^[[:space:]]*INFOPLIST_KEY_TadaWordsTeacherAudioEndpoint ='; then
    fail "LocalQA must remain teacher-audio endpoint-free"
fi
printf '%s\n' "$LOCAL_BUILD_SETTINGS" \
    | grep -q 'PRODUCT_NAME = Tada Words QA' \
    || fail "LocalQA product name is incorrect"
printf '%s\n' "$LOCAL_BUILD_SETTINGS" \
    | grep -q 'INFOPLIST_FILE = Apps/TadaWordsApp/InfoLocalQA.plist' \
    || fail "LocalQA is not using InfoLocalQA.plist"
printf '%s\n' "$LOCAL_BUILD_SETTINGS" \
    | grep -q 'CODE_SIGN_ENTITLEMENTS = Apps/TadaWordsApp/TadaWordsLocalQA.entitlements' \
    || fail "LocalQA is not using its empty entitlement file"
printf '%s\n' "$LOCAL_BUILD_SETTINGS" | grep -q 'LOCAL_DEVICE_QA' \
    || fail "LocalQA is missing the LOCAL_DEVICE_QA compilation condition"
pass "LocalQA build settings select the isolated app identity and code path"

LOCAL_UI_TEST_BUILD_SETTINGS=$(
    xcodebuild \
        -project "$PROJECT" \
        -target TadaWordsUITests \
        -configuration LocalQA \
        -sdk iphonesimulator \
        -showBuildSettings 2>/dev/null
)
printf '%s\n' "$LOCAL_UI_TEST_BUILD_SETTINGS" \
    | grep -q "PRODUCT_BUNDLE_IDENTIFIER = $LOCAL_UI_TEST_BUNDLE_ID" \
    || fail "LocalQA UI-test bundle identifier must retain its isolated identity"
if printf '%s\n' "$LOCAL_UI_TEST_BUILD_SETTINGS" \
    | grep -Eq '^[[:space:]]*DEVELOPMENT_TEAM = [^[:space:]]+'; then
    fail "LocalQA UI tests must remain team-flexible in committed settings"
fi
pass "LocalQA UI-test identity remains independent and team-flexible"

rm -rf "$DERIVED_DATA"
for destination in "iPhone 17 Pro Max" "iPad Pro 13-inch (M5)"; do
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination "platform=iOS Simulator,name=$destination,OS=latest" \
        -derivedDataPath "$DERIVED_DATA" \
        ONLY_ACTIVE_ARCH=YES \
        CODE_SIGNING_ALLOWED=NO \
        build >/dev/null
done
pass "Release builds succeeded for iPhone 17 Pro Max and iPad Pro 13-inch"

BUILT_APP="$DERIVED_DATA/Build/Products/Release-iphonesimulator/Tada Words.app"
test "$(plutil -extract CFBundleIdentifier raw -o - "$BUILT_APP/Info.plist")" \
    = "$NORMAL_BUNDLE_ID" \
    || fail "the normal built app has the wrong PawGoo bundle identifier"
validate_orientation_envelope "$BUILT_APP/Info.plist" UISupportedInterfaceOrientations false
validate_orientation_envelope "$BUILT_APP/Info.plist" 'UISupportedInterfaceOrientations~ipad' true
test -f "$BUILT_APP/PrivacyInfo.xcprivacy" \
    || fail "the built app does not contain PrivacyInfo.xcprivacy"
find "$BUILT_APP" -maxdepth 1 -type f -name 'AppIcon*.png' -print -quit | grep -q . \
    || fail "the asset compiler did not emit an app icon"
pass "the built app contains its privacy manifest and compiled app icon"

rm -rf "$LOCAL_DERIVED_DATA"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$LOCAL_SCHEME" \
    -configuration LocalQA \
    -destination "platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest" \
    -derivedDataPath "$LOCAL_DERIVED_DATA" \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO \
    build >/dev/null

LOCAL_BUILT_APP="$LOCAL_DERIVED_DATA/Build/Products/LocalQA-iphonesimulator/Tada Words QA.app"
LOCAL_BUILT_INFO="$LOCAL_BUILT_APP/Info.plist"
test -f "$LOCAL_BUILT_INFO" || fail "the LocalQA built app is missing"
validate_orientation_envelope "$LOCAL_BUILT_INFO" UISupportedInterfaceOrientations false
validate_orientation_envelope "$LOCAL_BUILT_INFO" 'UISupportedInterfaceOrientations~ipad' true
test "$(plutil -extract CFBundleIdentifier raw -o - "$LOCAL_BUILT_INFO")" \
    = "$LOCAL_BUNDLE_ID" \
    || fail "the LocalQA built app has the wrong bundle identifier"
test "$(plutil -extract CFBundleDisplayName raw -o - "$LOCAL_BUILT_INFO")" \
    = "Tada Words QA" \
    || fail "the LocalQA built app has the wrong display name"
test "$(plutil -extract CKSharingSupported raw -o - "$LOCAL_BUILT_INFO")" = false \
    || fail "the LocalQA built app unexpectedly advertises CloudKit sharing"
pass "unsigned LocalQA simulator build is isolated and device-only"

if xcrun devicectl list devices 2>/dev/null \
    | grep -Eq 'connected|available \(paired\)'; then
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
