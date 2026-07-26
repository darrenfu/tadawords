#!/bin/zsh

set -eu
umask 077

SCRIPT_DIR=${0:A:h}
REPO_SLUG=${TADA_AGENT_REPO:-darrenfu/tadawords}
INSTALL_ROOT=${TADA_AGENT_INSTALL_ROOT:-"/Users/macmini-dofu/Library/Application Support/TadaWordsIssueAgent"}
WORKTREE_ROOT=${TADA_AGENT_WORKTREE_ROOT:-"/Users/macmini-dofu/Documents/Tada Words Worktrees"}
LOG_DIR=${TADA_AGENT_LOG_DIR:-"/Users/macmini-dofu/Library/Logs/TadaWordsIssueAgent"}
MAX_ACTIVE_BATCHES=${TADA_AGENT_MAX_ACTIVE_BATCHES:-1}
CODEX_MODEL=${TADA_AGENT_MODEL:-gpt-5.6-terra}
CODEX_REASONING_EFFORT=${TADA_AGENT_REASONING_EFFORT:-medium}
STATE_DIR="$INSTALL_ROOT/state"
CONTROL_REPO="$INSTALL_ROOT/control-repo"
BIN_DIR="$INSTALL_ROOT/bin"
BACKUP_ROOT="$INSTALL_ROOT/backups"
LAUNCH_AGENT=${TADA_AGENT_LAUNCH_AGENT:-"/Users/macmini-dofu/Library/LaunchAgents/com.tadawords.issue-agent.plist"}
APP_CODEX="/Applications/ChatGPT.app/Contents/Resources/codex"
MODEL_CATALOG=${TADA_AGENT_MODEL_CATALOG:-"${CODEX_HOME:-$HOME/.codex}/models_cache.json"}
domain=${TADA_AGENT_LAUNCH_DOMAIN:-"gui/$(id -u)"}

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

verify_backup() {
    backup_dir=$1
    test -s "$backup_dir/manifest.sha256" || return 1
    (cd "$backup_dir" && shasum -a 256 -c manifest.sha256 >/dev/null)
}

