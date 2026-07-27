import Foundation
import XCTest

final class AppStoreSubmissionPackContractTests: XCTestCase {
    private let expectedKeywords =
        "sight words,reading,spelling,handwriting,vocabulary,school,practice,word lists,early literacy"

    func testMetadataFieldsStayWithinAppStoreLimits() throws {
        let document = try submissionPack()
        let appName = try tableValue(for: "App name", in: document)
        let subtitle = try tableValue(for: "Subtitle", in: document)
        let promotionalText = try tableValue(for: "Promotional text", in: document)
        let keywords = try tableValue(for: "Keywords", in: document)
        let description = try fencedTextBlock(after: "### Description", in: document)
        let reviewNotes = try fencedTextBlock(
            after: "### Base Notes for Review",
            in: document
        )

        XCTAssertEqual(appName, "Tada Words")
        XCTAssertLessThanOrEqual(appName.count, 30)
        XCTAssertEqual(subtitle, "Personal sight-word practice")
        XCTAssertLessThanOrEqual(subtitle.count, 30)
        XCTAssertLessThanOrEqual(promotionalText.count, 170)
        XCTAssertEqual(keywords, expectedKeywords)
        XCTAssertLessThanOrEqual(keywords.utf8.count, 100)
        XCTAssertLessThanOrEqual(description.count, 4_000)
        XCTAssertLessThanOrEqual(reviewNotes.count, 4_000)
        XCTAssertLessThanOrEqual(reviewNotes.utf8.count, 4_000)

        for field in ["Marketing URL", "Support URL", "Privacy Policy URL"] {
            let value = try tableValue(for: field, in: document)
            let url = try XCTUnwrap(URL(string: value), "Invalid \(field): \(value)")
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.host, "pawgoo.app")
        }
    }

    func testEveryLocalSubmissionPackLinkResolves() throws {
        let document = try submissionPack()
        let regularExpression = try NSRegularExpression(
            pattern: #"\[[^\]]+\]\(([^)]+)\)"#
        )
        let fullRange = NSRange(document.startIndex..., in: document)
        let destinations = regularExpression.matches(in: document, range: fullRange)
            .compactMap { match -> String? in
                guard let range = Range(match.range(at: 1), in: document) else {
                    return nil
                }
                return String(document[range])
            }
            .filter { !$0.hasPrefix("https://") && !$0.hasPrefix("http://") }

        XCTAssertGreaterThan(destinations.count, 40)
        for destination in destinations {
            let path = String(destination.split(separator: "#", maxSplits: 1)[0])
            let decodedPath = path.removingPercentEncoding ?? path
            let target = URL(
                fileURLWithPath: decodedPath,
                relativeTo: submissionPackURL.deletingLastPathComponent()
            ).standardizedFileURL
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: target.path),
                "Submission-pack link does not resolve: \(destination) -> \(target.path)"
            )
        }
    }

    func testSubmissionPackUsesCurrentEvidenceWithoutStaleClaims() throws {
        let document = try submissionPack()
        let requiredClaims = [
            "ce479db21eba64bd6abcd0aba739c222dfabb6a9",
            "Metadata-pack version | `0.7.5`",
            "Reserved build | `2026071905`",
            "app.tadawords.app",
            "7R78Q4HP86",
            "APP_STORE_PRIVACY_v0.7.4.md",
            "APP_STORE_CONTENT_RIGHTS.md",
            "PROFILES FOR EACH LEARNER",
            "LocalJSONKidProfileRepository",
            "GuardianWordManagerView",
            "no Pawgoo account or login",
            "available iCloud account",
            "final-Profile/delete-all",
            "TadaWordsTeacherAudioEndpoint",
            "#19",
            "#28",
            "#32",
            "#33",
            "#54",
            "#125",
            "#76",
            "Finalized for the enumerated content set",
            "#33 preserves the Pawgoo owner attestation",
            "first child microphone tap",
            "SYSTEM_PERMISSION_INVENTORY_v0.7.8.md",
            "VOICEPRINT_1_0_RELEASE_FALLBACK_v0.7.32.md",
            "request still-undetermined Speech Recognition and Microphone access in sequence",
            "APP_STORE_RELEASE_DECISIONS_v0.7.27.md",
            "Made for Kids, Apple primary band `6–8`, product and in-app Profile ages 3–8",
            "Primary Kids age band | `6–8`",
            "Apple Kids Category supports one primary band",
            "United States only",
            "Manually release this version",
            "No IAP, subscription, advertising, or paid unlock in 1.0",
            "https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/",
        ]
        for claim in requiredClaims {
            XCTAssertTrue(document.contains(claim), "Missing current claim: \(claim)")
        }

        let staleClaims = [
            "bd9ce11",
            "2026071803",
            "0.6.6",
            "PR #29",
            "PR #35",
            "#34",
            "`GuardianQuickAddView`",
            "`KidProfileRepositories`",
            "phonics",
            "flashcards",
            "MADE FOR SHARED DEVICES",
            "eligible remote teacher-audio endpoint",
            "tap the microphone control and allow Microphone",
        ]
        for claim in staleClaims {
            XCTAssertFalse(document.contains(claim), "Stale claim returned: \(claim)")
        }

        let productionPlist = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Apps/TadaWordsApp/Info.plist"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            productionPlist.contains(
                "<string>https://audio.pawgoo.app</string>"
            )
        )
        XCTAssertTrue(productionPlist.contains("<string>0.7.52</string>"))
        XCTAssertTrue(productionPlist.contains("<string>2026072703</string>"))
        XCTAssertFalse(productionPlist.contains("voice setup"))

        for plistPath in ["Apps/TadaWordsApp/InfoLocalQA.plist"] {
            let plist = try String(
                contentsOf: repositoryRoot.appendingPathComponent(plistPath),
                encoding: .utf8
            )
            XCTAssertFalse(plist.contains("TadaWordsTeacherAudioEndpoint"))
            XCTAssertTrue(plist.contains("<string>0.7.52</string>"))
            XCTAssertTrue(plist.contains("<string>2026072703</string>"))
            XCTAssertFalse(plist.contains("voice setup"))
        }

        let debugPlist = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Apps/TadaWordsApp/InfoDebug.plist"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            debugPlist.contains(
                "<string>https://audio-dev.pawgoo.app</string>"
            )
        )
        XCTAssertTrue(debugPlist.contains("<string>0.7.52</string>"))
        XCTAssertTrue(debugPlist.contains("<string>2026072703</string>"))

        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent("project.yml"),
            encoding: .utf8
        )
        XCTAssertTrue(project.contains("MARKETING_VERSION: 0.7.52"))
        XCTAssertTrue(project.contains("CURRENT_PROJECT_VERSION: 2026072703"))

        let appComposition = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Apps/TadaWordsApp/TadaWordsApp.swift"
            ),
            encoding: .utf8
        )
        XCTAssertFalse(
            appComposition.contains("AppleVoiceprintEnrollmentService(")
        )
        XCTAssertFalse(
            appComposition.contains(
                "voiceprintVerifier: AppleVoiceprintVerifier("
            )
        )
        XCTAssertTrue(
            appComposition.contains("voiceprintEnrollmentService: nil")
        )
        XCTAssertTrue(
            appComposition.contains("voiceprintRepository: voiceprintRepository")
        )

        let profilesView = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/TadaWordsGuardianFeatures/GuardianProfilesView.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(
            profilesView.contains(
                "if VoiceprintReleasePolicy.shipsEnrollmentAndSpeakerMatching"
            )
        )

        for unresolvedDecision in [
            "Price | **UNRESOLVED — #24**",
            "Availability | **UNRESOLVED — #23/#24**",
            "Do not select an age band",
        ] {
            XCTAssertFalse(
                document.contains(unresolvedDecision),
                "Resolved #24 decision regressed: \(unresolvedDecision)"
            )
        }
    }

    func testTeacherAudioDocsDefineCatalogMissAppleFallback() throws {
        let paths = [
            "README.md",
            "Docs/ADR-0001-CROSS-DEVICE-FAMILY-SYNC.md",
            "Docs/TEACHER_AUDIO_RELEASE_GATES.md",
            "Tools/Audio/README.md",
        ]
        for path in paths {
            let document = try String(
                contentsOf: repositoryRoot.appendingPathComponent(path),
                encoding: .utf8
            )
            XCTAssertTrue(
                document.localizedCaseInsensitiveContains(
                    "catalog-miss fallback"
                ),
                "Missing bounded Apple fallback contract in \(path)"
            )
        }
    }

    func testTeacherAudioCatalogFreezesOfflineOnlineAndCostBoundaries() throws {
        let catalogURL = repositoryRoot.appendingPathComponent(
            "Tools/Audio/Catalogs/TeacherWordCatalog-4000-v1.json"
        )
        let catalog = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL))
                as? [String: Any]
        )
        let offline = try XCTUnwrap(catalog["offlineWords"] as? [String])
        let online = try XCTUnwrap(catalog["onlineWords"] as? [String])
        let counts = try XCTUnwrap(catalog["counts"] as? [String: Int])

        XCTAssertEqual(offline.count, 2_000)
        XCTAssertEqual(online.count, 4_000)
        XCTAssertEqual(Set(offline).count, offline.count)
        XCTAssertEqual(Set(online).count, online.count)
        XCTAssertTrue(Set(offline).isDisjoint(with: Set(online)))
        XCTAssertEqual(Set(offline).union(online).count, 6_000)
        XCTAssertEqual(counts["totalBellaWords"], 6_000)
        XCTAssertEqual(counts["offlineTwoVariantCharacters"], 22_532)
        XCTAssertEqual(counts["onlineTwoVariantCharacters"], 56_262)
        XCTAssertEqual(counts["twoVariantCharacters"], 78_794)
        XCTAssertEqual(counts["newTwoVariantCharacters"], 74_560)
        XCTAssertTrue(Set(offline).contains("as"))
        XCTAssertTrue(Set(online).contains("albatross"))

        let manifestURL = repositoryRoot.appendingPathComponent(
            "Sources/TadaWordsApplePlatform/Resources/Audio/TeacherWords/"
                + "ElevenLabs-Teacher-2000-v1/manifest.json"
        )
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
                as? [String: Any]
        )
        let bundled = try XCTUnwrap(manifest["words"] as? [String])
        XCTAssertTrue(Set(bundled).isSubset(of: Set(offline)))

        let releasePolicyURL = repositoryRoot.appendingPathComponent(
            "Config/release-candidate-policy.json"
        )
        let releasePolicy = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: releasePolicyURL))
                as? [String: Any]
        )
        let requiredSourceFiles = try XCTUnwrap(
            releasePolicy["required_source_files"] as? [String]
        )
        let requiredAppResources = try XCTUnwrap(
            releasePolicy["required_app_resources"] as? [String]
        )
        XCTAssertTrue(
            requiredSourceFiles.contains {
                $0.contains("ElevenLabs-Teacher-2000-v1/manifest.json")
            }
        )
        XCTAssertTrue(
            requiredAppResources.contains {
                $0.contains("ElevenLabs-Teacher-2000-v1/read-hint/*.mp3")
            }
        )
        XCTAssertTrue(
            requiredAppResources.contains {
                $0.contains("ElevenLabs-Teacher-2000-v1/write-prompt/*.mp3")
            }
        )
        XCTAssertFalse(
            (requiredSourceFiles + requiredAppResources).contains {
                $0.contains("ElevenLabs-Teacher-500-v1")
            }
        )

        for excluded in [
            "fuck", "shit", "bitch", "porn", "rape", "sex", "sexual",
            "sexy", "suicide",
        ] {
            XCTAssertFalse(online.contains(excluded))
        }
    }

    func testProductionDeviceInstallerPreservesExistingAppData() throws {
        let installer = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scripts/install-production-device.sh"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            installer.contains("TADA_EXPECTED_BUNDLE_ID=app.tadawords.app")
        )
        XCTAssertTrue(
            installer.contains("verify-localqa-device-persistence.sh")
        )
        XCTAssertFalse(
            installer.contains("devicectl device uninstall")
        )
    }

    func testQAArtifactsContainsNoChildDirectories() throws {
        let artifactsURL = repositoryRoot.appendingPathComponent("QAArtifacts")
        let children = try FileManager.default.contentsOfDirectory(
            at: artifactsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for child in children {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            XCTAssertNotEqual(
                values.isDirectory,
                true,
                "QAArtifacts must not contain child directories: \(child.lastPathComponent)"
            )
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var submissionPackURL: URL {
        repositoryRoot.appendingPathComponent(
            "Docs/APP_STORE_SUBMISSION_PACK_v0.7.5.md"
        )
    }

    private func submissionPack() throws -> String {
        try String(contentsOf: submissionPackURL, encoding: .utf8)
    }

    private func tableValue(for field: String, in document: String) throws -> String {
        let prefix = "| \(field) |"
        let line = try XCTUnwrap(
            document.split(separator: "\n", omittingEmptySubsequences: false)
                .first { $0.hasPrefix(prefix) },
            "Missing metadata row: \(field)"
        )
        let components = line.split(separator: "`", omittingEmptySubsequences: false)
        let value: Substring? = components.count >= 3 ? components[1] : nil
        return String(try XCTUnwrap(value, "Missing inline value: \(field)"))
    }

    private func fencedTextBlock(after heading: String, in document: String) throws -> String {
        let headingRange = try XCTUnwrap(document.range(of: heading))
        let remainder = document[headingRange.upperBound...]
        let openingRange = try XCTUnwrap(remainder.range(of: "```text\n"))
        let afterOpening = remainder[openingRange.upperBound...]
        let closingRange = try XCTUnwrap(afterOpening.range(of: "\n```"))
        return String(afterOpening[..<closingRange.lowerBound])
    }
}
