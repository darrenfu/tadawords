# Intake, ownership, and sessions

[Back to module index](README.md)

Implementation begins with bounded GitHub intake: inspect the named Issue, its
exact linked/open PRs, and relevant live remote branches. Create only missing
Issues. Re-fetch immediately before the first mutation; another claim, PR,
branch, blocker, or lease wins the race. Apply `agent-reclaimed` as the first
pickup mutation.

Do not mutate GitHub for answer-, diagnosis-, review-, explanation-, or
status-only work. One batch owns one branch, dedicated worktree, PR, rollback
boundary, and writer. New requirements normally enter a later PR; never attach
new scope after an R4 candidate is frozen.

Use one fresh root session per Issue/PR. Acquire a `pr-writer` lease before
editing. Other sessions may inspect or review read-only. Routine work has no
subagents; complex investigation permits at most two direct, non-nested,
read-only subagents.

At the first context compaction, checkpoint at most 2 KB: Issue, PR, worktree,
branch, full HEAD, leases, changed files, evidence, blockers, and next command.
End the old session and continue fresh. An unchanged-HEAD status request reads
evidence instead of rerunning work. Default routine/unattended implementation
to Terra/medium and escalate only for bounded high-risk decisions.

Two independent iOS Issues may proceed concurrently only with explicit owner
authorization and separate PRs, writers, Xcode/device leases, mutable state,
and rollback boundaries.
