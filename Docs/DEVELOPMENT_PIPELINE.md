# Tada Words development and delivery pipeline

This document expands the mandatory rules in [`../AGENTS.md`](../AGENTS.md).
Its goal is to shorten feedback loops without weakening release-candidate
evidence, child-data safety, signing identity, or guarded merge.

## Outcomes

The pipeline optimizes for:

1. validated learning and product feedback per unit of time;
2. one writer and one authoritative HEAD per PR;
3. focused development checks before expensive verification;
4. one immutable release artifact tested across the required environments;
5. evidence reuse instead of repeated status-driven work;
6. bounded sessions and predictable token consumption.

## Pipeline

```text
Issue and acceptance criteria
  -> risk tier and one PR writer
  -> focused implementation checks
  -> scope freeze
  -> PR gate
  -> guarded merge
  -> scheduled/nightly integration
  -> immutable R4 candidate
  -> one archive/export
  -> required device acceptance
  -> Internal TestFlight/App Store
```

PR verification and release verification are different products. A feature PR
proves that its changed behavior is safe to integrate. An R4 candidate proves
that one exact artifact is safe to distribute.

## Risk classification

Classify by behavior, not file count or label. Mixed changes use the highest
applicable tier.

### R0: documentation and internal automation

Use R0 only when the app package, runtime, persistent data, signing, resources,
and generated project are unaffected.

Evidence:

- Markdown/configuration validation relevant to the diff;
- changed-path automation tests;
- no simulator, signing, archive, or physical device.

R0 PRs do not change app marketing/build versions.

### R1: pure logic

Examples include deterministic algorithms, domain policies, parsers, and state
machines with no platform API or packaged-resource behavior.

Evidence:

- focused regression tests while developing;
- affected unit/integration targets for the PR;
- one representative simulator build only when application linkage changes;
- no physical device.

### R2: app presentation

Examples include ordinary SwiftUI, responsive layout, animations, synthesized
feedback sounds, and copy.

Evidence:

- focused model/view-policy tests;
- relevant iPhone and iPad simulator build/UI coverage;
- accessibility settings appropriate to the change;
- at most one representative physical experience check after scope freeze when
  visual timing, speaker output, haptics, or touch feel requires human judgment.

An R2 experience check does not require rebuilding or installing on both device
classes. Simulator evidence covers form factor; one representative device
covers sensory judgment.

### R3: platform and stateful behavior

Examples include Camera, Photos, Speech, Microphone, Apple Pencil, permissions,
push/App Attest, signing-adjacent code, and persistent migrations.

Evidence:

- affected unit/integration and simulator gates;
- only the physical device classes that exercise the real capability;
- data-preserving install/upgrade where persistence changes;
- explicit rollback or compatibility evidence for migrations.

Camera-only work normally uses the approved iPhone. Pencil-only work normally
uses the approved iPad. Two devices are required only when the behavior is
cross-device.

### R4: immutable release candidate

Use R4 for Family Sync acceptance and any artifact intended for Internal
TestFlight, App Store submission, or final release audit.

Evidence:

- `make check-rc`;
- required iPhone and iPad simulator matrix;
- archive/export bound to the full HEAD;
- signed identity and entitlement verification;
- one approved iPhone plus one approved iPad;
- human product checks;
- explicit TestFlight/App Store state.

## Scope freeze

Do not pay the R2-R4 verification cost while behavior is still changing.

A scope-freeze record contains:

```text
Issue / PR
declared tier
full HEAD
included acceptance criteria
explicit exclusions
manual experience checks
artifact target, if R4
```

New product requirements after freeze return the PR to development. Do not
immediately rerun full gates after each edit. Produce the next frozen candidate,
then validate once.

No new Issue may be attached to a PR after its first R4 artifact. A follow-up
gets a new PR unless the owner explicitly abandons the candidate.

## One-writer and shared-resource leases

Use `Scripts/delivery-lease.py`. Its default store is under
`~/Library/Application Support/TadaWordsDelivery/leases`.

Acquire a PR writer:

```sh
python3 Scripts/delivery-lease.py acquire \
  --kind pr-writer \
  --resource PR-141 \
  --owner SESSION_ID \
  --issue 141 \
  --pr 142 \
  --branch agent/risk-tiered-delivery-pipeline \
  --head "$(git rev-parse HEAD)" \
  --ttl-seconds 14400
```

