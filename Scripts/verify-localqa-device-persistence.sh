#!/bin/bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: verify-localqa-device-persistence.sh DEVICE_ID APP_PATH

Read-only preflight for an in-place Tada Words LocalQA install. It copies the
existing snapshot directory to a private temporary folder and refuses an app
whose bundled readers are older than any saved schema on the device.
EOF
}

if [[ $# -ne 2 ]]; then
    usage >&2
    exit 64
fi

DEVICE_ID=$1
APP_PATH=$2
INFO_PLIST="$APP_PATH/Info.plist"
POLICY="$APP_PATH/PersistenceSchemaCompatibility.json"
BUNDLE_ID="com.tadawords.app.localqa"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

[[ -d "$APP_PATH" ]] || fail "app bundle does not exist: $APP_PATH"
[[ -f "$INFO_PLIST" ]] || fail "target app is missing Info.plist"
[[ -f "$POLICY" ]] || fail "target app is missing PersistenceSchemaCompatibility.json"

TARGET_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")
[[ "$TARGET_BUNDLE_ID" == "$BUNDLE_ID" ]] \
    || fail "target bundle must be $BUNDLE_ID, found $TARGET_BUNDLE_ID"

umask 077
TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/tadawords-persistence-preflight.XXXXXX")
trap 'rm -rf "$TEMP_ROOT"' EXIT
chmod 700 "$TEMP_ROOT"

if ! xcrun devicectl device copy from \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    --source 'Library/Application Support/TadaWords' \
    --destination "$TEMP_ROOT/TadaWords" \
    --json-output "$TEMP_ROOT/copy.json" \
    --log-output "$TEMP_ROOT/copy.log" \
    --timeout 120 \
    >/dev/null 2>&1
then
    fail "could not read existing LocalQA data; wake/unlock the device and retry"
fi

python3 - "$POLICY" "$TEMP_ROOT/TadaWords" <<'PY'
import json
import pathlib
import sys

policy_path = pathlib.Path(sys.argv[1])
snapshot_root = pathlib.Path(sys.argv[2])

with policy_path.open("r", encoding="utf-8") as handle:
    policy = json.load(handle)

if policy.get("formatVersion") != 1 or not isinstance(policy.get("stores"), dict):
    raise SystemExit("FAIL: target app has an invalid persistence compatibility policy")

failures = []
checked = 0
for filename, supported in sorted(policy["stores"].items()):
    snapshot = snapshot_root / filename
    if not snapshot.exists():
        continue
    checked += 1
    try:
        with snapshot.open("r", encoding="utf-8") as handle:
            value = json.load(handle)
        found = value["schemaVersion"]
    except (OSError, UnicodeError, json.JSONDecodeError, KeyError, TypeError):
        failures.append(f"{filename}: unreadable schema envelope")
        continue
    if not isinstance(found, int) or found < 1:
        failures.append(f"{filename}: invalid schema version")
    elif found > supported:
        failures.append(f"{filename}: saved={found}, target-max={supported}")

if failures:
    print("FAIL: target app cannot safely read this device's saved data", file=sys.stderr)
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    print("No app was installed and no device file was changed.", file=sys.stderr)
    raise SystemExit(1)

print(f"PASS: {checked} saved snapshot schema(s) are readable by the target app")
PY
