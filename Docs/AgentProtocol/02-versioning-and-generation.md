# Risk tiers, versioning, and project generation

[Back to module index](README.md)

Classify every PR R0-R4 by behavior; mixed changes use the highest tier. The
table in root `AGENTS.md` is mandatory. R0 is allowed only when package,
runtime, persistent data, signing, resources, Plists, `project.yml`, and
generated Xcode settings are unaffected.

Ordinary R0-R3 PRs do not increment SemVer or build solely because a PR exists.
Reserve and synchronize marketing/build identity only for an R4 promotion or
an explicitly requested versioned artifact.

For R4, inspect current `main`, Plists, project settings, remote reservations,
PRs, tags, and labels before choosing a monotonically increasing build.
Synchronize production and LocalQA Plists, `project.yml`, generated project,
and release notes. Regenerate only with `make generate`; direct `xcodegen
generate` in a worktree can leak the worktree path.
