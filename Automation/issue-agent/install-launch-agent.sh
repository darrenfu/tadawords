#!/bin/zsh

set -eu

SCRIPT_DIR=${0:A:h}
REPO_SLUG=${TADA_AGENT_REPO:-darrenfu/tadawords}
INSTALL_ROOT=${TADA_AGENT_INSTALL_ROOT:-"/Users/macmini-dofu/Library/Application Support/TadaWordsIssueAgent"}
WORKTREE_ROOT=${TADA_AGENT_WORKTREE_ROOT:-"/Users/macmini-dofu/Documents/Tada Words Worktrees"}
LOG_DIR=${TADA_AGENT_LOG_DIR:-"/Users/macmini-dofu/Library/Logs/TadaWordsIssueAgent"}
MAX_ACTIVE_BATCHES=${TADA_AGENT_MAX_ACTIVE_BATCHES:-2}
STATE_DIR="$INSTALL_ROOT/state"
CONTROL_REPO="$INSTALL_ROOT/control-repo"
BIN_DIR="$INSTALL_ROOT/bin"
LAUNCH_AGENT="/Users/macmini-dofu/Library/LaunchAgents/com.tadawords.issue-agent.plist"

for command in git gh codex python3; do
    command -v "$command" >/dev/null 2>&1 || {
        printf 'Missing required command: %s\n' "$command" >&2
        exit 1
    }
done
gh auth status >/dev/null
codex login status >/dev/null
codex --ask-for-approval never exec \
    --sandbox danger-full-access \
    --version >/dev/null

mkdir -p "$BIN_DIR" "$STATE_DIR" "$LOG_DIR" "$WORKTREE_ROOT" \
    "${LAUNCH_AGENT:h}"
install -m 755 "$SCRIPT_DIR/issue_agent.py" "$BIN_DIR/issue_agent.py"
install -m 755 "$SCRIPT_DIR/run.sh" "$BIN_DIR/run.sh"
install -m 644 "$SCRIPT_DIR/agent-prompt.md" "$BIN_DIR/agent-prompt.md"

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

{
    printf "export TADA_AGENT_REPO='%s'\n" "$REPO_SLUG"
    printf "export TADA_AGENT_CONTROL_REPO='%s'\n" "$CONTROL_REPO"
    printf "export TADA_AGENT_WORKTREE_ROOT='%s'\n" "$WORKTREE_ROOT"
    printf "export TADA_AGENT_STATE_DIR='%s'\n" "$STATE_DIR"
    printf "export TADA_AGENT_LOG_DIR='%s'\n" "$LOG_DIR"
    printf "export TADA_AGENT_MAX_ACTIVE_BATCHES='%s'\n" "$MAX_ACTIVE_BATCHES"
} >"$BIN_DIR/agent.env"
chmod 600 "$BIN_DIR/agent.env"

sed \
    -e "s|__RUNNER__|$BIN_DIR/run.sh|g" \
    -e "s|__STDOUT__|$LOG_DIR/launchd.out.log|g" \
    -e "s|__STDERR__|$LOG_DIR/launchd.err.log|g" \
    "$SCRIPT_DIR/com.tadawords.issue-agent.plist.template" >"$LAUNCH_AGENT"
plutil -lint "$LAUNCH_AGENT" >/dev/null

domain="gui/$(id -u)"
launchctl bootout "$domain" "$LAUNCH_AGENT" >/dev/null 2>&1 || true
launchctl bootstrap "$domain" "$LAUNCH_AGENT"
launchctl enable "$domain/com.tadawords.issue-agent"
launchctl kickstart -k "$domain/com.tadawords.issue-agent"

printf 'Installed com.tadawords.issue-agent (600-second interval).\n'
printf 'Control repo: %s\nLogs: %s\nState: %s\n' \
    "$CONTROL_REPO" "$LOG_DIR" "$STATE_DIR"
