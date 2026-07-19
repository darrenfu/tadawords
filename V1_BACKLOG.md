# Tada Words V1 backlog

This backlog tracks release acceptance and external configuration. Physical-device feedback and all subsequent iterations are versioned in `FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md`; the active source batch is `v0.7.0`. Use `MVP_ACCEPTANCE.md` for the executable checklist.

## Release blockers

### DEVICE-01: Sign and install on physical devices

**Status:** Earlier LocalQA installs exist; the exact-HEAD v0.7.0 signed iPhone/iPad regression and production Family Sync acceptance are required

- Select an Apple development Team in Xcode
- Confirm a valid signing identity
- Enable Developer Mode on the test iPhone and iPad
- Install the canonical `TadaWords.xcodeproj` build
- Complete one Read and one Write quest on each device

### DEVICE-02: Re-test physical-device follow-ups

**Status:** Automated implementation pass complete; fresh physical-device regression required

- Single-tap `Parents` and Results Replay
- Profile-first clean/returning launch
- Read silence before first response and Hear/See only after two valid errors
- Silence/noise/short-word speech behavior and child voiceprint samples
- Relaxed star recovery, calibration, and slow-side cases
- Parent Word Manager typing, Camera OCR, Photo OCR, newest-first, delete/Undo, and no automatic words
- Write final consonants and the continuous `tā-'dá, wòrds!` / `它达，沃尔子` launch phrase: `tah-DAH`, 105ms pause, lower `words`
- Moonpetal rainbow/unicorn visuals and upbeat score
- Double-Quest next-day Theme/Icon unlock and My Collection persistence
- Rotate all Parents routes in portrait/landscape, then confirm every child route restores landscape; simulator policy passes, but physical iPhone/iPad checks remain
- Tap the upper-right `Badge` on phone and tablet; simulator layout evidence passes, but physical navigation confirmation remains

### CLOUD-01: Add consent and erasure, then validate CloudKit

**Status:** v0.7.0 source implementation complete; production schema, destructive test-only erasure, and physical-device acceptance remain privacy release blockers

- [x] Add a persisted, default-off Family Sync choice
- [x] Block launch, onboarding-completion, lifecycle, manual, and invitation synchronization until the guardian opts in
- [x] Let the guardian disable future sync without blocking local quests
- [x] Keep LocalQA visibly device-only with a separate bundle ID and no iCloud entitlement
- [x] Implement ledger-before-purge deletion, owner remote erasure, participant leave/revocation, restart retry, and unconditional stale-device non-resurrection
- Create or attach `iCloud.com.tadawords.app` under the selected Team
- Deploy the CloudKit development schema
- Validate private-database sync on two devices using one Apple ID
- Validate a CloudKit share between two Apple IDs
- [x] Add production-only Apple `CKShare` access-management UI routed to the persisted private-owner or shared-participant root/share
- Validate owner removal, participant leave, and revocation on signed iPhone/iPad builds
- [x] Cover offline edits, conflict resolution, retry, corrupt data, account changes, invitation routing, deletion dominance, crash replay, and two-device arrival permutations with deterministic source harnesses
- [x] Confirm child Quest commits never wait for CloudKit

Voiceprint templates remain device-scoped and do not sync through CloudKit.

Simulator and LocalQA builds intentionally use a local/device-only sync transport. The real CloudKit transport runs only in a normal signed physical-device build with the configured Team, container, iCloud account, and explicit guardian opt-in.

### VOICE-01: Calibrate child voiceprints

**Status:** Device Alpha code complete; representative accuracy evidence open

- Enroll the target child on each test device
- Collect same-child and different-speaker trials across multiple rooms and distances
- Measure false accept, false reject, and uncertain rates
- Tune thresholds only from representative child samples
- Confirm no raw enrollment or quest recording persists or uploads

The current on-device acoustic signature and conservative uncertain band improve routing. They do not prove that the microphone recorded only the selected child.

### AUDIO-01: Approve voice and music on device

