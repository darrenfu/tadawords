# Guarded merge and reconciliation

[Back to module index](README.md)

The only permitted automatic mutation is
`Automation/issue-agent/issue_agent.py guarded-merge` with the immutable
snapshot event ID and exact tested HEAD. Direct `gh pr merge`, pull-request
merge API, `git push main`, update-branch, rebase, or admin-bypass calls are
forbidden. The guarded command persists an fsync-backed intent before mutation,
posts the required exact-HEAD status, re-fetches every identity field, and uses
the full HEAD as GitHub's merge compare-and-swap. A recovered pending intent is
verified before new work; any sent-or-unknown request is reconciliation-only
and can never be sent twice.

The guarded command also owns the repository-wide remote ref
`refs/heads/agent-leases/merge-critical` from its final metadata check through
durable acknowledgement. Every automated writer must check this ref before
changing a PR title/body, labels, reviews, checks, closing links, or merge state
and must stop when another event owns it. GitHub offers an exact HEAD CAS and
strict base/check protection, but no CAS for PR metadata. Metadata race safety
therefore relies on this enforced single-writer lease and on the repository
owner not editing merge-critical metadata during that short critical section;
do not describe this trust boundary as a GitHub-atomic guarantee.
Durable acknowledgement is two-phase: while still holding the lease, fsync the
verified outcome plus an outstanding cleanup record; delete only that unique
lease commit with compare-and-swap; then fsync cleanup completion. Each worker
poll must recover unfinished cleanup before any repository inspection.

After merge, fetch `origin/main` and verify the PR reports the same tested HEAD,
its merge commit is reachable from `origin/main`, the merged tree equals the
tested HEAD tree, the merge commit's first parent equals the recorded base OID,
the merged PR body retains the recorded SHA-256 digest and canonical
closing-Issue set, and every recorded Issue closed through that PR as intended.
A PR
closed without merge is not a successful or durable merge outcome. Do not
acknowledge the merge event or claim completion until these checks pass.
