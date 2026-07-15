#!/bin/zsh

set -eu

SCRIPT_DIR=${0:A:h}
CONFIG_FILE=${TADA_AGENT_CONFIG:-"$SCRIPT_DIR/agent.env"}
if test -f "$CONFIG_FILE"; then
    source "$CONFIG_FILE"
fi

: "${TADA_AGENT_REPO:=darrenfu/tadawords}"
: "${TADA_AGENT_CONTROL_REPO:?TADA_AGENT_CONTROL_REPO is required}"
: "${TADA_AGENT_WORKTREE_ROOT:=/Users/macmini-dofu/Documents/Tada Words Worktrees}"
: "${TADA_AGENT_STATE_DIR:=/Users/macmini-dofu/Library/Application Support/TadaWordsIssueAgent/state}"
: "${TADA_AGENT_LOG_DIR:=/Users/macmini-dofu/Library/Logs/TadaWordsIssueAgent}"
: "${TADA_AGENT_MAX_ACTIVE_BATCHES:=2}"

mkdir -p "$TADA_AGENT_STATE_DIR" "$TADA_AGENT_LOG_DIR" "$TADA_AGENT_WORKTREE_ROOT"

LOCK_DIR="$TADA_AGENT_STATE_DIR/run.lock"
acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        print -r -- "$$" >"$LOCK_DIR/pid"
        return 0
    fi

    old_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
    if test -n "$old_pid" && kill -0 "$old_pid" 2>/dev/null; then
        print -r -- "$(date -u +%FT%TZ) poll skipped: worker pid $old_pid is active" \
            >>"$TADA_AGENT_LOG_DIR/poll.log"
        return 1
    fi

    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR"
    print -r -- "$$" >"$LOCK_DIR/pid"
}

acquire_lock || exit 0
trap 'rm -rf "$LOCK_DIR"' EXIT INT TERM

stamp=$(date -u +%Y%m%dT%H%M%SZ)
snapshot="$TADA_AGENT_STATE_DIR/snapshot-$stamp.json"
last_message="$TADA_AGENT_LOG_DIR/run-$stamp-final.md"
event_log="$TADA_AGENT_LOG_DIR/run-$stamp.jsonl"

python3 "$SCRIPT_DIR/issue_agent.py" inspect \
    --repo "$TADA_AGENT_REPO" \
    --control-repo "$TADA_AGENT_CONTROL_REPO" \
    --worktree-root "$TADA_AGENT_WORKTREE_ROOT" \
    --state-dir "$TADA_AGENT_STATE_DIR" \
    --max-active-batches "$TADA_AGENT_MAX_ACTIVE_BATCHES" \
    --pretty >"$snapshot"

should_run=$(python3 -c 'import json,sys; print("true" if json.load(open(sys.argv[1]))["should_run"] else "false")' "$snapshot")
if test "$should_run" != true; then
    print -r -- "$(date -u +%FT%TZ) safe no-op; snapshot=$snapshot" \
        >>"$TADA_AGENT_LOG_DIR/poll.log"
    find "$TADA_AGENT_STATE_DIR" -name 'snapshot-*.json' -mtime +30 -delete
    exit 0
fi

{
    cat "$SCRIPT_DIR/agent-prompt.md"
    printf '\n\n## Immutable preflight snapshot\n\n```json\n'
    cat "$snapshot"
    printf '```\n'
} | codex exec \
    --cd "$TADA_AGENT_CONTROL_REPO" \
    --add-dir "$TADA_AGENT_WORKTREE_ROOT" \
    --sandbox danger-full-access \
    --ask-for-approval never \
    --ephemeral \
    --color never \
    --json \
    --output-last-message "$last_message" \
    - >"$event_log" 2>&1

python3 "$SCRIPT_DIR/issue_agent.py" acknowledge \
    --snapshot "$snapshot" \
    --state-dir "$TADA_AGENT_STATE_DIR"

find "$TADA_AGENT_LOG_DIR" -type f -mtime +30 -delete
find "$TADA_AGENT_STATE_DIR" -name 'snapshot-*.json' -mtime +30 -delete
