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
uses an isolated config plus the explicit `gpt-5.6-terra` default, so unrelated
user plugins and a stale local model setting cannot strand actionable Issues.
Reasoning defaults to `medium` for unattended pickup and routine delivery.
Bounded architecture, synchronization, security, signing, or final release
decisions may explicitly override this with Terra/high or Sol/high. Ultra is
never the unattended default.
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
5. Reserve and push the batch branch, then acquire its PR-writer lease before
   editing implementation files.

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
`/resume <current-head-sha>` on its PR.

## Exact-HEAD automatic merge

A ready, non-draft agent PR targeting `main` directly, carrying
`awaiting-human-review`, and having no blocker or current changes-requested
review produces a deterministic `automatic_merge_candidate` event keyed by its
full HEAD SHA, the PR's live `baseRefOid`, PR-body SHA-256 digest, and verified
canonical closing-reference digest, and verified branch-protection contract
digest. The repository
owner's standing authorization permits Codex to squash-merge that candidate
without a separate GitHub comment, but only after a fresh exact-HEAD preflight
confirms mergeable/clean state, required checks, evidence applicable to the
declared R0-R4 tier, dependencies, and every remaining product or risk gate. A
new commit produces a new event ID and invalidates evidence for the prior HEAD;
full archive/device evidence is required only for a frozen R4 candidate.
Stacked and other non-`main` PRs never produce automatic candidates. A base edit
or any PR-body edit invalidates the candidate even when the commit SHA is
unchanged; the worker must re-fetch the full body digest and exact closing set
immediately before merge. The closing set comes from the paginated GraphQL
`closingIssuesReferences` connection, so Development-sidebar links and
qualified same-repository syntax cannot be missed; cross-repository closing
references, GraphQL partial errors, and malformed pagination fail closed. A PR
with only `Refs #N` and no canonical closing
reference remains eligible.

Automatic merge is disabled unless GitHub itself protects `main` with strict
up-to-date required checks, admin enforcement, pull-request entry, linear
history, resolved conversations, no force push/deletion, and the required
`tadawords/exact-head-gates` context. The canonical reversible configuration is
[`main-branch-protection.json`](main-branch-protection.json). The worker never
uses an admin bypass, update-branch, or automatic rebase.

After all checks and evidence applicable to the declared tier pass, the agent
must call `issue_agent.py guarded-merge`; direct merge
commands are forbidden. The core command re-fetches the complete candidate,
durably records preparation, atomically acquires
`refs/heads/agent-leases/merge-critical`, posts the exact-HEAD gate status,
re-fetches again, records a sent-or-unknown intent immediately before the
request, and sends a squash merge request with the full HEAD as the server-side
compare-and-swap value. Its fixed commit title/message cannot introduce a new
closing keyword. Strict branch protection rejects a base race. Pending intents
are never capacity-truncated, survive process death, and are restored on later
polls even after a PR disappears from the open-PR listing. Once a request is
sent or its outcome is unknown, the worker only reconciles and never resends.
Acknowledgement first fsyncs both the durable outcome and an outstanding lease
cleanup record while the lease is still held. It then deletes that exact unique
lease with compare-and-swap and fsyncs cleanup completion. Every poll recovers
unfinished cleanup before inspection, so a crash cannot create an unowned
metadata-write window.

GitHub does not provide compare-and-swap for PR body, labels, or closing-link
metadata. Every automated repository writer therefore treats the
merge-critical remote ref as an exclusive lease and stops metadata mutations
while it is owned. The repository currently has one direct writer. Owner edits
during the critical section remain an explicit trusted-operator boundary, not
a claimed GitHub-atomic guarantee.

`/merge <current-head-sha>` remains an optional compatible command. It creates
the legacy `merge_authorized` event but does not bypass the same preflight.

After merging, the worker fetches `origin/main` and refuses durable
acknowledgement until the PR still names the tested HEAD, its merge commit is
reachable from `origin/main`, its tree matches the tested HEAD tree, its first
parent matches the tested base OID, its body digest and paginated canonical
closing set match the event, and every recorded closing reference is closed
through that PR. An unchanged open PR and a PR
closed without merge are not durable merge outcomes merely because Codex exited
successfully.

## Recovery and rollback

If a new poller fails, disable and boot out
`gui/$(id -u)/com.tadawords.issue-agent`, restore the most recent backup's plist
and `bin` contents with their recorded modes, then bootstrap and enable that
plist again. Preserve logs, state, worktrees, remote branches, and GitHub labels
until ownership has been reconciled; rollback must not erase audit evidence.
After restoration, verify the loaded program, 900-second interval, selected
model/effort, lock behavior, and one safe no-op poll before declaring recovery.
Never acknowledge a partially handled event merely because the process exited.

To restore the prior mandatory-comment merge gate, revert the Issue #85 policy
commit, run the installer so the verified repository copy replaces the installed
worker, and retain the existing backup, logs, state, worktrees, remote branches,
and GitHub labels. After disabling the worker and confirming no pending merge
intent, restore the recorded pre-change branch protection (it was absent before
Issue #85) so the retired exact-head context cannot deadlock every PR. Verify the
restored program, 900-second interval, lock, and one safe no-op poll before
re-enabling work. The restored worker again waits for
an exact owner `/merge <current-head-sha>` comment. If rollback cannot be
completed atomically, disable the LaunchAgent or apply a blocker rather than
running mixed policy versions.

## Uninstall

```sh
./Automation/issue-agent/uninstall-launch-agent.sh
```

Uninstalling disables future polls but intentionally preserves logs, state, and
worktrees for audit and recovery.