Acquire a heavy Xcode lane:

```sh
python3 Scripts/delivery-lease.py acquire \
  --kind heavy-xcode \
  --resource local \
  --owner SESSION_ID \
  --issue 141 \
  --branch "$(git branch --show-current)" \
  --head "$(git rev-parse HEAD)" \
  --ttl-seconds 7200
```

Inspect or release:

```sh
python3 Scripts/delivery-lease.py status --kind heavy-xcode --resource local
python3 Scripts/delivery-lease.py release \
  --kind heavy-xcode --resource local --owner SESSION_ID
```

Allowed kinds are `pr-writer`, `heavy-xcode`, `signing-archive`, `iphone`,
`ipad`, and `testflight`. Acquisition fails closed when another unexpired owner
holds the lease. The same owner may renew it. This is a local Mac/device-lane
lock; GitHub Issue labels, branches, and PR state remain the cross-machine
ownership record.

## Check commands

During development:

```sh
make check-changed BASE_REF=origin/main TEST_FILTER=QuestAttemptStateMachineTests
```

Normal PR gate:

```sh
make check-pr BASE_REF=origin/main
```

Immutable R4 or scheduled full gate:

```sh
make check-rc
```

`check-changed` requires a focused Swift filter when Swift app paths changed.
`check-pr` runs the full Swift suite only when Swift/package paths changed.
Both run Issue Agent or release-preflight tests only when their owned paths
changed. `check-rc` always runs the complete suite.

The legacy `make check` alias maps to `check-pr`, not `check-rc`.

## Evidence reuse

Evidence must be addressable by:

```text
full commit SHA
risk tier
command/check identifier
toolchain/environment
artifact identity when applicable
result and artifact path
```

Store generated evidence outside tracked source, such as
`.build/delivery-evidence/<sha>/`. When HEAD and environment are unchanged,
status checks read this evidence. They do not rerun tests or reconstruct
screenshots.

A new commit invalidates evidence for the previous HEAD. It does not promote an
R1/R2 PR into R4 or require unrelated Issue Agent/release-preflight/device
gates. Only the gates applicable to the current tier are regenerated.

## Session lifecycle

One root session owns one Issue/PR. At the first compaction, create a checkpoint
of at most 2 KB:

```text
Issue and PR
worktree, branch, and full HEAD
writer/resource leases
changed files
completed checks and evidence paths
pending acceptance criteria
blockers and next exact command
```

End the old session and continue from the checkpoint in a fresh session.
Routine work has no subagents. Complex read-only investigation may use at most
two direct subagents in one wave; nested delegation and concurrent writers are
forbidden.

## Model policy

- Terra/medium: unattended pickup, routine implementation, docs, status, and
  proportionate tests.
- Terra/high: bounded complex bug or stateful migration implementation.
- Sol/high: architecture, security/privacy, synchronization correctness,
  signing, production identity, or final release decision.
- Ultra: exceptional, bounded final audit only; never the unattended default.

## Device and artifact policy

- The approved default group remains one iPhone and one iPad.
- The backup device group is not activated without owner approval.
- Keep device data and identity intact.
- Physical lanes are exclusive even when apps can coexist.
- Prefer one R4 archive/export. When bundle, Team, entitlements, and profile
  cover both devices, install that same artifact sequentially.
- Family Sync uses one coordinator and both devices on one exact build.
- TestFlight upload, Apple processing, group assignment, installability, and
  physical acceptance remain separate evidence states.

## PR and merge handoff

The PR template records tier and only the evidence required by that tier.
Immediately before merge, guarded merge re-fetches exact HEAD, base, body,
closing references, checks, blockers, and applicable evidence. It does not
invent absent device evidence or require R4 evidence for an R0-R3 PR.

After merge, scheduled integration may run broader checks. Promotion to R4 is a
separate decision with a frozen version/build and artifact.

## Metrics for the next ten PRs

Track:

- time from first commit to merge;
- full-suite runs per PR;
- device minutes and installs per PR;
- stale-evidence reruns;
- context compactions and tool calls;
- unique defects caught by focused, PR, nightly, and device gates.

Consider additional Mac hardware only if, after this pipeline is adopted, the
heavy-Xcode queue still consumes more than 30% of delivery cycle time.
