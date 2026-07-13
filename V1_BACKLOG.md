# Tada Words V1 backlog

This backlog now tracks release acceptance and external configuration. The confirmed V1 product flows are implemented in source. Use `MVP_ACCEPTANCE.md` for the executable checklist.

## Release blockers

### DEVICE-01: Sign and install on physical devices

**Status:** External setup required

- Select an Apple development Team in Xcode
- Confirm a valid signing identity
- Enable Developer Mode on the test iPhone and iPad
- Install the canonical `TadaWords.xcodeproj` build
- Complete one Read and one Write quest on each device

### CLOUD-01: Configure and validate CloudKit

**Status:** Code complete; Apple environment acceptance open

- Create or attach `iCloud.com.tadawords.app` under the selected Team
- Deploy the CloudKit development schema
- Validate private-database sync on two devices using one Apple ID
- Validate a CloudKit share between two Apple IDs
- Test offline edits, conflict resolution, retry, invitation acceptance, and profile tombstones
- Confirm quests never wait for CloudKit

Voiceprint templates remain device-scoped and do not sync through CloudKit.

Simulator builds intentionally use a local/device-only sync transport. The real CloudKit transport runs only in a signed physical-device build with the configured Team, container, and iCloud account.

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
- Check Camera and Photo Library permission copy

### PRODUCT-01: Run the real-child usability session

**Status:** Human acceptance required

- Confirm a pre-reader can distinguish Read and Write without help
- Confirm the child can switch Profile, World, Calendar, and Collection
- Observe whether rewards remain motivating after several sessions
- Check that Rescue feedback helps without creating pressure

## Final repository cleanup

### REPO-01: Remove stale generated Xcode artifacts

**Status:** Completed 2026-07-12 after the canonical 367-test check and both Release simulator builds passed

Keep:

- `TadaWords.xcodeproj`
- `Apps/TadaWordsApp/Info.plist`
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
- First-run parent onboarding with versioned consent, Profile setup, optional starter words, and deferred system permissions
- Manual words, smart fill, Grade automatic recommendations, normalization, and de-duplication
- Multiple Profiles, child nickname creation, last-profile restore, photo and animal avatars, grade, age, and world settings
- Three separate worlds, 20 small rewards and five milestones each, world unlocks, Collection, and monthly Calendar
- Guardian Today, Needs Attention, 7-day and 30-day reports, corrections, and CSV export
- Crash-resumable profile deletion, local notifications, sensitive-action authentication, and device-local voice setup
- Optional local-first CloudKit synchronization and family invitations
- Light-mode V1 visual system, compact landscape layouts, 44-point targets, VoiceOver announcements, Reduce Motion, and left-handed writing controls
