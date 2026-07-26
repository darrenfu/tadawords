# Device, artifact, and resource delivery

[Back to module index](README.md)

Acquire the applicable `heavy-xcode`, `signing-archive`, `iphone`, `ipad`, or
`testflight` lease with `Scripts/delivery-lease.py` before shared mutation.
Physical lanes remain exclusive. Family Sync uses one coordinator and both
device leases.

R2 may use at most one representative physical experience check. R3 uses only
the affected device classes; two devices are required only for cross-device
behavior. R4 uses one approved iPhone plus one approved iPad.

Keep device data and identity intact. Authentication, trust, Developer Mode,
signing, provisioning, or availability blockers require human handoff.

For R4, build once from the frozen HEAD with `TADA_GIT_COMMIT` set to the full
SHA. Verify Team, bundle ID, profile, version, build, entitlements, commit, and
artifact digest before installation. Prefer the same archive/export on both
approved devices. Re-read on-device identity after every install or test;
unexpected replacement invalidates the evidence.

Treat upload, Apple processing, TestFlight visibility, tester eligibility,
installation, automated checks, and human acceptance as separate states.
