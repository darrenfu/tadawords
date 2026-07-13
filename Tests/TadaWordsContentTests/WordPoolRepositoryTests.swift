import TadaWordsContent
import TadaWordsDomain
import XCTest

final class WordPoolRepositoryTests: XCTestCase {
    func testNewestQueuedWordsAppearFirstAndBatchOrderStaysStable() async throws {
        let repository = InMemoryWordPoolRepository()
        let importer = ManualWordPoolImporter(repository: repository)
        _ = try await importer.importBatch(
            "old",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: ContentTestFixture.day.addingTimeInterval(-60)
        )
        _ = try await importer.importBatch(
            "zebra apple",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: ContentTestFixture.day
        )

        let entries = try await repository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: false
        )

        XCTAssertEqual(entries.map(\.normalizedText), ["zebra", "apple", "old"])
    }

    func testBatchActivationValidatesEveryIDBeforeMutating() async throws {
        let repository = InMemoryWordPoolRepository()
        let result = try await ManualWordPoolImporter(repository: repository).importBatch(
            "cat dog",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: ContentTestFixture.day
        )
        let cat = try XCTUnwrap(result.inserted.first)

        do {
            _ = try await repository.setActive(
                false,
                entryIDs: [cat.id, ContentTestFixture.entryID(999)]
            )
            XCTFail("Expected a missing-entry failure")
        } catch {
            XCTAssertEqual(
                error as? WordPoolRepositoryError,
                .entryNotFound(ContentTestFixture.entryID(999))
            )
        }

        let active = try await repository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: false
        )
        XCTAssertEqual(active.count, 2)
    }

    func testLegacyRecommendedEntriesNeverEnterTheActiveParentPool() async throws {
        let repository = InMemoryWordPoolRepository()
        let recommendation = WordPoolEntryDraft(
            profileID: ContentTestFixture.profileID,
            prompt: try WordPrompt(learningMode: .read, text: "legacy"),
            addedAt: ContentTestFixture.day,
            source: .gradeRecommendation,
            positionInBatch: 0
        )
        _ = try await repository.upsert([recommendation])

        let active = try await repository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: false
        )
        let history = try await repository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: true
        )

        XCTAssertTrue(active.isEmpty)
        XCTAssertEqual(history.map(\.normalizedText), ["legacy"])
    }

    func testReenteringWordPreservesStableIdentityAndReactivatesIt() async throws {
        let repository = InMemoryWordPoolRepository()
        let importer = ManualWordPoolImporter(repository: repository)
        let firstDate = ContentTestFixture.day.addingTimeInterval(-86_400)
        let secondDate = ContentTestFixture.day

        let first = try await importer.importBatch(
            "Cat",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: firstDate
        )
        let original = try XCTUnwrap(first.inserted.first)
        _ = try await repository.setActive(false, entryID: original.id)

        let second = try await importer.importBatch(
            " cat ",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: secondDate,
            source: .gradeRecommendation
        )
        let requeued = try XCTUnwrap(second.requeuedExisting.first)

        XCTAssertEqual(requeued.id, original.id)
        XCTAssertEqual(requeued.prompt.id, original.prompt.id)
        XCTAssertEqual(requeued.addedAt, firstDate)
        XCTAssertEqual(requeued.source, .guardianManual)
        XCTAssertEqual(requeued.lastQueuedAt, secondDate)
        XCTAssertTrue(requeued.isActive)
    }

    func testSameWordCanExistAcrossProfilesAndModes() async throws {
        let repository = InMemoryWordPoolRepository()
        let importer = ManualWordPoolImporter(repository: repository)

        let read = try await importer.importBatch(
            "cat",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: ContentTestFixture.day
        )
        let write = try await importer.importBatch(
            "cat",
            profileID: ContentTestFixture.profileID,
            learningMode: .write,
            addedAt: ContentTestFixture.day
        )
        let otherProfile = try await importer.importBatch(
            "cat",
            profileID: ContentTestFixture.secondProfileID,
            learningMode: .read,
            addedAt: ContentTestFixture.day
        )

        let entries = [
            try XCTUnwrap(read.inserted.first),
            try XCTUnwrap(write.inserted.first),
            try XCTUnwrap(otherProfile.inserted.first),
        ]
        XCTAssertEqual(Set(entries.map(\.normalizedText)), ["cat"])
        XCTAssertEqual(Set(entries.map(\.id)).count, 3)
        XCTAssertEqual(Set(entries.map(\.prompt.id)).count, 3)
    }

    func testConcurrentUpsertsRemainAtomicallyDeduplicated() async throws {
        let repository = InMemoryWordPoolRepository()
        let importer = ManualWordPoolImporter(repository: repository)

        let returnedIDs = await withTaskGroup(
            of: WordPoolEntryID?.self,
            returning: [WordPoolEntryID].self
        ) { group in
            for offset in 0..<20 {
                group.addTask {
                    let result = try? await importer.importBatch(
                        "cat",
                        profileID: ContentTestFixture.profileID,
                        learningMode: .read,
                        addedAt: ContentTestFixture.day.addingTimeInterval(Double(offset))
                    )
                    return result?.inserted.first?.id
                        ?? result?.requeuedExisting.first?.id
                }
            }

            var ids: [WordPoolEntryID] = []
            for await id in group {
                if let id { ids.append(id) }
            }
            return ids
        }

        let storedEntries = try await repository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: true
        )
        XCTAssertEqual(returnedIDs.count, 20)
        XCTAssertEqual(Set(returnedIDs).count, 1)
        XCTAssertEqual(storedEntries.count, 1)
        XCTAssertEqual(
            storedEntries.first?.lastQueuedAt,
            ContentTestFixture.day.addingTimeInterval(19)
        )
    }

    func testUnknownEntryActivationFailsWithTypedError() async {
        let repository = InMemoryWordPoolRepository()
        let missingID = ContentTestFixture.entryID(999)

        do {
            _ = try await repository.setActive(true, entryID: missingID)
            XCTFail("Expected a typed missing-entry error")
        } catch {
            XCTAssertEqual(
                error as? WordPoolRepositoryError,
                .entryNotFound(missingID)
            )
        }
    }

    func testImporterStoresValidWordsAndReturnsInvalidOnes() async throws {
        let repository = InMemoryWordPoolRepository()
        let result = try await ManualWordPoolImporter(
            repository: repository
        ).importBatch(
            "cat, 123, dog",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: ContentTestFixture.day
        )

        XCTAssertEqual(result.inserted.map(\.normalizedText), ["cat", "dog"])
        XCTAssertEqual(
            result.rejected.map(\.reason),
            [.invalidPrompt(.unsupportedCharacters)]
        )
    }

    func testDecodingReappliesEntryInvariants() throws {
        let entry = try ContentTestFixture.entry(
            "cat",
            number: 1,
            addedAt: ContentTestFixture.day,
            position: 2
        )
        let encoded = try JSONEncoder().encode(entry)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let encodedAddedAt = try XCTUnwrap(object["addedAt"] as? NSNumber)
        object["lastQueuedAt"] = encodedAddedAt.doubleValue - 10_000
        object["positionInLastBatch"] = -4

        let invalidData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(
            WordPoolEntry.self,
            from: invalidData
        )

        XCTAssertEqual(decoded.lastQueuedAt, decoded.addedAt)
        XCTAssertEqual(decoded.positionInLastBatch, 0)
    }
}
