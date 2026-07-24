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

The source and archive boundary is mechanically verifiable. The release owner
confirmed the Pawgoo authorship and rights chain on 2026-07-23:

- #32's Cartesia account/tier evidence is preserved for the enumerated current
  Katie/Aurora pack; the exact release candidate must reconcile its actual
  retained audio assets and provider terms before this record is relied on.
- The authorized Pawgoo representative confirmed that the original icon and
  marks, SwiftUI worlds and mascots, reward names/icons, procedural
  music/effects, preset editorial selection, and OpenAI-generated zodiac
  avatars were created or generated under Pawgoo authorization and that Pawgoo
  LLC is authorized to distribute them.
- Licensed Twemoji, Cartesia output, Apple platform resources, and test-only
  fixtures remain governed by their separately recorded terms.

The private Pawgoo rights evidence index remains outside Git; its recorded
SHA-256 is
`85a98c0275800457e53d8607312650a6621afd3ce2e2f165c0c6fa2ab47ee73f`.
The Parent-gated, offline Third-Party Notices route from #34 remains the
in-product attribution surface.

## Current inventory

| Content class | Concrete source and quantity | Production `.app` status | Evidence and permission basis | Attribution / status |
| --- | --- | --- | --- | --- |
| Tada Words app icon and mark | `AppIcon-1024.png`; `TadaWordsAppIcon.svg`; duplicate design source under `DesignAssets` | Asset catalogs compile the production copies into app-icon output and `Assets.car`; design sources do not ship | SHA-256: PNG `ce1782b295901de1a7cc82f6f61cfc5ffbebf9bc0745256a573058bd1281e637`; SVG `e47bfb19efa22e38db1b2a796bb47bb87993fc35b5ae4e6ba6624a9ec5e7b816` | Pawgoo ownership confirmed by the 2026-07-23 owner attestation. |
| Pawgoo mark | `Apps/TadaWordsApp/Assets.xcassets/PawgooMark.imageset/pawgoo-mark.svg` | Compiled into `Assets.car` | SHA-256 `2653ed92cac054f5df24d1726a90cd8e147b7e784cd98653c26f99d08c05f6c9` | Pawgoo ownership confirmed by the 2026-07-23 owner attestation. |
| World scenes, mascots, avatars, rewards | SwiftUI `Shape`, `Path`, gradients, colors, SF Symbols, and local catalogs under `Sources` | Ships as compiled code; there is no world raster-art pack | Repository-authored source plus Apple platform symbols | Pawgoo ownership confirmed by the 2026-07-23 owner attestation. SF Symbols are platform resources, not redistributed custom files. |
| Fonts and text | SwiftUI system font APIs | No `.ttf` or `.otf` file ships | Apple system font APIs | Re-audit if a custom font is introduced. |
| Katie teacher words | 500 manifest words with Read and Write variants: 1,000 AAC-LC M4A files in `Katie-500-v1` | Copied into the `TadaWordsApplePlatform` resource bundle | Manifest SHA-256 `c2909c26c4423d0254b0bfdf996894d6d9420c5c9b7543a12bc78d7d350aa93b`; Cartesia Sonic 3.5; Katie voice; pack `1.1.0`; created 2026-07-14 | Private evidence records Cartesia Pro entitlement during generation; see #32 pointer below. It applies only while these exact assets remain in the release candidate. |
| Aurora launch and celebrations | Eight AAC-LC M4A files: launch, five positive transitions, quest complete, and the `ta-da` source | Copied into the same resource bundle | Manifest SHA-256 `4f49d4e97d0113419a78cee8b96cae252dfa9e2df230233151eae76c8bdca31b`; Cartesia Sonic 3.5; Aurora voice; pack `1.1.0`; created 2026-07-14 | Private evidence records Cartesia Pro entitlement during generation; see #32 pointer below. It applies only while these exact assets remain in the release candidate. |
| Complete voice pack | 1,008 M4A files | Bundled offline | Stable relative-path/checksum digest `d8556c3035e6bce1947ce094531b64164a88433d0f58ee54ca03fd81a02fab86` | No runtime teacher-audio endpoint is configured in the production plist. Reconcile the exact release candidate after any #74/#81 audio replacement. |
| World music and functional effects | `ProceduralAudioDesign.swift` and `ProceduralAudioRenderer.swift` synthesize oscillator/noise output | Compiled code; generated PCM exists only at runtime | `DesignAssets/Audio/README.md` documents the method and absence of third-party samples | Pawgoo ownership confirmed by the 2026-07-23 owner attestation. |
| Apple speech, handwriting, OCR, and recognition | Operating-system frameworks and services | Uses platform APIs; no Apple voice/model file is bundled | Apple platform APIs | Not represented as Pawgoo-owned recordings or models. |
| Twemoji picture hints | 74 unmodified PNGs, `manifest.json`, `README.md`, and `LICENSE-GRAPHICS.txt` under `PictureHints/Twemoji-17.0.3` | All 77 files are copied into the `TadaWordsApplePlatform` resource bundle; the app reads them offline and contains no picture-hint CDN path | `jdecked/twemoji` 17.0.3, commit `b6b55fef1e8636b540a6d016a4729ca8cdf2e60b`, CC BY 4.0; manifest SHA-256 `e2232045781f9984879eedcee3ae4cd410aa506daa77710e53f06759a29f7a27`; license SHA-256 `8ae9438818c26e4873b91d8c6ad620526c011e27e125677f13031eda903f007c`; complete-pack digest `fbe89ce4496e0f50a59f93b3dc55f2e3e24eb1bcd463597c218a40e5f19d7a1a` | Source/license evidence is present. Parent Home → App & Family → Third-Party Notices identifies the source, version, unmodified quantity, copyright attribution, CC BY 4.0 license, and offline availability. |
| Preset word catalog | Five roots, 34 leaf presets, 1,365 references, 1,166 normalized unique words, and seven method references | `PresetWords.json` is processed into the `TadaWordsContent` resource bundle | SHA-256 `f5b0a273a816d97de265f82f8a16d56bc45cbc2be19d585dfda05449827e3fd0`; source/method notes are in the JSON and `Docs/TADA_WORDS_PRESET_CATALOG.md` | Editorial ownership confirmed by the 2026-07-23 owner attestation. Do not describe the catalog as a copied branded list. |
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
- The current source contains exactly 1,008 M4A files, 74 bundled Twemoji PNGs,
  four Swift-package resource JSON files, one app-level persistence compatibility
  JSON file, and no custom font file under `Apps` or `Sources`.
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
| Generated/procedural audio notes | `DesignAssets/Audio/README.md` |
| Preset source/method record | `Sources/TadaWordsContent/Resources/PresetWords.json` and `Docs/TADA_WORDS_PRESET_CATALOG.md` |
| Child fixture license/checksum | `Tests/Fixtures/ChildSpeech/LICENSE_SOURCE.md` and `SHA256SUMS` |
| Repeatable source/archive assertions | `Scripts/verify-release-content-inventory.sh` |
| Cartesia commercial entitlement for the current pack | Private owner-controlled evidence vault `Cartesia/2026-07-14/` (outside Git): Cartesia Pro effective 2026-07-14 through 2026-08-14; safe invoice reference `DO1RKSRC-0001`, receipt reference `2706-2686`, invoice SHA-256 `71e3533be3361733cf5d13ae9fe5240a0e87e2d1c9aa8f854876a9e51175f24b`, receipt SHA-256 `1ca2ed49122c0298d3fcd1278341a8b4bbaf5b62387f4610f93297df3a657082`, private index SHA-256 `868275560ed488189442a7f863e9ed9cf281fd4f77cf0901bbc9ea35d66faecf`; official sources: [pricing](https://www.cartesia.ai/pricing), [Terms](https://www.cartesia.ai/legal/terms), and [Acceptable Use Policy](https://www.cartesia.ai/legal/acceptable-use). The pointer covers only the listed 1,008-file Cartesia pack and is not a legal opinion. |
| Pawgoo ownership attestation | Owner-confirmed 2026-07-23; private evidence index SHA-256 `85a98c0275800457e53d8607312650a6621afd3ce2e2f165c0c6fa2ab47ee73f` |
| Adult-accessible in-app attribution | `GuardianTodayView.swift`, `GuardianRootView.swift`, and `GuardianThirdPartyNoticesView.swift`; implemented by #34 |
| Attribution route tests | `GuardianParentNavigationTests.testThirdPartyNoticeMatchesBundledTwemojiAttribution` and `TadaWordsCriticalFlowUITests.testParentCanOpenOfflineThirdPartyNotices` |

## App Store Connect Content Rights draft

The app displays licensed Twemoji graphics, bundles voice-service output, and
may display family-provided profile content. The conservative draft is:

> This app contains, shows, or accesses third-party content. Pawgoo has the
> necessary rights or permissions to use that content in every selected App
> Store country or region.

The owner attestation and recorded Cartesia evidence support this
representation for the current United States-only content set after the exact
release-candidate archive passes the verifier. Repeat the review if the content
set, generation terms, or storefront list changes.

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
