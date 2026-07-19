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

On success it atomically emits a JSON manifest containing the commit, version,
build, bundle ID, Team ID, archive metadata, signed entitlements, and SHA-256
hashes for both app bundles and their critical artifacts. The manifest records
simulator evidence, physical installation, launch smoke, automated device
tests, human acceptance, and TestFlight upload as separate gates. It never
converts one gate's result into evidence for another.

## Required order

1. Run source tests and simulator gates separately.
2. Create the archive with `TADA_GIT_COMMIT` set to the full candidate HEAD.
3. Export the archive without changing the release worktree.
4. Run this preflight against both artifacts.
5. Review and retain the JSON manifest with the release evidence.
6. Perform physical install, inventory, launch, device tests, and human
   acceptance only through their separately authorized workflows.
7. Upload to TestFlight only after an explicit human action outside this tool.

Any new commit invalidates the archive, export, manifest, device evidence, and
human approval. Recreate them from the new HEAD.
