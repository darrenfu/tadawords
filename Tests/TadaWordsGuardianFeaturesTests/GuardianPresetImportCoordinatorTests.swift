import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

@testable import TadaWordsGuardianFeatures

@MainActor
final class GuardianPresetImportCoordinatorTests: XCTestCase {
    func testDeactivatedRepositoryMembershipIsRestoredAndCountedAsSuccess() async throws {
        let repository = InMemoryWordPoolRepository()
        let profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            schoolGrade: .preK,
            ageYears: 4,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let store = RepositoryGuardianWordStore(
            profile: profile,
            wordPoolRepository: repository,
            practiceSettingsRepository: InMemoryPracticeSettingsRepository(),
            clock: PresetImportFixedClock()
        )
        _ = try await store.importWords(
            GuardianWordImportRequest(rawText: "dog", learningMode: .read)
        )
        let originalSnapshot = try await store.dashboardSnapshot()
        let original = try XCTUnwrap(originalSnapshot.readPool.first)
        _ = try await store.setWordsActive(
            ids: [original.id],
            learningMode: .read,
            isActive: false
        )
        let plan = PresetWordSelectionPlanner().plan(
            selectedWords: ["Dog"],
            destination: .read,
            existingReadWords: [],
            existingWriteWords: []
        )

        let outcome = await GuardianPresetImportCoordinator().execute(
            profileID: profile.id,
            plan: plan,
            submit: { submittedProfileID, request in
                XCTAssertEqual(submittedProfileID, profile.id)
                return try? await store.importWords(request)
            },
            rollback: { _ in
                XCTFail("A complete restoration must not roll back.")
                return false
            }
        )

        XCTAssertEqual(
            outcome,
            .success(
                GuardianPresetImportSummary(
                    addedMembershipCount: 0,
                    reactivatedMembershipCount: 1,
                    alreadyPresentMembershipCount: 0
                )
            )
        )
        let restored = try await store.dashboardSnapshot().readPool
        XCTAssertEqual(restored.map(\.normalizedText), ["dog"])
        XCTAssertEqual(restored.first?.id, original.id)
    }

    func testAlreadyActivePlannedMembershipCountsAsAlreadyPresent() async throws {
        let profileID = ProfileID()
        let dog = try membership("dog", mode: .read, number: 1)
        let plan = PresetWordSelectionPlanner().plan(
            selectedWords: ["Dog"],
            destination: .read,
            existingReadWords: [],
            existingWriteWords: []
        )
        var rollbackRequests: [GuardianPresetRollbackRequest] = []

        let outcome = await GuardianPresetImportCoordinator().execute(
            profileID: profileID,
            plan: plan,
            submit: { submittedProfileID, request in
                XCTAssertEqual(submittedProfileID, profileID)
                XCTAssertEqual(request.learningMode, .read)
                return GuardianWordImportReport(
                    profileID: profileID,
                    learningMode: .read,
                    insertedMemberships: [],
                    reactivatedMemberships: [],
                    alreadyActiveMemberships: [dog],
                    rejected: []
                )
            },
            rollback: { request in
                rollbackRequests.append(request)
                return true
            }
        )

        let summary = GuardianPresetImportSummary(
            addedMembershipCount: 0,
            reactivatedMembershipCount: 0,
            alreadyPresentMembershipCount: 1
        )
        XCTAssertEqual(outcome, .success(summary))
        XCTAssertEqual(
            summary.message,
            "1 already exists in the selected pool or pools."
        )
        XCTAssertTrue(rollbackRequests.isEmpty)
    }