**Status:** Code complete; listening approval open

- Complete two Read and two Write quests in every World
- Approve the young, energetic female voice on supported device voices
- Check pronunciation, loudness, fatigue, clipping, ducking, interruptions, and headphone changes
- Verify Reduced Sound and Calm Rescue preserve essential feedback

The shipping soundscape synthesizes original procedural music and cues. It does not bundle the downloaded child-speech test fixture or copied Todo Math assets.

### INPUT-01: Validate handwriting and Pencil behavior

**Status:** Code complete; child and device acceptance open

- Test four-year-old handwriting on iPhone and iPad
- Compare finger and Apple Pencil samples on iPad
- Place a palm on the screen while writing and check accidental-touch filtering
- Verify Left-handed writing keeps the primary controls reachable
- Calibrate recognition from real samples before changing thresholds

### ACCESS-01: Complete the physical accessibility pass

**Status:** Code complete; device acceptance open

- Walk through every child and Guardian route with VoiceOver
- Verify transient feedback and result summaries announce once
- Test larger Dynamic Type in compact landscape height
- Verify Reduce Motion removes repeating travel while preserving visible state changes
- Check Camera and Photo Library permission copy for both avatars and word-sheet OCR

### PRODUCT-01: Run the real-child usability session

**Status:** Human acceptance required

- Confirm a pre-reader can distinguish Read and Write without help
- Confirm the child can switch Profile, World, Calendar, and Badge/Collection
- Observe whether rewards remain motivating after several sessions
- Check that Rescue feedback helps without creating pressure

## Final repository cleanup

### REPO-01: Remove stale generated Xcode artifacts

**Status:** V1 baseline cleanup completed; canonical LocalQA files retained; the current v0.7.0 batch passes 814 Swift and 14 Issue Agent tests, and the exact committed-HEAD simulator reruns plus final artifact scan must be recorded at merge time

Keep:

- `TadaWords.xcodeproj`
- `Apps/TadaWordsApp/Info.plist`
- `Apps/TadaWordsApp/InfoLocalQA.plist`
- `Apps/TadaWordsApp/TadaWordsLocalQA.entitlements`
- `TadaWords.xcodeproj/xcshareddata/xcschemes/TadaWordsLocalQA.xcscheme`
- `project.yml`

Removed stale artifacts:

- `TadaWords 2.xcodeproj`
- `TadaWords 3.xcodeproj`
- `TadaWords 4.xcodeproj`
- `TadaWords 5.xcodeproj`
- `Apps/TadaWordsApp/Info 2.plist`

The numbered projects were generated snapshots, not source inputs. A repository scan now finds only the canonical `TadaWords.xcodeproj`; removing the duplicates prevents opening an obsolete target or shipping stale privacy and orientation settings.

## Completed V1 scope

- Two independent Today Quest routes, guided retry rules, timing isolation, Ebbinghaus review, and true mastery
- Profile-first onboarding with versioned consent, Profile setup, no starter-word form, and deferred system permissions
- Parent-only words via typing or local Camera/Photo OCR, normalization, newest-first queues, de-duplication, and delete/Undo
- Multiple Profiles, child nickname creation, last-profile highlight, photo/animal/earned icons, grade, age, and world settings
- Eight separate original worlds, 20 small rewards and five milestones each,
  distinct locked/earned treasure icons, treasure avatars, world unlocks,
  Collection, and monthly Calendar
- Guardian Today, Needs Attention, 7-day and 30-day reports, corrections, and CSV export
- Crash-resumable profile deletion, local notifications, sensitive-action authentication, and device-local voice setup
- Versioned private/shared CKSyncEngine transport, durable outbox/inbox/apply, full Profile/settings/pool/photo/event coverage, derived progress/rewards, default-off guardian opt-in, family invitations, and source-side remote erasure/non-resurrection; production schema and physical acceptance remain open
- Light-mode V1 visual system, compact landscape layouts, 44-point targets, VoiceOver announcements, Reduce Motion, and left-handed writing controls
