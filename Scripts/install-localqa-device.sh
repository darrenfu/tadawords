#!/bin/bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
    printf 'Usage: install-localqa-device.sh DEVICE_ID APP_PATH\n' >&2
    exit 64
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEVICE_ID=$1
APP_PATH=$2

"$ROOT/Scripts/verify-localqa-device-persistence.sh" "$DEVICE_ID" "$APP_PATH"

xcrun devicectl device install app \
    --device "$DEVICE_ID" \
    --timeout 120 \
    "$APP_PATH"
