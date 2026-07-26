## Change batch

- Batch ID:
- Included Issues:
  - Closes #
- Risk tier: R0 / R1 / R2 / R3 / R4
- Tier rationale:
- Current HEAD SHA:
- Risk:
- Scope frozen: yes / no
- PR writer lease owner:

### Versioned artifact (R4 or explicitly requested only)

- Previous version:
- New version:
- Build number:

## Outcome

Describe the user-visible result and why these Issues form one coherent module,
test surface, and rollback boundary.

## Scope boundary

- Included:
- Explicitly excluded:
- Follow-up Issues:

## Development and PR evidence

- [ ] `make check-changed` focused checks
- [ ] `make check-pr` normal PR gate
- [ ] Regression tests for every included bug
- [ ] Simulator evidence required by the declared tier
- [ ] HEAD-unchanged evidence was reused rather than rerun

List exact commands, totals, artifact/evidence paths, and the tested HEAD SHA.

### R4 evidence

- [ ] `make check-rc`
- [ ] Frozen exact-HEAD archive/export identity
- [ ] Required iPhone and iPad simulator matrix
- [ ] TestFlight/App Store state, if applicable

## Physical-device evidence

R0/R1 use no physical device. R2 may use at most one representative experience
check after scope freeze. R3 uses only affected device classes; two devices are
required only for cross-device behavior. R4 requires the approved iPhone and
iPad. Record `N/A` with the tier rationale.

### iPhone

- Device / OS / identifier:
- Version / build / commit:
- Signed-app identity verification:
- Install:
- Launch smoke:
- Automated device test:
- Manual acceptance remaining:

### iPad

- Device / OS / identifier:
- Version / build / commit:
- Signed-app identity verification:
- Install:
- Launch smoke:
- Automated device test:
- Manual acceptance remaining:

## Risk, rollback, and known limitations

- Risk:
- Rollback:
- Known limitations:

## Exact-HEAD merge readiness

- [ ] Current full HEAD SHA re-fetched and unchanged
- [ ] PR is ready, mergeable, clean, and targets `main` directly
- [ ] Per-PR `baseRefOid` is pinned and still equals fresh `origin/main`
- [ ] `main` protection matches the strict exact-head contract and applies to admins
- [ ] Current PR-body SHA-256 and paginated canonical closing-reference set match the candidate; cross-repo closures are absent
- [ ] Repository merge-critical lease is free or owned by this exact event, and automated metadata writers are quiesced
- [ ] Required checks and all applicable artifact/device evidence pass on this HEAD
- [ ] No blocker, unresolved requested change, stale evidence, dependency, or high-risk decision remains
- [ ] Product behavior/copy/visual acceptance is complete, or is `N/A` with rationale

The repository owner's standing authorization permits Codex to squash-merge
only after every row above is reverified. The owner may optionally comment:

`/merge <current HEAD SHA>`

The command is compatible but is not required and never substitutes for a
gate. Any new commit invalidates evidence for the previous HEAD; rerun only
checks applicable to the declared tier. Full archive/device evidence is
collected only for a frozen R4 HEAD.
Automatic mutation must go through `issue_agent.py guarded-merge`; direct merge,
admin bypass, update-branch, rebase, and `git push main` are forbidden.
GitHub has no PR-metadata CAS, so the repository-wide remote merge lease is the
single-writer boundary; the owner must not edit merge-critical metadata while
that short critical section is active.

## Post-merge verification

- [ ] Fetched `origin/main` after merge
- [ ] PR merged the same tested HEAD and its merge commit is reachable from `origin/main`
- [ ] Merge commit first parent equals the recorded base OID
- [ ] Merged tree equals the tested HEAD tree
- [ ] Merged PR body retains the recorded SHA-256/canonical closing set and every recorded closing reference closed through this PR
- [ ] Sent-or-unknown intent was never retried, and the merge-critical lease was released only after durable verification
