# Tada Words Issue Agent

This local worker polls GitHub every ten minutes, performs a deterministic
read-only preflight, and starts Codex only when there is actionable work. An
empty queue is a safe no-op. The worker uses a dedicated clean control clone and
creates release worktrees outside the user's normal checkout.

The default admission limit is two open agent Release Batches. An open PR blocks
new work in the same `area`, but an unrelated area can claim the remaining slot
in its own worktree. Only one new batch is started per poll, and physical-device
deployment remains serialized. Set `TADA_AGENT_MAX_ACTIVE_BATCHES` before
installation to choose a different bounded limit.

Installation prefers the CLI bundled with the installed ChatGPT/Codex app over
an older shell `PATH` copy, then parses the unattended approval/sandbox flags
and runs one cached model round trip before loading the LaunchAgent. The worker
uses an isolated config plus the explicit `gpt-5.6-sol` default, so unrelated
user plugins and a stale local model setting cannot strand actionable Issues.
Set `TADA_AGENT_CODEX_BIN` or `TADA_AGENT_MODEL` before installation to override
either value. The model probe reruns only when the selected CLI version or model
changes.

## Install

```sh
./Automation/issue-agent/install-launch-agent.sh
```

The installer verifies `gh` and Codex authentication, installs a launchd user
agent, creates a clean control clone under `~/Library/Application Support`, and
starts the first poll. No GitHub token is copied into repository files.

## Dry run

```sh
python3 Automation/issue-agent/issue_agent.py inspect \
  --repo darrenfu/tadawords \
  --control-repo '/path/to/a/clean/tadawords/clone' \
  --worktree-root '/Users/macmini-dofu/Documents/Tada Words Worktrees' \
  --state-dir '/tmp/tadawords-issue-agent-state' \
  --max-active-batches 2 \
  --pretty
```

Inspect the active job and recent logs:

```sh
launchctl print gui/$(id -u)/com.tadawords.issue-agent
tail -50 '/Users/macmini-dofu/Library/Logs/TadaWordsIssueAgent/poll.log'
```

To resume a human-resolved blocker, comment `/resume` on the blocked Issue or
`/resume <current-head-sha>` on its PR. To authorize merge after reviewing the
exact tested build, comment `/merge <current-head-sha>` on the PR.

## Uninstall

```sh
./Automation/issue-agent/uninstall-launch-agent.sh
```

Uninstalling disables future polls but intentionally preserves logs, state, and
worktrees for audit and recovery.
