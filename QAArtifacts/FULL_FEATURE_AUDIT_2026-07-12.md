# Tada Words full feature audit follow-up

This follow-up replaces the stale gap list from the initial 2026-07-12 audit.
Confirmed learning behaviors have production paths. CloudKit has a persisted,
default-off guardian consent gate; remote record erasure is still a release
blocker. Other blockers require Apple service configuration, physical devices,
representative child samples, or human listening.

> **v0.2 supersession:** The 367-test result is retained below only as the
> accepted V1 historical baseline. The active `v0.2` branch has since completed
> a branch-wide **480/480** Swift test run and LocalQA simulator builds for iPhone
> 17 Pro Max and iPad Pro 13-inch (M5). Physical-device rotation, child input,
> accessibility, and audible prosody remain open. The authoritative change
> history is `FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md`.

## Verdict

Tada Words is a local-first V1 candidate for iPhone and iPad. It implements separate Read and Write quests, adaptive review, Profiles, Worlds, rewards, reports, notifications, device-local voice setup, and a CloudKit sync transport.

Do not label the release Device Alpha accepted yet. Persisted, default-off CloudKit consent is implemented, but remote record erasure remains a release blocker. CloudKit runtime behavior, voiceprint accuracy, handwriting, Pencil, VoiceOver, route rotation, Camera, notifications, and audio quality still need physical-device evidence.

## Evidence states

- **Code complete**: production composition and automated coverage exist
- **Runtime fixture checked**: an Apple runtime processed a checked-in real child-speech file
- **Device Alpha acceptance open**: representative child or physical-device evidence is missing
- **External setup required**: Apple signing, iCloud container, accounts, or permissions are missing

## Consolidated quality gate

The current v0.2 consolidated run used:

```sh
make generate
make check
./Scripts/verify-device-readiness.sh
```

| Gate | Result |
|---|---|
| Strict Swift formatter check | Pass |
| Swift unit and integration suite | 480 tests passed, 0 failures |
| iPhone 17 Pro Max LocalQA simulator build | Pass |
| iPad Pro 13-inch (M5) LocalQA simulator build | Pass |
| Built-product orientation declarations | iPhone contains Portrait plus both Landscapes; iPad contains all four; `UIRequiresFullScreen` is true and runtime policy restricts child routes to Landscape |
| Route-orientation policy tests | Pass; Parents is flexible and child routes restore Landscape |
| iPad simulator visual evidence | Historical captures showed a tall/portrait Parent launch and landscape child Read route. The temporary image files were removed in the v0.7.29 repository cleanup. |
| iPhone child visual evidence | Historical readable landscape captures showed the last-played Profile emphasis, compact Lobby utility dock, enlarged Read hierarchy, and enlarged Result hierarchy. The temporary image files were removed in the v0.7.29 repository cleanup. |
| iPhone simulator orientation capture | Inconclusive because raw framebuffer captures can appear rotated or letterboxed; physical rotation remains required |
| Built-product CloudKit sharing declaration | `CKSharingSupported` is true |
| Child-speech fixture integrity and Apple transcription | Pass; checksum valid and output is `Bye.` |

The original audit's 292-test count and the accepted V1 baseline's 367-test
count are both superseded for `v0.2` by the 480-test run. The older counts remain
in historical cleanup notes only.

## Requirements traceability

### Content, Profiles, and daily planning

| Requirement | Status | Current implementation |
|---|---|---|
| Separate Read and Write pools and Today Quest buttons | Code complete | Mode-keyed pools, plans, settings, attempts, and lobby entrances |
| Guardian supplies every word | v0.2 code complete; device acceptance open | One-word Return-to-add plus local Camera/Photo OCR review, newest-first queue, dedupe, single/bulk delete, and Undo |
| Normalize and de-duplicate | Code complete | Stable normalized identity with case-preserving display text |
| Parent words have priority | Code complete | Today entries queue first; older pool entries fill shortages |
| Automatic recommendation | Removed in v0.2 | V1 never inserts Grade/catalog/smart-fill words; undersized Pools remain undersized |
| Daily plan survives restart | Code complete | Profile, mode, and local-day keyed snapshots |
| New-first or Review-first | Code complete | Stored independently for Read and Write |
| Problem New replacement | Code complete | New-first can replace the lowest Review while preserving review debt |
| Multiple Profiles and last-profile confirmation | v0.2 code complete | Cold launch highlights the last valid Profile in the Picker; the child still taps to enter, and stale IDs are cleared |
| Child nickname-only Profile creation | Code complete | Kid-facing New Kid route assigns safe defaults |
| Avatar, Grade, age, and starter World | Code complete | Camera, Photo Library, animals, editable school level, and age |
| First-run Guardian onboarding | v0.2 code complete; device layout follow-up open | Versioned consent and timestamp, Profile, Grade, starter World, no word-entry interruption, and deferred system permissions |

### Review, evidence, and mastery