    func testAlreadyActiveFirstPoolIsNotDeactivatedWhenSecondPoolFails()
        async throws
    {
        let profileID = ProfileID()
        let dog = try membership("dog", mode: .read, number: 8)
        let plan = PresetWordSelectionPlanner().plan(
            selectedWords: ["dog"],
            destination: .both,
            existingReadWords: [],
            existingWriteWords: []
        )

        let outcome = await GuardianPresetImportCoordinator().execute(
            profileID: profileID,
            plan: plan,
            submit: { submittedProfileID, request in
                XCTAssertEqual(submittedProfileID, profileID)
                guard request.learningMode == .read else { return nil }
                return GuardianWordImportReport(
                    profileID: profileID,
                    learningMode: .read,
                    insertedMemberships: [],
                    reactivatedMemberships: [],
                    alreadyActiveMemberships: [dog],
                    rejected: []
                )
            },
            rollback: { _ in
                XCTFail("An originally active membership must not be rolled back.")
                return false
            }
        )

        XCTAssertEqual(outcome, .failure(.unchanged))
    }

    func testBothSecondPoolFailureRollsBackExactFirstPoolMemberships() async throws {
        let profileID = ProfileID()
        let dog = try membership("dog", mode: .read, number: 2)
        let cat = try membership("cat", mode: .read, number: 3)
        let plan = PresetWordSelectionPlanner().plan(
            selectedWords: ["dog", "cat"],
            destination: .both,
            existingReadWords: [],
            existingWriteWords: []
        )
        var submittedModes: [LearningMode] = []
        var rollbackRequests: [GuardianPresetRollbackRequest] = []

        let outcome = await GuardianPresetImportCoordinator().execute(
            profileID: profileID,
            plan: plan,
            submit: { submittedProfileID, request in
                XCTAssertEqual(submittedProfileID, profileID)
                submittedModes.append(request.learningMode)
                guard request.learningMode == .read else { return nil }
                return GuardianWordImportReport(
                    profileID: profileID,
                    learningMode: .read,
                    insertedMemberships: [dog, cat],
                    reactivatedMemberships: [],
                    alreadyActiveMemberships: [],
                    rejected: []
                )
            },
            rollback: { request in
                rollbackRequests.append(request)
                return true
            }
        )

        XCTAssertEqual(submittedModes, [.read, .write])
        XCTAssertEqual(
            rollbackRequests,
            [
                GuardianPresetRollbackRequest(
                    profileID: profileID,
                    learningMode: .read,
                    membershipIDs: [cat.entryID, dog.entryID]
                )
            ]
        )
        XCTAssertEqual(outcome, .failure(.rolledBack))
        XCTAssertEqual(
            GuardianPresetImportFailure.rolledBack.message,
            "The selected words could not be added to every pool, so this Add was rolled back. Try again."
        )
    }

    func testBothFailureRestoresActualStoreToItsPreImportState() async throws {
        let repository = InMemoryWordPoolRepository()
        let profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            schoolGrade: .preK,
            ageYears: 4,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let store = RepositoryGuardianWordStore(
            profile: profile,
            wordPoolRepository: repository,
            practiceSettingsRepository: InMemoryPracticeSettingsRepository(),
            clock: PresetImportFixedClock()
        )
        let plan = PresetWordSelectionPlanner().plan(
            selectedWords: ["dog", "cat"],
            destination: .both,
            existingReadWords: [],
            existingWriteWords: []
        )

        let outcome = await GuardianPresetImportCoordinator().execute(
            profileID: profile.id,
            plan: plan,
            submit: { submittedProfileID, request in
                XCTAssertEqual(submittedProfileID, profile.id)
                guard request.learningMode == .read else { return nil }
                return try? await store.importWords(request)
            },
            rollback: { request in
                XCTAssertEqual(request.profileID, profile.id)
                do {
                    try await store.setMembershipsActive(
                        ids: request.membershipIDs,
                        learningMode: request.learningMode,
                        isActive: false
                    )
                    return true
                } catch {
                    return false
                }
            }
        )

        XCTAssertEqual(outcome, .failure(.rolledBack))
        let finalSnapshot = try await store.dashboardSnapshot()
        XCTAssertTrue(finalSnapshot.readPool.isEmpty)
        XCTAssertTrue(finalSnapshot.writePool.isEmpty)
        let readRecords = try await repository.entries(
            for: profile.id,
            learningMode: .read,
            includingInactive: true
        )
        XCTAssertEqual(readRecords.map(\.normalizedText), ["dog", "cat"])
        XCTAssertTrue(readRecords.allSatisfy { !$0.isActive })
    }

