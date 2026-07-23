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
            "#55",
            "Provisional",
            "BLOCKED BY ISSUE #55",
            "SYSTEM_PERMISSION_INVENTORY_v0.7.8.md",
            "Child Read has no request capability",
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

        for plistPath in [
            "Apps/TadaWordsApp/Info.plist",
            "Apps/TadaWordsApp/InfoLocalQA.plist",
        ] {
            let plist = try String(
                contentsOf: repositoryRoot.appendingPathComponent(plistPath),
                encoding: .utf8
            )
            XCTAssertFalse(plist.contains("TadaWordsTeacherAudioEndpoint"))
            XCTAssertTrue(plist.contains("<string>0.7.24</string>"))
            XCTAssertTrue(plist.contains("<string>2026072124</string>"))
        }

        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent("project.yml"),
            encoding: .utf8
        )
        XCTAssertTrue(project.contains("MARKETING_VERSION: 0.7.24"))
        XCTAssertTrue(project.contains("CURRENT_PROJECT_VERSION: 2026072124"))
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
