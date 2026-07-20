# App Store release-candidate preflight

The canonical preflight verifies an already-created archive and export. It does
not build, sign, install, launch, upload, submit, merge, or release anything.

## Inputs

- a clean dedicated release worktree at the exact candidate HEAD;
- an existing signed `.xcarchive` produced from that HEAD;
- the existing exported signed `.app` or `.ipa` produced from that archive;
- PawGoo Apple Developer Team `7R78Q4HP86`.

Keep the archive and export outside tracked source. The default manifest path,
`.build/release-candidate-manifest.json`, is ignored by Git.

```sh
make release-preflight \
  ARCHIVE='/absolute/path/TadaWords.xcarchive' \
  EXPORTED_APP='/absolute/path/TadaWords.ipa' \
  TEAM_ID='7R78Q4HP86'
```

The normal Development artifact has a separate, read-only verifier. It does
not install or launch the app:

```sh
./Scripts/verify-pawgoo-development-app.py \
  '/absolute/path/Tada Words.app' \
  'EXPECTED_VERSION' \
  'EXPECTED_BUILD' \
  'EXACT_40_CHARACTER_COMMIT' \
  --device-udid 'APPROVED_IPHONE_HARDWARE_UDID' \
  --device-udid 'APPROVED_IPAD_HARDWARE_UDID'
```

That verifier rejects policy overrides, non-PawGoo identities, a CMS not
signed by the pinned Apple provisioning signer, a code-signing leaf not listed
in the embedded profile, expired or unexpected device coverage, and app
entitlements not authorized by the profile. The sealed app is held to a
least-privilege entitlement contract even though the Apple profile contains a
broader authorization envelope. It snapshots the `.app`, rejects mutation
during verification, checks an iPhoneOS-only arm64 executable, and prints the
verified tree SHA-256 for the serialized handoff to the install lane.

`TadaWordsGitCommit` is signed metadata, not cryptographic proof of source
provenance by itself. Exact-source evidence additionally requires the clean,
exact-HEAD build log that produced the app. The handoff consumer must recheck
the printed tree SHA-256 before any separately authorized installation.

The command fails closed when it finds dirty source, stale generated project
files, version/build/bundle/team/commit drift, an invalid signature, a missing
privacy manifest, missing icons or runtime resources, or entitlements outside
`Config/release-candidate-policy.json`.

The source entitlement plist and Xcode build settings declare intent; they are
not Production signing evidence. The preflight extracts the signed
entitlements independently from the exact archived app and the exact exported
app. An archive may still carry `aps-environment=development`, a Development
CloudKit environment, and a debug allowance because it is an intermediate
artifact. The archive is never sufficient App Store or TestFlight evidence by
itself. The exported app or IPA must carry `aps-environment=production`, the
Production CloudKit environment, and no enabled debug entitlement.

On success it atomically emits a JSON manifest containing the commit, version,
build, bundle ID, Team ID, archive metadata, signed entitlements, and SHA-256
hashes for both app bundles and their critical artifacts. The manifest records
simulator evidence, physical installation, launch smoke, automated device
tests, human acceptance, and TestFlight upload as separate gates. It never
converts one gate's result into evidence for another.

The manifest keeps the two authorities separate:

- `archive.app.entitlements` and the archive app hashes describe only the
  intermediate archived artifact;
- `export.app.entitlements` and the exported app hashes are the canonical
  Production entitlement evidence.

LocalQA builds, simulator output, portal screenshots, source plist values, and
archive-only inspection cannot replace the exported-app evidence.

## Required order

1. Run source tests and simulator gates separately.
2. Create the archive with `TADA_GIT_COMMIT` set to the full candidate HEAD.
3. Export the archive without changing the release worktree.
4. Run this preflight against both artifacts and confirm that the exported
   app's signed `aps-environment` is exactly `production`.
5. Review and retain the JSON manifest with the release evidence.
6. Perform physical install, inventory, launch, device tests, and human
   acceptance only through their separately authorized workflows.
7. Upload to TestFlight only after an explicit human action outside this tool.

Any new commit invalidates the archive, export, manifest, device evidence, and
human approval. Recreate them from the new HEAD.
