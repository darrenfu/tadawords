# Versioning and project generation

[Back to module index](README.md)

Every PR increments `vMAJOR.MINOR.PATCH`, including documentation and internal
automation PRs. Use PATCH for compatible fixes, docs, and small polish; MINOR
for a coherent backward-compatible capability; and require human approval for
breaking version strategy. The build number is independently monotonic.

Before creating a worktree, inspect the default branch, source Plists,
`project.yml`, generated Xcode settings, remote branches, open PRs, release
labels, tags, and active batch reservations. Atomically reserve an unused
version by pushing the newly created batch branch. If that push loses a race,
remove the local worktree, recompute, and try a new version. Never reuse a
version already present in any active reservation.

Synchronize the version and build across:

- `Apps/TadaWordsApp/Info.plist`
- `Apps/TadaWordsApp/InfoLocalQA.plist`
- `project.yml`
- the generated Xcode project
- release notes or status documentation that names the build

Regenerate the project only with `make generate` or
`Scripts/generate-xcode-project.sh`. Direct `xcodegen generate` in a release
worktree leaks the worktree directory name into the project file.
