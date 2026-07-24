# App Store content-rights inventory

- Exact source baseline inspected: `16c45dee7271b6e272b52b330d013a8f74d05403`
- Content-bearing Third-Party Notices implementation: `1fd65c583583bf9ec6b01a4f5cacee3a4c286011`
- Observed app identity: `0.7.3 / 2026071903` (unchanged by this inventory)
- Audit date: 2026-07-19
- Scope: production iOS target, repository-owned App Store/QA captures, runtime family content, and test-only fixtures

This is an engineering evidence inventory, not a legal opinion. It records what
the current source and built product contain and where the available evidence
lives. Re-run `Scripts/verify-release-content-inventory.sh` against the exact
release-candidate archive after every content-bearing merge.

## Release conclusion

The source and archive boundary is mechanically verifiable, but App Store
content-rights readiness remains **blocked**:

- #32 requires the Cartesia account holder to preserve account/tier evidence
  that commercial distribution of the generated Katie and Aurora output was
  allowed on 2026-07-14.
- #33 requires an authorized Pawgoo representative to attest the authorship and
  rights chain for the original visual and editorial content.
- #74's ElevenLabs replacement remains a non-shipping candidate. The owner
  confirmed a monthly Creator subscription on 2026-07-23, but the exact voice
  and pronunciation dictionary still require listening approval, and private
  account/plan evidence must be retained for the actual generation date before
  the replacement invalidates the current Cartesia pack evidence.

Do not infer, fabricate, or commit private account evidence to resolve these
blockers. The Parent-gated, offline Third-Party Notices route from #34 is present
in this baseline and is mechanically checked below; it does not replace the
account and ownership evidence required by #32 and #33.

## Current inventory

