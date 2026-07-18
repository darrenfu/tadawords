#!/bin/zsh

set -eu
umask 077

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
: "${TADA_AGENT_MAX_ACTIVE_BATCHES:=1}"
: "${TADA_AGENT_MODEL:=gpt-5.6-sol}"
: "${TADA_AGENT_REASONING_EFFORT:=ultra}"
if test -z "${TADA_AGENT_CODEX_BIN:-}"; then
    TADA_AGENT_CODEX_BIN=$(command -v codex)
fi

mkdir -p "$TADA_AGENT_STATE_DIR" "$TADA_AGENT_LOG_DIR" "$TADA_AGENT_WORKTREE_ROOT"

LOCK_FILE="$TADA_AGENT_STATE_DIR/run.lock"
exec 9>"$LOCK_FILE"
if ! /usr/bin/lockf -s -t 0 9; then
    print -r -- "$(date -u +%FT%TZ) poll skipped: another worker holds $LOCK_FILE" \
        >>"$TADA_AGENT_LOG_DIR/poll.log"
    exit 0
fi

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

has_reconciliation_actions=$(python3 -c 'import json,sys; print("true" if json.load(open(sys.argv[1])).get("reconciliation_actions") else "false")' "$snapshot")
if test "$has_reconciliation_actions" = true; then
    python3 "$SCRIPT_DIR/issue_agent.py" reconcile \
        --snapshot "$snapshot" \
        --repo "$TADA_AGENT_REPO" \
        --control-repo "$TADA_AGENT_CONTROL_REPO"
    python3 "$SCRIPT_DIR/issue_agent.py" inspect \
        --repo "$TADA_AGENT_REPO" \
        --control-repo "$TADA_AGENT_CONTROL_REPO" \
        --worktree-root "$TADA_AGENT_WORKTREE_ROOT" \
        --state-dir "$TADA_AGENT_STATE_DIR" \
        --max-active-batches "$TADA_AGENT_MAX_ACTIVE_BATCHES" \
        --pretty >"$snapshot"
fi

should_run=$(python3 -c 'import json,sys; print("true" if json.load(open(sys.argv[1]))["should_run"] else "false")' "$snapshot")
if test "$should_run" != true; then
    print -r -- "$(date -u +%FT%TZ) safe no-op; snapshot=$snapshot" \
        >>"$TADA_AGENT_LOG_DIR/poll.log"
    find "$TADA_AGENT_STATE_DIR" -name 'snapshot-*.json' -mtime +30 -delete
    exit 0
fi

has_claimable_batch=$(python3 -c 'import json,sys; print("true" if json.load(open(sys.argv[1])).get("claimable_batches") else "false")' "$snapshot")
if test "$has_claimable_batch" = true; then
    python3 "$SCRIPT_DIR/issue_agent.py" reserve \
        --snapshot "$snapshot" \
        --repo "$TADA_AGENT_REPO" \
        --control-repo "$TADA_AGENT_CONTROL_REPO"
fi

export TADA_AGENT_SNAPSHOT="$snapshot"
export TADA_AGENT_CORE="$SCRIPT_DIR/issue_agent.py"
export TADA_AGENT_REPO TADA_AGENT_CONTROL_REPO TADA_AGENT_STATE_DIR

{
    cat "$SCRIPT_DIR/agent-prompt.md"
    printf '\n\n## Immutable preflight snapshot\n\n```json\n'
    cat "$snapshot"
    printf '```\n'
} | "$TADA_AGENT_CODEX_BIN" --ask-for-approval never exec \
    --ignore-user-config \
    --model "$TADA_AGENT_MODEL" \
    --config "model_reasoning_effort=\"$TADA_AGENT_REASONING_EFFORT\"" \
    --cd "$TADA_AGENT_CONTROL_REPO" \
    --add-dir "$TADA_AGENT_WORKTREE_ROOT" \
    --sandbox danger-full-access \
    --ephemeral \
    --color never \
    --json \
    --output-last-message "$last_message" \
    - >"$event_log" 2>&1

if ! python3 "$SCRIPT_DIR/issue_agent.py" acknowledge \
    --snapshot "$snapshot" \
    --state-dir "$TADA_AGENT_STATE_DIR" \
    --repo "$TADA_AGENT_REPO" \
    --control-repo "$TADA_AGENT_CONTROL_REPO" \
    --require-durable-outcome; then
    print -r -- "$(date -u +%FT%TZ) run not acknowledged: no durable GitHub outcome; snapshot=$snapshot" \
        >>"$TADA_AGENT_LOG_DIR/poll.log"
    exit 1
fi

find "$TADA_AGENT_LOG_DIR" -type f -mtime +30 -delete
find "$TADA_AGENT_STATE_DIR" -name 'snapshot-*.json' -mtime +30 -delete