| Requirement | Status | Current implementation |
|---|---|---|
| Ebbinghaus recall model | Code complete | `R(t) = exp(-t / stability)` with due-state priority |
| Errors, Help, replay, and relative pace affect review | Code complete | Evidence updates stability, difficulty, and weak-word ranking |
| Review includes weak not-yet-due words | Code complete | Supplemental weak candidates fill available review capacity |
| Re-entered learned word moves forward | Code complete | Guardian requeue time raises review priority |
| Technical outcomes do not update learning | Code complete | Typed technical and uncertain states remain outside independent evidence |
| True mastery | Code complete | Three independent successes on distinct local days plus future 14-day recall threshold |
| Timing excludes non-child work | Code complete | Per-attempt clocks exclude playback, Help, recognition, technical, and uncertain leakage |

### Read quest

| Requirement | Status | Current implementation |
|---|---|---|
| Visible word and tap-to-record | Code complete; device acceptance open | Apple on-device speech path and child UI |
| First attempt plus two valid retries | Code complete | Technical or uncertain outcomes do not consume valid attempts |
| Three technical failures offer Move On | Code complete | Result remains Not scored |
| Final wrong result plays the standard answer | Code complete | Answer audio follows the last valid incorrect outcome |
| Automatic endpointing and voice processing | Code complete; device acceptance open | Voice-processing audio session and partial-transcript stability |
| Apple transcript punctuation | Fixed and fixture checked | Target `bye` accepts Apple output `Bye.` without weakening exact spelling |
| Per-Profile voiceprint match | Device Alpha code complete | Enrollment, Keychain template, on-device feature extraction, conservative match policy, and speech integration |
| Theme-safe word color | v0.2 code complete; visual acceptance open | Stable per-item selection from each World's high-contrast palette; retries and Help do not flicker or encode correctness. Historical readable iPhone evidence was reviewed before the temporary image cleanup. |

The voiceprint route treats mismatch as a technical retry. It does not prove that only the child was recorded. Validate same-child, different-speaker, noise, distance, and device variation before tuning its thresholds.

### Write quest

| Requirement | Status | Current implementation |
|---|---|---|
| Hear-only independent handwriting | Code complete; device acceptance open | Word audio, guides, slots, explicit Done, and Vision recognition |
| New word demonstration | Code complete | Shows spelling, plays it, hides it, then starts independent work |
| Help cannot establish mastery | Code complete | Guided evidence stays distinct from independent success |
| Incorrect or uncertain guided rewrite | Code complete | Shows the answer and allows one rewrite |
| Technical retry stays neutral | Code complete | It does not consume the guided rewrite or accuracy |
| Apple Pencil and palm filtering | Code complete; device acceptance open | Input-method classification, pressure capture, and major-radius filtering |
| Left-handed controls | Code complete; device acceptance open | Write action rails swap according to Profile settings |
| Four pens, 12 colors, and local eraser | v0.2 code complete; device acceptance open | Pencil, Crayon, Chalk, and Brush preserve per-stroke style/color; gentle throttled sounds; Undo replaced by a 2.5× local eraser; Clear is immediate |

### Score, timer, Worlds, and rewards

| Requirement | Status | Current implementation |
|---|---|---|
| 0 to 100 score and three stars | Code complete | Accuracy threshold plus personal pace gates stars |
| Child-relative pace | Code complete | Baselines separate Profile, mode, device, input, and word length |
| Whole-Quest upward timer | Code complete | Pauses for background, playback, Help, and recognition |
| Configurable Rescue threshold | Code complete | Crossing it changes presentation and audio without failure or score loss |
| Calm Rescue and Reduced Sound | Code complete | Essential feedback remains; optional decoration and Rescue layer can stop |
| Eight separate original Worlds | v0.2 code complete | Independent scenes, pose-aware mascots, palettes, ambient motion, and procedural scores; new Dinosaur, Rescue, Block, Frost, and Coaster themes do not reuse protected IP |
| Theme-safe rewards | Code complete | Reward keys and Collection stay inside the selected World |
| 20 small plus five milestone rewards per World | v0.2 code complete | 200 stable catalog items; every World uses 25 distinct relevant icons; locked cards retain gray artwork plus a lock |
| Double Quest next-day unlock | v0.2 code complete | Same-day Read+Write Today completion unlocks one unearned World and animal icon only on a later local day; replay/partial days do not count |
| Collected treasure avatar | v0.2 code complete | Only collected treasure can be selected; original photo and Profile isolation remain intact |
| Practice Again does not duplicate rewards | Code complete | It records completion without granting the same daily collectible again |

### Guardian, calendar, reports, and deletion

| Requirement | Status | Current implementation |
|---|---|---|
| Exact monthly quest Calendar | Code complete | Profile-isolated local-day completion counts, including Practice Again |
| Guardian Today summary | Code complete | Completion, score, stars, pool, due, attention, Calendar, and sync state |
| Needs Attention uses child-relative pace | Code complete | Weak, due, incorrect, slow, replayed, and helped signals |
| 7-day and 30-day reports | Code complete | Summary, trend comparison, and per-word detail |
| Guardian correction | Code complete | Correction events rebuild current learning progress |
| CSV export | Code complete | Sensitive-action authorization precedes ShareLink access |
| Delete Profile | Code complete | Crash-resumable tombstone clears repositories; app also clears reminders, last session, and device voiceprint |
| Parent gate and sensitive actions | v0.2 code complete; device acceptance open | Normal single tap opens the math challenge; LocalAuthentication protects delete, export, and family sync |

