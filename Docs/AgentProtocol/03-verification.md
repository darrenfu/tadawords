# Implementation and verification

[Back to module index](README.md)

For a bug, add a failing regression test first when practical. Run focused
checks during implementation, then freeze scope before expensive validation.

- `make check-changed`: focused development feedback.
- `make check-pr`: normal PR gate, selected by changed paths.
- `make check-rc`: R4, scheduled/nightly validation, or explicit final audit.

R0 runs relevant lint and changed-path automation tests, with no simulator,
signing, archive, or device gate. R1-R3 run only the source, simulator, and
affected-device gates required by their tier. R4 runs the full applicable
release-candidate matrix.

Record evidence by full commit SHA, tier, command, environment, result, and
artifact identity when applicable. A new commit invalidates old-HEAD evidence
but reruns only the new tier's gates. When HEAD and environment are unchanged,
reuse evidence; never rerun a passing gate merely to answer status.