restore_backup() {
    requested_backup=${1:A}
    canonical_root=${BACKUP_ROOT:A}
    if [[ "$requested_backup" != "$canonical_root"/* ]]; then
        fail "Refusing rollback outside the Issue Agent backup root: $requested_backup"
    fi
    verify_backup "$requested_backup" \
        || fail "Backup checksum verification failed: $requested_backup"

    recovery_dir="$INSTALL_ROOT/failed-install-$(date -u +%Y%m%dT%H%M%SZ)-$$"
    install -d -m 700 "$recovery_dir" "${LAUNCH_AGENT:h}"
    launchctl bootout "$domain" "$LAUNCH_AGENT" >/dev/null 2>&1 || true

    if test -d "$BIN_DIR"; then
        mv "$BIN_DIR" "$recovery_dir/bin"
    fi
    if test -f "$LAUNCH_AGENT"; then
        mv "$LAUNCH_AGENT" "$recovery_dir/com.tadawords.issue-agent.plist"
    fi

    if test -d "$requested_backup/bin"; then
        cp -pR "$requested_backup/bin" "$BIN_DIR"
    fi
    if test -f "$requested_backup/com.tadawords.issue-agent.plist"; then
        cp -p "$requested_backup/com.tadawords.issue-agent.plist" "$LAUNCH_AGENT"
        plutil -lint "$LAUNCH_AGENT" >/dev/null
        launchctl bootstrap "$domain" "$LAUNCH_AGENT"
        launchctl enable "$domain/com.tadawords.issue-agent"
        launchctl kickstart -k "$domain/com.tadawords.issue-agent"
    fi

    printf 'Restored Issue Agent backup: %s\n' "$requested_backup"
    printf 'Displaced runtime retained at: %s\n' "$recovery_dir"
}

if test "${1:-}" = --rollback; then
    test "$#" -eq 2 || fail "Usage: $0 --rollback BACKUP_DIRECTORY"
    for command in launchctl plutil shasum; do
        command -v "$command" >/dev/null 2>&1 \
            || fail "Missing required rollback command: $command"
    done
    restore_backup "$2"
    exit 0
elif test "$#" -ne 0; then
    fail "Usage: $0 [--rollback BACKUP_DIRECTORY]"
fi

if test -n "${TADA_AGENT_CODEX_BIN:-}"; then
    CODEX_BIN="$TADA_AGENT_CODEX_BIN"
elif test -x "$APP_CODEX"; then
    CODEX_BIN="$APP_CODEX"
else
    CODEX_BIN=$(command -v codex 2>/dev/null || true)
fi

for command in git gh python3 launchctl plutil shasum; do
    command -v "$command" >/dev/null 2>&1 || {
        printf 'Missing required command: %s\n' "$command" >&2
        exit 1
    }
done
if test -z "$CODEX_BIN" || test ! -x "$CODEX_BIN"; then
    printf 'Missing executable Codex CLI: %s\n' "${CODEX_BIN:-not found}" >&2
    exit 1
fi

python3 - "$MODEL_CATALOG" "$CODEX_MODEL" "$CODEX_REASONING_EFFORT" <<'PY'
import json
import sys
from pathlib import Path

catalog_path = Path(sys.argv[1])
model_slug = sys.argv[2]
reasoning_effort = sys.argv[3]
try:
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(f"Unable to verify the local Codex model catalog: {error}")

model = next(
    (item for item in catalog.get("models", []) if item.get("slug") == model_slug),
    None,
)
if model is None:
    raise SystemExit(f"Codex model is not present in the local catalog: {model_slug}")
levels = {
    item.get("effort") if isinstance(item, dict) else item
    for item in model.get("supported_reasoning_levels", [])
}
if reasoning_effort not in levels:
    raise SystemExit(
        f"Codex model {model_slug} does not advertise reasoning effort "
        f"{reasoning_effort}"
    )
PY

mkdir -p "$BIN_DIR" "$STATE_DIR" "$LOG_DIR" "$WORKTREE_ROOT" \
    "$BACKUP_ROOT" "${LAUNCH_AGENT:h}"
chmod 700 "$INSTALL_ROOT" "$STATE_DIR" "$BACKUP_ROOT"

gh auth status >/dev/null
"$CODEX_BIN" login status >/dev/null
"$CODEX_BIN" --ask-for-approval never exec \
    --config "model_reasoning_effort=\"$CODEX_REASONING_EFFORT\"" \
    --sandbox danger-full-access \
    --version >/dev/null

probe_key="$("$CODEX_BIN" --version)|$CODEX_MODEL|$CODEX_REASONING_EFFORT"
probe_marker="$STATE_DIR/codex-runtime-probe"
if ! grep -Fqx "$probe_key" "$probe_marker" 2>/dev/null; then
    probe_message=$(mktemp "$STATE_DIR/codex-runtime-probe-message.XXXXXX")
    if ! probe_output=$(printf 'Reply with exactly READY and do not use tools.\n' | \
        "$CODEX_BIN" --ask-for-approval never exec \
            --ignore-user-config \
            --model "$CODEX_MODEL" \
            --config "model_reasoning_effort=\"$CODEX_REASONING_EFFORT\"" \
            --sandbox read-only \
            --ephemeral \
            --color never \
            --json \
            --output-last-message "$probe_message" \
            --cd "$SCRIPT_DIR" \
            - 2>&1); then
        rm -f "$probe_message"
        printf 'Codex runtime probe failed for %s with model %s/%s:\n%s\n' \
            "$CODEX_BIN" "$CODEX_MODEL" "$CODEX_REASONING_EFFORT" \
            "$probe_output" >&2
        exit 1
    fi
    if ! grep -q '"type":"turn.completed"' <<<"$probe_output" \
        || test "$(tr -d '\r\n' <"$probe_message")" != READY; then
        rm -f "$probe_message"
        printf 'Codex runtime probe did not complete for %s with model %s/%s:\n%s\n' \
            "$CODEX_BIN" "$CODEX_MODEL" "$CODEX_REASONING_EFFORT" \
            "$probe_output" >&2
        exit 1
    fi
    rm -f "$probe_message"
    printf '%s\n' "$probe_key" >"$probe_marker"
    chmod 600 "$probe_marker"
fi

if test ! -d "$CONTROL_REPO/.git"; then
    git clone "https://github.com/$REPO_SLUG.git" "$CONTROL_REPO"
else
    if test -n "$(git -C "$CONTROL_REPO" status --porcelain)"; then
        printf 'Control repository is dirty; refusing to overwrite it: %s\n' \
            "$CONTROL_REPO" >&2
        exit 1
    fi
    git -C "$CONTROL_REPO" fetch origin main --prune
    git -C "$CONTROL_REPO" switch --detach origin/main
fi

stage_dir=$(mktemp -d "$INSTALL_ROOT/.install-stage.XXXXXX")
install_in_progress=false
handle_install_signal() {
    exit_code=$1
    trap - INT TERM
    if test "$install_in_progress" = true; then
        install_in_progress=false
        restore_backup "$backup_dir"
    fi
    exit "$exit_code"
}
trap 'rm -rf "$stage_dir"' EXIT
trap 'handle_install_signal 130' INT
trap 'handle_install_signal 143' TERM
install -d -m 700 "$stage_dir/bin"
install -m 755 "$SCRIPT_DIR/issue_agent.py" "$stage_dir/bin/issue_agent.py"
install -m 755 "$SCRIPT_DIR/run.sh" "$stage_dir/bin/run.sh"
install -m 644 "$SCRIPT_DIR/agent-prompt.md" "$stage_dir/bin/agent-prompt.md"
install -m 644 "$SCRIPT_DIR/release-policy.json" "$stage_dir/bin/release-policy.json"

{
    printf "export TADA_AGENT_REPO='%s'\n" "$REPO_SLUG"
    printf "export TADA_AGENT_CONTROL_REPO='%s'\n" "$CONTROL_REPO"
    printf "export TADA_AGENT_WORKTREE_ROOT='%s'\n" "$WORKTREE_ROOT"
    printf "export TADA_AGENT_STATE_DIR='%s'\n" "$STATE_DIR"
    printf "export TADA_AGENT_LOG_DIR='%s'\n" "$LOG_DIR"
    printf "export TADA_AGENT_MAX_ACTIVE_BATCHES='%s'\n" "$MAX_ACTIVE_BATCHES"
    printf "export TADA_AGENT_CODEX_BIN='%s'\n" "$CODEX_BIN"
    printf "export TADA_AGENT_MODEL='%s'\n" "$CODEX_MODEL"
    printf "export TADA_AGENT_REASONING_EFFORT='%s'\n" "$CODEX_REASONING_EFFORT"
} >"$stage_dir/bin/agent.env"
chmod 600 "$stage_dir/bin/agent.env"

sed \
    -e "s|__RUNNER__|$BIN_DIR/run.sh|g" \
    -e "s|__STDOUT__|$LOG_DIR/launchd.out.log|g" \
    -e "s|__STDERR__|$LOG_DIR/launchd.err.log|g" \
    "$SCRIPT_DIR/com.tadawords.issue-agent.plist.template" \
    >"$stage_dir/com.tadawords.issue-agent.plist"
chmod 644 "$stage_dir/com.tadawords.issue-agent.plist"
plutil -lint "$stage_dir/com.tadawords.issue-agent.plist" >/dev/null

backup_dir="$BACKUP_ROOT/$(date -u +%Y%m%dT%H%M%SZ)-$$"
install -d -m 700 "$backup_dir"
if test -d "$BIN_DIR" && test -n "$(find "$BIN_DIR" -mindepth 1 -maxdepth 1 -print -quit)"; then
    cp -pR "$BIN_DIR" "$backup_dir/bin"
fi
if test -f "$LAUNCH_AGENT"; then
    cp -p "$LAUNCH_AGENT" "$backup_dir/com.tadawords.issue-agent.plist"
fi
if test ! -d "$backup_dir/bin" && test ! -f "$backup_dir/com.tadawords.issue-agent.plist"; then
    printf 'No previous Issue Agent runtime was installed.\n' \
        >"$backup_dir/previous-install-absent"
fi
(
    cd "$backup_dir"
    for file in **/*(.DN); do
        test "$file" = manifest.sha256 && continue
        shasum -a 256 "$file"
    done
) >"$backup_dir/manifest.sha256"
chmod 600 "$backup_dir/manifest.sha256"
verify_backup "$backup_dir" || fail "Backup verification failed: $backup_dir"

install_in_progress=true
launchctl bootout "$domain" "$LAUNCH_AGENT" >/dev/null 2>&1 || true
if ! {
    install -m 755 "$stage_dir/bin/issue_agent.py" "$BIN_DIR/issue_agent.py" &&
    install -m 755 "$stage_dir/bin/run.sh" "$BIN_DIR/run.sh" &&
    install -m 644 "$stage_dir/bin/agent-prompt.md" "$BIN_DIR/agent-prompt.md" &&
    install -m 644 "$stage_dir/bin/release-policy.json" "$BIN_DIR/release-policy.json" &&
    install -m 600 "$stage_dir/bin/agent.env" "$BIN_DIR/agent.env" &&
    install -m 644 "$stage_dir/com.tadawords.issue-agent.plist" "$LAUNCH_AGENT" &&
    plutil -lint "$LAUNCH_AGENT" >/dev/null &&
    launchctl bootstrap "$domain" "$LAUNCH_AGENT" &&
    launchctl enable "$domain/com.tadawords.issue-agent" &&
    launchctl kickstart -k "$domain/com.tadawords.issue-agent"
}; then
    printf 'Issue Agent installation failed; restoring the verified backup.\n' >&2
    install_in_progress=false
    restore_backup "$backup_dir"
    exit 1
fi
install_in_progress=false

printf 'Installed com.tadawords.issue-agent (900-second interval, %s/%s).\n' \
    "$CODEX_MODEL" "$CODEX_REASONING_EFFORT"
printf 'Control repo: %s\nLogs: %s\nState: %s\n' \
    "$CONTROL_REPO" "$LOG_DIR" "$STATE_DIR"
printf "Verified backup: %s\nRollback: '%s' --rollback '%s'\n" \
    "$backup_dir" "$0" "$backup_dir"
