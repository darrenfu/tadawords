## Release batch

- Batch ID:
- Included Issues:
  - Closes #
- Previous version:
- New version:
- Build number:
- Current HEAD SHA:
- Risk:

## Outcome

Describe the user-visible result and why these Issues form one coherent module,
test surface, and rollback boundary.

## Scope boundary

- Included:
- Explicitly excluded:
- Follow-up Issues:

## Automated evidence

- [ ] Strict format/lint
- [ ] Swift unit and integration tests
- [ ] Regression tests for every included bug
- [ ] iPhone simulator build and relevant E2E
- [ ] iPad simulator build and relevant E2E

List exact commands, totals, failures, artifact paths, and the tested HEAD SHA.

## Physical-device evidence

Mark each device row `N/A` only when the diff cannot affect app runtime,
signing, persistence, or packaged content and changes no app/LocalQA
version/build metadata, source/generated Plist, `project.yml`, generated Xcode
project, entitlement, resource, or package input. Otherwise provide exact-HEAD
signed evidence for one iPhone and one iPad.

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
- [ ] Current PR-body SHA-256 and complete `Closes #N` set match the candidate
- [ ] Required checks and all applicable artifact/device evidence pass on this HEAD
- [ ] No blocker, unresolved requested change, stale evidence, dependency, or high-risk decision remains
- [ ] Product behavior/copy/visual acceptance is complete, or is `N/A` with rationale

The repository owner's standing authorization permits Codex to squash-merge
only after every row above is reverified. The owner may optionally comment:

`/merge <current HEAD SHA>`

The command is compatible but is not required and never substitutes for a
gate. Any new commit invalidates previous evidence and merge readiness.

## Post-merge verification

- [ ] Fetched `origin/main` after merge
- [ ] PR merged the same tested HEAD and its merge commit is reachable from `origin/main`
- [ ] Merged tree equals the tested HEAD tree
- [ ] Merged PR body retains the recorded SHA-256/closing set and every exact closing reference closed through this PR