### Data, sync, notifications, and privacy

| Requirement | Status | Current implementation |
|---|---|---|
| Offline local persistence | Code complete | Atomic JSON snapshots under Application Support |
| CloudKit multi-device sync | Persisted opt-in and transport code complete; external setup remains | Private/shared databases, profile zones, conflict resolution, retry status, and local-first coordinator run only after explicit parent opt-in |
| Family invitation across Apple IDs | Code complete; external setup required | CKShare URL creation, ShareLink, paste-to-accept flow, and shared database reads |
| Profile deletion propagation | Partial; privacy release blocker | A syncable tombstone prevents resurrection, but the transport does not erase existing CloudKit records |
| Local notifications | Code complete; device acceptance open | Daily, Pool low, completion, sync failure, weekly summary, editable times, and quiet hours |
| No raw child recordings persisted or uploaded | Code complete; dynamic audit open | Speech and enrollment buffers stay in memory; voiceprint template stays in this-device-only Keychain |
| No app-owned server database | Code complete | Core data stays local; a configured signed build can copy records to CloudKit only after persisted guardian opt-in; missing remote erasure still blocks family-data release |

### Accessibility and presentation

| Requirement | Status | Current implementation |
|---|---|---|
| Route-based iPhone and iPad orientation | v0.2 automated pass; device acceptance open | Code, plist, and policy tests pass. iPad simulator window shapes support the expected Parent/child split; iPhone raw framebuffer evidence is inconclusive. Child routes use Left/Right Landscape; Parents uses all-but-upside-down on iPhone and all orientations on iPad, then restores Landscape on exit |
| iPhone 17 Pro Max support | Release simulator passed; physical-device acceptance open | Release build, install, launch, and onboarding capture passed; signed physical-device checks remain |
| Lobby `Badge` relocation | v0.2 automated pass; device tap open | Historical readable iPhone landscape evidence showed that the four-item header fits and the old bottom Collection strip is absent; tap-through still needs physical phone/tablet confirmation |
| Light appearance | Code complete | App-root policy covers bootstrap, child, and Guardian routes |
| 44-point targets and compact layouts | Code complete | Shared tokens, scroll fallbacks, and compact landscape variants |
| VoiceOver feedback and focus | Code complete; device acceptance open | Transient announcements, result summary, and modal saving focus |
| Reduce Motion | Code complete; device acceptance open | Ambient, feedback, reward, and route transitions adapt |
| Young energetic female English voice | Code complete; listening acceptance open | Prefers the installed youthful US-English persona (Sandy on this Mac), then deterministic natural female fallbacks. Launch uses one continuous `tah-DAH` SSML phrase, a 105ms pause, and a lower landing on `words`; target is `tā-'dá, wòrds!` / `它达，沃尔子`, pending human device listening |

## Real child-speech fixture

The repository includes OpenSLR SLR101 utterance `000010168`, a Mandarin-native child saying `BYE`, with its Creative Commons Attribution 4.0 source note and checksum.

The Apple file transcription returns `Bye.`. The current speech decision policy removes boundary punctuation only for speech matching and accepts it for target `bye`. Exact spelling remains strict.

This fixture does not test microphone permission, voice processing, household noise, speaker routes, automatic endpointing, or a Profile voiceprint.

## External and physical acceptance list

- Configure signing, Developer Mode, and the CloudKit container
- Build, install, cold-launch, and rotate a physical iPhone 17 Pro Max and iPad
- Validate child speech, endpointing, noise suppression, echo cancellation, and route recovery
- Measure voiceprint same-child and different-speaker performance
- Validate four-year-old handwriting, Apple Pencil, palm contact, and left-handed use
- Test Camera and Photo Library permissions
- Walk the full app with VoiceOver, Reduce Motion, and large Dynamic Type
- Approve female voice, pronunciation, music, loudness, ducking, fatigue, and interruptions
- Validate local notification permission, quiet hours, delivery, and cancellation
- Validate CloudKit same-account sync, two-Apple-ID sharing, offline conflict, retry, and deletion propagation
- Run a short real-child usability session for navigation and reward appeal

## Repository cleanup completed

The repository now keeps only the canonical `TadaWords.xcodeproj`, `Apps/TadaWordsApp/Info.plist`, and `project.yml`.

At the accepted V1 baseline, after the canonical 367-test check and both Release
simulator builds passed, these stale artifacts were removed. That historical
coverage is superseded by the current 480-test v0.2 run:

- `TadaWords 2.xcodeproj`
- `TadaWords 3.xcodeproj`
- `TadaWords 4.xcodeproj`
- `TadaWords 5.xcodeproj`
- `Apps/TadaWordsApp/Info 2.plist`

The numbered projects were not source inputs. A repository scan now finds only the canonical Xcode project, preventing accidental stale builds.
