# Tada Words Issue Agent

This local worker polls GitHub every 15 minutes, performs a deterministic
read-only preflight, and starts Codex only when there is actionable work. An
empty queue is a safe no-op. The worker uses a dedicated clean control clone and
creates release worktrees outside the user's normal checkout.

Run exactly one mutating scheduler host for this repository. The host-level lock
serializes polls on that Mac; GitHub labels, PRs, and `origin/*` branches provide
the durable ownership record visible to interactive sessions and other agents.
Additional hosts must remain disabled or read-only. A worker must re-fetch
GitHub immediately before its first mutation and yield when it finds a claim,
blocker, open implementation PR, or live remote implementation branch.

The default admission limit is two open agent Release Batches, but it is a
safety ceiling rather than permission to parallelize. Admission is sequential
by dependencies, owner priority, open PRs, existing claims, and remote branches;
an `area` label alone cannot let later work jump the queue. A second independent
batch requires explicit owner authorization. Only one new batch starts per poll,
and physical-device deployment remains serialized. Set
`TADA_AGENT_MAX_ACTIVE_BATCHES` before installation only when the owner has
explicitly authorized a different bound.

Installation prefers the CLI bundled with the installed ChatGPT/Codex app over
an older shell `PATH` copy, then parses the unattended approval/sandbox flags
and runs one cached model round trip before loading the LaunchAgent. The worker
uses an isolated config plus the explicit `gpt-5.6-sol` default, so unrelated
user plugins and a stale local model setting cannot strand actionable Issues.
Reasoning defaults to `ultra` (Sol Ultra) for unattended pickup and delivery.
Set `TADA_AGENT_CODEX_BIN`,
`TADA_AGENT_MODEL`, or `TADA_AGENT_REASONING_EFFORT` before installation to
override them. The model probe reruns only when the selected CLI version, model,
or effort changes.

`release-policy.json` is installed beside the worker and is checked during both
inspection and reservation. Until an owner-authorized policy change records the
first public App Store release (URL, released version/build, exact manifest, and
authorization), the worker fails closed on versions above `v1.0.0`. Examples in
Issue prose do not reserve versions; explicit labels, PRs, refs, and planned
reservation fields do.

## Pickup and stale-Issue policy

Only an open `agent-ready` Issue with no blocker, unresolved dependency,
material ambiguity, existing claim, open implementation PR, or live
implementation branch is claimable. Each implementation/change request follows
the same order, whether it arrives through the scheduler or an interactive
session:

1. Search and deduplicate GitHub Issues.
2. Break down the uncovered scope and create only missing Issues.
3. Check open PRs, PRs merged to `origin/main`, and `origin/*` implementation
   branches for exact ownership or completion evidence.
4. Re-fetch the Issue, then make `agent-reclaimed` the first pickup mutation.
5. Reserve and push the batch branch before editing implementation files.

An open PR gets `implementation-in-pr` plus a comment naming its exact URL and
HEAD, then is skipped. A live implementation branch gets a comment naming its
exact ref and HEAD, then is skipped. Neither is duplicated or automatically
closed. A stale Issue may be closed only when a PR has an exact closing
reference, is merged into the default branch, and its merge commit is present
in the current `origin/main`. Title similarity, fuzzy keywords, or apparent
feature overlap never authorize an automatic close.

Pickup is ordered by `priority:P0`, `P1`, `P2`, `P3`, then unspecified, with
dependencies ahead of Issue number. If a claimed Issue has or discovers a
blocker, the worker posts an evidence-backed blocker report, applies
`agent-blocked`, removes both claim labels, and releases its verified lease.
Continuation after recovery always requires a fresh reclaim.

The poll is acknowledged only after a durable outcome can be re-fetched from
GitHub: a closed Issue, a linked open PR or remote branch owner, a pushed batch
reservation, or an explicit blocker/clarification label and evidence comment.
A zero Codex exit status alone is not an acknowledgement.

## Install

```sh
./Automation/issue-agent/install-launch-agent.sh
```

The installer verifies `gh` and Codex authentication, installs a launchd user
agent, creates a clean control clone under `~/Library/Application Support`, and
starts the first poll. No GitHub token is copied into repository files.

Before replacing a live installation, the installer preserves the prior plist
and installed `bin` directory under
`~/Library/Application Support/TadaWordsIssueAgent/backups/<timestamp>/`, with
restricted permissions and checksums. It stages and probes the new CLI/model
configuration before unloading the working LaunchAgent.

## Dry run

```sh
python3 Automation/issue-agent/issue_agent.py inspect \
  --repo darrenfu/tadawords \
  --control-repo '/path/to/a/clean/tadawords/clone' \
  --worktree-root '/Users/macmini-dofu/Documents/Tada Words Worktrees' \
  --state-dir '/tmp/tadawords-issue-agent-state' \
  --max-active-batches 1 \
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

## Recovery and rollback

If a new poller fails, disable and boot out
`gui/$(id -u)/com.tadawords.issue-agent`, restore the most recent backup's plist
and `bin` contents with their recorded modes, then bootstrap and enable that
plist again. Preserve logs, state, worktrees, remote branches, and GitHub labels
until ownership has been reconciled; rollback must not erase audit evidence.
After restoration, verify the loaded program, 900-second interval, selected
model/effort, lock behavior, and one safe no-op poll before declaring recovery.
Never acknowledge a partially handled event merely because the process exited.

## Uninstall

```sh
./Automation/issue-agent/uninstall-launch-agent.sh
```

Uninstalling disables future polls but intentionally preserves logs, state, and
worktrees for audit and recovery.