| Content class | Concrete source and quantity | Production `.app` status | Evidence and permission basis | Attribution / status |
| --- | --- | --- | --- | --- |
| Tada Words app icon and mark | `AppIcon-1024.png`; `TadaWordsAppIcon.svg`; duplicate design source under `DesignAssets` | Asset catalogs compile the production copies into app-icon output and `Assets.car`; design sources do not ship | SHA-256: PNG `ce1782b295901de1a7cc82f6f61cfc5ffbebf9bc0745256a573058bd1281e637`; SVG `e47bfb19efa22e38db1b2a796bb47bb87993fc35b5ae4e6ba6624a9ec5e7b816` | No third-party source is recorded. Rights-chain confirmation is blocked by #33. |
| Pawgoo mark | `Apps/TadaWordsApp/Assets.xcassets/PawgooMark.imageset/pawgoo-mark.svg` | Compiled into `Assets.car` | SHA-256 `2653ed92cac054f5df24d1726a90cd8e147b7e784cd98653c26f99d08c05f6c9` | Rights-chain confirmation is blocked by #33. |
| World scenes, mascots, avatars, rewards | SwiftUI `Shape`, `Path`, gradients, colors, SF Symbols, and local catalogs under `Sources` | Ships as compiled code; there is no world raster-art pack | Repository-authored source plus Apple platform symbols | Pawgoo ownership confirmation is blocked by #33. SF Symbols are platform resources, not redistributed custom files. |
| Fonts and text | SwiftUI system font APIs | No `.ttf` or `.otf` file ships | Apple system font APIs | Re-audit if a custom font is introduced. |
| Bella teacher words | 500 manifest words with Read and Write variants: 1,000 MP3 files in `ElevenLabs-Teacher-500-v1` | Copied into the `TadaWordsApplePlatform` resource bundle | Manifest SHA-256 `8aacd3073ea2a9d99cd99b1f64eb35e330b64685a91e29782cf32a53b497ab18`; stable MP3 digest `b843da5702521e2e40b5ae6e990a079cc92c69175236ba125128d5cd405055bc`; ElevenLabs Multilingual v2; Bella voice `hpp4J3VqNfWAUOO0d1Us`; seed `20260725`; approved dictionary/version; pack `2.0.0`; full 1,000-clip inspection and 18/18 representative SpeechTranscriber matrix pass | ElevenLabs Creator subscription and Bella selection were owner-confirmed 2026-07-23. Preserve the subscription evidence with the release record. Physical-device listening remains mandatory. |
| Aurora launch and celebrations | Eight AAC-LC M4A files: launch, five positive transitions, quest complete, and the `ta-da` source | Copied into the same resource bundle | Manifest SHA-256 `4f49d4e97d0113419a78cee8b96cae252dfa9e2df230233151eae76c8bdca31b`; Cartesia Sonic 3.5; Aurora voice; pack `1.1.0`; created 2026-07-14 | Account-level proof is absent. Blocked by #32. |
| Complete voice pack | 1,000 Bella MP3 teacher clips plus eight Aurora AAC-LC M4A accents | Bundled offline | Stable relative-path/checksum digest `44b85c73a2da092e0634fb71792496b947245c76b55638d925de3855869cc6f4` | No runtime teacher-audio endpoint is configured in the production plist until the PawGoo production deployment passes. |
| ElevenLabs teacher QA artifacts | 98 MP3 files across five `QAArtifacts/TeacherAudio-ElevenLabs-*` directories plus pronunciation-alias evaluation: seeded and exploratory Bella/Jessica Read/Write clips for the nine acceptance words and listening montages | QA-only; not copied into the app target | Candidate manifests record exact provider/model/voice/seed/speed/playback metadata. No provider credential is present. The approved shipping pack is recorded separately above | Failed exploratory candidates remain QA evidence and are never fallback voices. |
| World music and functional effects | `ProceduralAudioDesign.swift` and `ProceduralAudioRenderer.swift` synthesize oscillator/noise output | Compiled code; generated PCM exists only at runtime | `DesignAssets/Audio/README.md` documents the method and absence of third-party samples | Ownership confirmation remains part of #33. |
| Apple speech, handwriting, OCR, and recognition | Operating-system frameworks and services | Uses platform APIs; no Apple voice/model file is bundled | Apple platform APIs | Not represented as Pawgoo-owned recordings or models. |
| Twemoji picture hints | 74 unmodified PNGs, `manifest.json`, `README.md`, and `LICENSE-GRAPHICS.txt` under `PictureHints/Twemoji-17.0.3` | All 77 files are copied into the `TadaWordsApplePlatform` resource bundle; the app reads them offline and contains no picture-hint CDN path | `jdecked/twemoji` 17.0.3, commit `b6b55fef1e8636b540a6d016a4729ca8cdf2e60b`, CC BY 4.0; manifest SHA-256 `e2232045781f9984879eedcee3ae4cd410aa506daa77710e53f06759a29f7a27`; license SHA-256 `8ae9438818c26e4873b91d8c6ad620526c011e27e125677f13031eda903f007c`; complete-pack digest `fbe89ce4496e0f50a59f93b3dc55f2e3e24eb1bcd463597c218a40e5f19d7a1a` | Source/license evidence is present. Parent Home → App & Family → Third-Party Notices identifies the source, version, unmodified quantity, copyright attribution, CC BY 4.0 license, and offline availability. |
| Preset word catalog | Five roots, 34 leaf presets, 1,365 references, 1,166 normalized unique words, and seven method references | `PresetWords.json` is processed into the `TadaWordsContent` resource bundle | SHA-256 `f5b0a273a816d97de265f82f8a16d56bc45cbc2be19d585dfda05449827e3fd0`; source/method notes are in the JSON and `Docs/TADA_WORDS_PRESET_CATALOG.md` | Editorial ownership confirmation is blocked by #33. Do not describe the catalog as a copied branded list. |
| Persistence compatibility table | `Apps/TadaWordsApp/PersistenceSchemaCompatibility.json` | Copied to the application root to declare supported local-store schema versions | SHA-256 `51f579dccf3d44c5b03176cbb6abc975e983b547f7be205867f1a65df8156676`; repository-authored runtime configuration | It contains schema names and integer versions, not user or third-party content. |
| Family-provided photos and word-sheet images | Parent-selected profile photos and transient camera/photo OCR input | Not bundled. Profile photos may become family sync data only after the parent enables that feature; word-sheet images are input, not release assets | Runtime user-selected content and privacy/data-flow controls | Not approved by this inventory for App Store marketing or Pawgoo ownership claims. |
| QA and candidate screenshots | 19 tracked PNG/JPEG captures under `QAArtifacts` | Not copied into the application target | Generated from Tada Words builds; current source scan found no imported stock photo | Exact App Store screenshots still require release-candidate selection and human review. |
| Child-speech test fixture | One WAV, `speechocean762-000010168-bye.wav` | Test-only and rejected by the archive verifier | OpenSLR SLR101/speechocean762, CC BY 4.0; SHA-256 `807df45f3aec0718c30929595a9db1e99eab87134e6cdefe15551aa8c0a79db8`; local license record beside fixture | Must never enter the App Store binary or marketing. |
| Test/demo values and build products | Swift fixtures, synthetic names, ignored `.build`, DerivedData, archives, IPAs, symbols, provisioning data | Test sources and ignored products are excluded from the app | Repository configuration and archive inspection | No real child identity, portrait, or private fixture is approved for marketing reuse. |

