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

## Human acceptance

- [ ] Product behavior reviewed on iPhone
- [ ] Product behavior reviewed on iPad
- [ ] Copy and visual behavior accepted
- [ ] Current HEAD confirmed

To authorize squash merge, the repository owner must comment:

`/merge <current HEAD SHA>`

Any new commit invalidates previous device evidence and authorization.