    func testPartialSecondPoolReportRollsBackBothPoolsInReverseOrder() async throws {
        let profileID = ProfileID()
        let readDog = try membership("dog", mode: .read, number: 4)
        let readCat = try membership("cat", mode: .read, number: 5)
        let writeDog = try membership("dog", mode: .write, number: 6)
        let plan = PresetWordSelectionPlanner().plan(
            selectedWords: ["dog", "cat"],
            destination: .both,
            existingReadWords: [],
            existingWriteWords: []
        )
        var rollbackRequests: [GuardianPresetRollbackRequest] = []

        let outcome = await GuardianPresetImportCoordinator().execute(
            profileID: profileID,
            plan: plan,
            submit: { submittedProfileID, request in
                XCTAssertEqual(submittedProfileID, profileID)
                if request.learningMode == .read {
                    return GuardianWordImportReport(
                        profileID: profileID,
                        learningMode: .read,
                        insertedMemberships: [readDog, readCat],
                        reactivatedMemberships: [],
                        alreadyActiveMemberships: [],
                        rejected: []
                    )
                }
                return GuardianWordImportReport(
                    profileID: profileID,
                    learningMode: .write,
                    insertedMemberships: [writeDog],
                    reactivatedMemberships: [],
                    alreadyActiveMemberships: [],
                    rejected: [
                        GuardianRejectedWord(
                            sourceText: "cat",
                            reason: "Injected rejection"
                        )
                    ]
                )
            },
            rollback: { request in
                rollbackRequests.append(request)
                return true
            }
        )

        XCTAssertEqual(
            rollbackRequests,
            [
                GuardianPresetRollbackRequest(
                    profileID: profileID,
                    learningMode: .write,
                    membershipIDs: [writeDog.entryID]
                ),
                GuardianPresetRollbackRequest(
                    profileID: profileID,
                    learningMode: .read,
                    membershipIDs: [readCat.entryID, readDog.entryID]
                ),
            ]
        )
        XCTAssertEqual(outcome, .failure(.rolledBack))
    }

    func testRollbackFailureReportsManualReviewInsteadOfClaimingConsistency()
        async throws
    {
        let profileID = ProfileID()
        let dog = try membership("dog", mode: .read, number: 7)
        let plan = PresetWordSelectionPlanner().plan(
            selectedWords: ["dog"],
            destination: .both,
            existingReadWords: [],
            existingWriteWords: []
        )

        let outcome = await GuardianPresetImportCoordinator().execute(
            profileID: profileID,
            plan: plan,
            submit: { submittedProfileID, request in
                XCTAssertEqual(submittedProfileID, profileID)
                guard request.learningMode == .read else { return nil }
                return GuardianWordImportReport(
                    profileID: profileID,
                    learningMode: .read,
                    insertedMemberships: [dog],
                    reactivatedMemberships: [],
                    alreadyActiveMemberships: [],
                    rejected: []
                )
            },
            rollback: { _ in false }
        )

        XCTAssertEqual(outcome, .failure(.rollbackFailed))
        XCTAssertTrue(
            GuardianPresetImportFailure.rollbackFailed.message.contains("Manage Words")
        )
    }
}

private func membership(
    _ word: String,
    mode: LearningMode,
    number: Int
) throws -> GuardianWordPoolMembership {
    let suffix = String(format: "%012X", number)
    return GuardianWordPoolMembership(
        entryID: WordPoolEntryID(
            rawValue: UUID(
                uuidString: "92000000-0000-0000-0000-\(suffix)"
            )!
        ),
        promptID: try WordPrompt(learningMode: mode, text: word).id,
        normalizedText: try EnglishWordNormalizer.normalize(word)
    )
}

private struct PresetImportFixedClock: AppClock {
    let now = Date(timeIntervalSince1970: 2)
}
