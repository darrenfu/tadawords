#!/bin/bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: install-production-device.sh DEVICE_ID APP_PATH

Safely installs a production Tada Words app in place. The script first proves
that the target build can read the saved production data and never uninstalls
or resets the existing app.
EOF
}

if [[ $# -ne 2 ]]; then
    usage >&2
    exit 64
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_ID=$1
APP_PATH=$2

TADA_EXPECTED_BUNDLE_ID=app.tadawords.app \
    "$ROOT/Scripts/verify-localqa-device-persistence.sh" "$DEVICE_ID" "$APP_PATH"

xcrun devicectl device install app \
    --device "$DEVICE_ID" \
    --timeout 120 \
    "$APP_PATH"
