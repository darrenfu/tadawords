# App Store release-candidate preflight

The canonical preflight verifies an already-created archive and export. It does
not build, sign, install, launch, upload, submit, merge, or release anything.

## Inputs

- a clean dedicated release worktree at the exact candidate HEAD;
- an existing signed `.xcarchive` produced from that HEAD;
- the existing exported signed `.app` or `.ipa` produced from that archive;
- the expected Apple Developer Team ID.

Keep the archive and export outside tracked source. The default manifest path,
`.build/release-candidate-manifest.json`, is ignored by Git.

```sh
make release-preflight \
  ARCHIVE='/absolute/path/TadaWords.xcarchive' \
  EXPORTED_APP='/absolute/path/TadaWords.ipa' \
  TEAM_ID='EXPECTED_TEAM_ID'
```

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
