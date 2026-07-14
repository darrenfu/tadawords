import Foundation
import TadaWordsDomain
import TadaWordsGuardianFeatures
import XCTest

@testable import TadaWordsAppShell

final class FamilyApplicationCompositionTests: XCTestCase {
    func testGuardianProfileSelectionScopesEverySharedProductionRepository()
        async throws
    {
        let supportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TadaWordsFamily-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: supportDirectory) }
        let firstProfile = makeProfile(name: "Mia", suffix: 1)
        let environment = try await ProductionApplicationBootstrapper(
            applicationSupportDirectory: { supportDirectory },
            defaultProfile: firstProfile,
            clock: FamilyCompositionClock(now: testDate),
            timeZone: TimeZone(secondsFromGMT: 0) ?? .current
        ).bootstrap()

        let secondDashboard = try await environment.guardianStore.createProfile(
            from: GuardianProfileDraft(
                displayName: "Leo",
                avatarAssetID: "dog",
                selectedWorld: .buildItBay,
                ageYears: 4
            )
        )
        let secondProfile = secondDashboard.profile
        _ = try await environment.guardianStore.importWords(
            GuardianWordImportRequest(rawText: "cat", learningMode: .read)
        )
        let secondSettings = ProfilePracticeSettings(
            profileID: secondProfile.id,
            write: LearningRouteSettings(
                newWordLimit: 6,
                reviewWordLimit: 3,
                contentOrder: .reviewThenNew,
                emergencyAfterSeconds: 240
            )
        )
        _ = try await environment.guardianStore.updatePracticeSettings(secondSettings)
        let secondAttempt = AttemptEvent(
            profileID: secondProfile.id,
            wordPromptID: WordPromptID(),
            learningMode: .read,
            evidence: .firstIndependentAttempt,
            outcome: .correct,
            occurredAt: testDate
        )
        try await environment.learningRecordRepository.append(secondAttempt)

        _ = try await environment.guardianStore.selectProfile(id: firstProfile.id)
        _ = try await environment.guardianStore.importWords(
            GuardianWordImportRequest(rawText: "dog", learningMode: .write)
        )

        let profiles = try await environment.profileRepository.profiles()
        let firstRead = try await environment.wordPoolRepository.entries(
            for: firstProfile.id,
            learningMode: .read,
            includingInactive: true
        )
        let firstWrite = try await environment.wordPoolRepository.entries(
            for: firstProfile.id,
            learningMode: .write,
            includingInactive: true
        )
        let secondRead = try await environment.wordPoolRepository.entries(
            for: secondProfile.id,
            learningMode: .read,
            includingInactive: true
        )
        let secondWrite = try await environment.wordPoolRepository.entries(
            for: secondProfile.id,
            learningMode: .write,
            includingInactive: true
        )
        let firstSettings = try await environment.practiceSettingsRepository.settings(
            for: firstProfile.id
        )
        let storedSecondSettings = try await environment.practiceSettingsRepository.settings(
            for: secondProfile.id
        )
        let firstAttempts = try await environment.learningRecordRepository.attempts(
            for: firstProfile.id,
            wordPromptID: nil
        )
        let secondAttempts = try await environment.learningRecordRepository.attempts(
            for: secondProfile.id,
            wordPromptID: nil
        )

        XCTAssertEqual(profiles.map(\.id), [firstProfile.id, secondProfile.id])
        XCTAssertTrue(firstRead.isEmpty)
        XCTAssertEqual(firstWrite.map(\.prompt.normalizedText), ["dog"])
        XCTAssertEqual(secondRead.map(\.prompt.normalizedText), ["cat"])
        XCTAssertTrue(secondWrite.isEmpty)
        XCTAssertEqual(firstSettings, .defaults(for: firstProfile.id))
        XCTAssertEqual(storedSecondSettings, secondSettings)
        XCTAssertTrue(firstAttempts.isEmpty)
        XCTAssertEqual(secondAttempts, [secondAttempt])
    }

    private let testDate = Date(timeIntervalSince1970: 2_000_000_000)

    private func makeProfile(name: String, suffix: Int) -> KidProfile {
        KidProfile(
            id: ProfileID(
                rawValue: UUID(
                    uuidString: String(
                        format: "92000000-0000-0000-0000-%012X",
                        suffix
                    )
                )!
            ),
            displayName: name,
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: testDate.addingTimeInterval(-100)
        )
    }
}

private struct FamilyCompositionClock: AppClock {
    let now: Date
}