## Source and archive boundary

- `Package.swift` has no remote package dependency. All application products are
  local Tada Words targets.
- `TadaWordsContent` processes its `Resources` directory.
- `TadaWordsApplePlatform` copies both `Resources/Audio` and
  `Resources/PictureHints`.
- The current source contains exactly 1,000 teacher MP3 files, eight accent M4A
  files, 74 bundled Twemoji PNGs, four Swift-package resource JSON files, one
  app-level persistence compatibility JSON file, and no custom font file under
  `Apps` or `Sources`.
- `AppleWordPictureHintService` reads `Bundle.module` only. It has no URL,
  `URLSession`, jsDelivr, or other CDN path.
- The Parent-gated `App & Family` section opens `Third-Party Notices`. Its
  attribution, source/version, unmodified quantity, license, and offline-status
  text are local Swift constants; only the optional source and license links
  open a web browser.
- `RemoteTeacherWordAudioProvider` compiles into the binary, but the production
  plist has no `TadaWordsTeacherAudioEndpoint`; the bundled provider is the
  current release path.
- `QAArtifacts`, `DesignAssets`, `Tests`, and documentation are not application
  target resources. The archive verifier rejects their names, the child-speech
  fixture, WAV files, and custom font files.
- Runtime family photos and OCR inputs are data, not static archive resources.

## Evidence locations

| Evidence | Location |
| --- | --- |
| Repository third-party notice | `THIRD_PARTY_NOTICES.md` |
| Twemoji manifest, provenance, and full license | `Sources/TadaWordsApplePlatform/Resources/PictureHints/Twemoji-17.0.3/` |
| Cartesia pack metadata | `Sources/TadaWordsApplePlatform/Resources/Audio/**/manifest.json` |
| ElevenLabs candidate metadata and listening samples | `QAArtifacts/TeacherAudio-ElevenLabs-*` and `QAArtifacts/TeacherAudio-Pronunciation-Alias-Evaluation/` |
| ElevenLabs replacement generator, inspector, and proposed dictionary | `Tools/Audio/` |
| Generated/procedural audio notes | `DesignAssets/Audio/README.md` |
| Preset source/method record | `Sources/TadaWordsContent/Resources/PresetWords.json` and `Docs/TADA_WORDS_PRESET_CATALOG.md` |
| Child fixture license/checksum | `Tests/Fixtures/ChildSpeech/LICENSE_SOURCE.md` and `SHA256SUMS` |
| Repeatable source/archive assertions | `Scripts/verify-release-content-inventory.sh` |
| Cartesia commercial entitlement | Missing; #32 |
| Pawgoo ownership attestation | Missing; #33 |
| Adult-accessible in-app attribution | `GuardianTodayView.swift`, `GuardianRootView.swift`, and `GuardianThirdPartyNoticesView.swift`; implemented by #34 |
| Attribution route tests | `GuardianParentNavigationTests.testThirdPartyNoticeMatchesBundledTwemojiAttribution` and `TadaWordsCriticalFlowUITests.testParentCanOpenOfflineThirdPartyNotices` |

## App Store Connect Content Rights draft

The app displays licensed Twemoji graphics, bundles voice-service output, and
may display family-provided profile content. The conservative draft is:

> This app contains, shows, or accesses third-party content. Pawgoo has the
> necessary rights or permissions to use that content in every selected App
> Store country or region.

Do **not** submit that representation until #32 and #33 are resolved and
the unchanged signed release-candidate archive passes the verifier. Repeat the
review if the content set, generation terms, or storefront list changes.

## Exact-archive acceptance

1. Build the final production archive from the unchanged release-candidate
   HEAD with `TADA_GIT_COMMIT` set to that full 40-character commit.
2. Run:

   ```sh
   Scripts/verify-release-content-inventory.sh /absolute/path/TadaWords.xcarchive
   ```

3. Record the archive path, source HEAD, version/build, bundle ID, embedded
   commit, signing evidence, and verifier output in the release PR.
4. Refresh this inventory if any count, hash, third-party version, voice pack,
   screenshot, preset, font, or target resource changes.
