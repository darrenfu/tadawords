#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
command -v xcodegen >/dev/null 2>&1 || {
    printf 'XcodeGen is not installed\n' >&2
    exit 1
}

# XcodeGen derives the visible name of a root-local Swift package from the
# project-root directory. Release worktrees intentionally have different names,
# which would otherwise create unrelated project and scheme diffs. Generate
# through a short-lived, stable logical path while writing into the real root.
STABLE_PARENT=$(mktemp -d "${TMPDIR:-/tmp}/tadawords-xcodegen.XXXXXX")
STABLE_ROOT="$STABLE_PARENT/Tada Words"
trap 'rm -rf "$STABLE_PARENT"' EXIT INT TERM
ln -s "$ROOT" "$STABLE_ROOT"

xcodegen generate \
    --spec "$STABLE_ROOT/project.yml" \
    --project "$STABLE_ROOT" \
    --project-root "$STABLE_ROOT" \
    "$@"
