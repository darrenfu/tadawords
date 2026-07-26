# Device delivery

[Back to module index](README.md)

Physical installation is pre-authorized only for the isolated LocalQA app and
must not remove existing data. Authentication, trust, Developer Mode, signing,
provisioning, or device-availability blockers require a stop and human handoff.

Physical Xcode build, install, launch, and device-test work is a single global
lane even when code batches coexist. Before using that lane, check for another
active Xcode/device deployment and stop on ambiguity. Recheck on-device
version/build after every install or test; unexpected replacement invalidates
the device evidence instead of being overwritten or ignored.

Build the physical app from the PR's current HEAD with `TADA_GIT_COMMIT` set to
the full HEAD SHA. Before installation, run
`Scripts/verify-signed-app-identity.sh`. Record the device model, OS, identifier,
version, build, commit, install result, smoke result, automated result, and
remaining manual checklist separately for iPhone and iPad.
