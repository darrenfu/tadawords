# Intake and release batches

[Back to module index](README.md)

## Intake

For every request to implement or change repository behavior, the first action
is GitHub intake. Before editing code, search open and closed Issues, open and
merged PRs, and `origin/*` implementation branches. Deduplicate against exact
existing scope, split any uncovered work into focused Issues, and create only
the missing Issues. When a new or existing Issue is sufficiently specified and
safe to execute, apply `agent-ready` if needed and immediately reclaim it with
`agent-reclaimed` before implementation begins. Re-fetch immediately before
that first mutation; another claim, blocker, PR, or remote branch wins the race.

Do not create or mutate Issues for requests that only ask for an answer,
diagnosis, review, explanation, or status report. Create Issues when that work
later becomes an implementation request. Split unrelated implementation goals
into separate Issues.

Each Issue must preserve concrete user wording and contain current behavior,
expected behavior, reproduction steps, acceptance criteria, device coverage,
edge cases, out-of-scope boundaries, area, and risk. Apply `agent-ready` only
when the task is sufficiently specified. Use `needs-human-clarification` when a
missing decision could materially change the implementation.

Pickup is limited to an open `agent-ready` Issue with no blocker label,
unresolved dependency, material ambiguity, existing claim, open implementation
PR, or live `origin/*` implementation branch. Before pickup, check PR coverage
by exact Issue linkage and inspect the relevant remote branch diff. For an open
PR, apply `implementation-in-pr`, comment its exact link and HEAD, and skip it;
for a live branch, comment its exact ref and HEAD and skip it. Close a stale
Issue only when an exact closing reference belongs to a PR merged into the
default branch and the merge commit is present in current `origin/main`.
Similar titles, keywords, or inferred feature overlap are never enough to close
an Issue.

## Release batches

Before claiming one ready Issue, scan every open, unreclaimed `agent-ready`
Issue and inspect the affected code. Treat both `agent-reclaimed` and the legacy
`agent-claimed` label as active ownership. Group Issues only when they share a
coherent module, capability, user flow, test surface, and rollback boundary.
Examples:

- `area:parent`: Parent Home, Parent Gate, profiles, guardian settings.
- `area:audio`: speech, pronunciation, recording, audio packs, ducking.
- `area:import`: OCR, imports, presets, and word-pool management.

Do not group work merely because it arrived together. Split work with different
architectures, risk gates, rollback boundaries, or conflicting requirements.
The default maximum is five Issues per batch. A larger or ambiguous batch needs
human approval.

One batch owns one branch, one worktree, one version, and one PR. Development
may use multiple focused commits; the final merge is squash-merge. Once work
starts, newly arriving related Issues normally go to the next batch so scope
does not grow without bound.

Admission is repository-wide and sequential by dependency, owner priority, and
existing remote ownership; area labels alone never authorize a later Issue to
jump the queue. An older open PR, reclaimed Issue, or `origin/*` implementation
branch blocks duplicate or dependent pickup until its current exact HEAD reaches
the required gates or is explicitly abandoned. The configured active-batch
limit is only a safety ceiling, not permission to parallelize. A second batch
requires explicit owner authorization and evidence that it is independent in
dependencies, runtime state, device lane, risk, and rollback. Only one new batch
may be reclaimed per poll. Actionable review, resume, stale-claim, exact-HEAD
verification, and merge events take priority over starting a new batch.
