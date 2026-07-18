#!/bin/zsh

set -eu

LAUNCH_AGENT="/Users/macmini-dofu/Library/LaunchAgents/com.tadawords.issue-agent.plist"
domain="gui/$(id -u)"
launchctl bootout "$domain" "$LAUNCH_AGENT" >/dev/null 2>&1 || true
rm -f "$LAUNCH_AGENT"
printf 'Disabled com.tadawords.issue-agent. Logs, state, and worktrees were preserved.\n'
