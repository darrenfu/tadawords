# Device Deployment

Tada Words has three deliberately separate delivery milestones. A successful Simulator build is useful evidence, but it is not a physical-device release.

## 1. Developer Preview

**When:** the current Read/Write vertical slice builds and launches on both target Simulators.

**Form:** Xcode installs a development-signed `.app` directly onto one connected iPhone or iPad. The device does not receive a standalone download link, and this build is intended only for local testing. Use the **TadaWordsLocalQA** scheme: it installs as **Tada Words QA**, uses bundle ID `com.tadawords.app.localqa`, and cannot contact iCloud Family Sync.

1. Connect the device to the Mac and trust the connection.
2. Run `make generate` after any `project.yml` change.
3. Open `TadaWords.xcodeproj` in Xcode. This is the canonical project generated
   from `project.yml`; do not use numbered copies such as
   `TadaWords 2.xcodeproj` or `TadaWords 3.xcodeproj`.
4. Select the **TadaWordsLocalQA** scheme in the Xcode toolbar.
5. In **Signing & Capabilities**, choose the owner's Personal Team or paid Apple development team.
6. On the device, enable Developer Mode if iOS requests it.
7. Select the physical device as the run destination and press **Run**.

The first direct install can use Xcode-managed personal-team signing for testing on
the owner's devices. TestFlight requires an active paid Apple Developer Program team.
The generated project intentionally does not store a personal Team ID in Git. Xcode
may remember the choice locally, or a command-line build can pass
`DEVELOPMENT_TEAM=<your-team-id>` without editing the committed project.

LocalQA data is stored under its own app identity, separate from a normal Tada Words
Release install. It stays on that device: reinstalling another device does not copy it,
and it cannot be used to test cross-device sync.

Xcode may ask the owner to sign in to their Apple Account or approve a macOS/iOS security prompt. Credentials must be entered by the owner; they are never needed by the source code or stored in this repository.

## 2. Device Alpha

**When:** real speech, handwriting, retry, permission, and local-persistence flows pass on the target child profile and physical devices.

**Form:** the same direct Xcode installation, used for repeated family testing. This milestone validates microphone routes, on-device speech availability, child handwriting recognition, both child-landscape orientations, parent rotation, landscape restoration after leaving Parents, interruptions, and offline recovery.

Device Alpha is not complete merely because recognition works once. Thresholds must be calibrated against real samples, and technical/uncertain recognition results must never be counted as wrong learning evidence.

## 3. V1 Beta

**When:** the complete V1 scope, privacy boundaries, Kid-Fun Visual Pass, device QA, and release checks are complete.

**Form:** an archived Release build uploaded to App Store Connect and distributed through TestFlight. Testers install Apple's TestFlight app and accept an invitation or approved public link.

TestFlight distribution requires an active Apple Developer Program membership and App Store Connect setup. It is the preferred handoff for installing V1 on multiple devices without keeping them tethered to this Mac. Archive the normal **TadaWords** scheme in Release; do not upload the LocalQA app.

Before archiving, confirm the final 1024 x 1024 App Icon, select the paid
distribution team, and run **Product > Archive** with **Any iOS Device (arm64)**
selected. Validate the archive in Organizer before uploading it to App Store
Connect. Increment the build number before every replacement upload.

The current binary declares that it does not use non-exempt encryption. Reassess
that declaration if custom cryptography is added later.

## Privacy and capability checklist

- The current app requests microphone and speech-recognition permission only after
  an explicit action; both usage descriptions are present in `Info.plist`.
- Speech recognition is configured to require on-device recognition. Audio is not
  saved by the app.
- Handwriting recognition uses Vision on device. Camera and photo-library access are
  requested only when a parent chooses that profile-photo action; both usage
  descriptions are present.
- `PrivacyInfo.xcprivacy` declares the app-container file metadata access and
  monotonic timer APIs used by persistence and quest timing. The app declares no
  tracking or collected data in the current implementation.
- The LocalQA entitlement file is intentionally empty and its Info declares
  `CKSharingSupported=false`. The normal Release target has the CloudKit entitlement
  for `iCloud.com.tadawords.app`.
- Release Family Sync is persisted and off by default. Onboarding consent does not
  enable it; a parent must explicitly turn it on in Guardian settings. Turning it
  off stops future sync but does not yet erase records already uploaded to CloudKit.
- Profile deletion removes local data and creates a sync tombstone, but remote record
  erasure remains a release blocker.

Before external TestFlight or App Store review, the owner must also complete the
App Store privacy answers, age rating, export-compliance answers, and a public
privacy-policy URL. Those are App Store Connect records, not source-code files.

## Automated local check

`project.yml` is the source of truth for generated Xcode settings. Run the generator after changing orientations, capabilities, targets, or build settings:

```sh
make generate
```

The global Info envelope includes Portrait and both Landscape orientations on iPhone, plus Portrait Upside Down on iPad. Runtime route policy narrows every child route to both Landscape orientations. `Parents`, Parent Gate, Guardian management, and first-run parent setup use all-but-upside-down on iPhone and all orientations on iPad; leaving them requests a landscape geometry update before returning to child UI.

Run:

```sh
./Scripts/verify-device-readiness.sh
```

The script checks static Release and LocalQA configuration, verifies that no personal
Team ID is committed, builds Release for the iPhone 17 Pro Max and iPad Pro 13-inch
simulators, and builds an isolated LocalQA iPhone app. It inspects the LocalQA product
name, bundle ID, CloudKit-sharing declaration, scheme actions, and empty iCloud
entitlements. It separately reports whether a physical device and signing identity
are available; those two items require the owner's device and Apple Account.

## Current verified local environment

- Xcode 26.6
- iOS 26.5 Simulator runtime
- iPhone 17 Pro Max Simulator
- iPad Pro 13-inch Simulator

These versions describe the current development machine and are not product requirements. The app deployment target remains iOS 18.0.

## Apple references

- [Run an app on simulated or physical devices](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices)
- [Enable Developer Mode](https://developer.apple.com/documentation/Xcode/enabling-developer-mode-on-a-device)
- [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
