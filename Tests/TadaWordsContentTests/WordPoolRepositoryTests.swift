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

    func testReenteringInactiveWordPreservesStableIdentityAndReactivatesIt()
        async throws
    {
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
        let reactivated = try XCTUnwrap(second.reactivated.first)

        XCTAssertEqual(reactivated.id, original.id)
        XCTAssertEqual(reactivated.prompt.id, original.prompt.id)
        XCTAssertEqual(reactivated.addedAt, firstDate)
        XCTAssertEqual(reactivated.source, .guardianManual)
        XCTAssertEqual(reactivated.lastQueuedAt, secondDate)
        XCTAssertTrue(reactivated.isActive)
        XCTAssertTrue(second.alreadyActive.isEmpty)
    }

    func testReenteringActiveWordClassifiesItAndMovesItNewestFirst()
        async throws
    {
        let repository = InMemoryWordPoolRepository()
        let importer = ManualWordPoolImporter(repository: repository)
        let firstDate = ContentTestFixture.day.addingTimeInterval(-120)

        let first = try await importer.importBatch(
            "cat",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: firstDate
        )
        let original = try XCTUnwrap(first.inserted.first)
        _ = try await importer.importBatch(
            "dog",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: ContentTestFixture.day.addingTimeInterval(-60)
        )

        let duplicate = try await importer.importBatch(
            "123 ＣＡＴ",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: ContentTestFixture.day
        )

        let requeued = try XCTUnwrap(duplicate.alreadyActive.first)
        XCTAssertEqual(requeued.id, original.id)
        XCTAssertEqual(requeued.prompt.id, original.prompt.id)
        XCTAssertEqual(requeued.addedAt, original.addedAt)
        XCTAssertEqual(requeued.source, original.source)
        XCTAssertEqual(requeued.lastQueuedAt, ContentTestFixture.day)
        XCTAssertEqual(requeued.positionInLastBatch, 1)
        XCTAssertTrue(requeued.isActive)
        XCTAssertTrue(duplicate.inserted.isEmpty)
        XCTAssertTrue(duplicate.reactivated.isEmpty)
        let entries = try await repository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: true
        )
        XCTAssertEqual(entries.map(\.normalizedText), ["cat", "dog"])
        XCTAssertEqual(entries.first, requeued)
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

        let results = await withTaskGroup(
            of: ManualWordPoolImportResult?.self,
            returning: [ManualWordPoolImportResult].self
        ) { group in
            for offset in 0..<20 {
                group.addTask {
                    let result = try? await importer.importBatch(
                        "cat",
                        profileID: ContentTestFixture.profileID,
                        learningMode: .read,
                        addedAt: ContentTestFixture.day.addingTimeInterval(Double(offset))
                    )
                    return result
                }
            }

            var results: [ManualWordPoolImportResult] = []
            for await result in group {
                if let result { results.append(result) }
            }
            return results
        }

        let inserted = results.flatMap(\.inserted)
        let reactivated = results.flatMap(\.reactivated)
        let alreadyActive = results.flatMap(\.alreadyActive)
        let storedEntries = try await repository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: true
        )
        XCTAssertEqual(results.count, 20)
        XCTAssertEqual(inserted.count, 1)
        XCTAssertTrue(reactivated.isEmpty)
        XCTAssertEqual(alreadyActive.count, 19)
        XCTAssertEqual(Set((inserted + alreadyActive).map(\.id)).count, 1)
        XCTAssertEqual(storedEntries.count, 1)
        XCTAssertEqual(storedEntries.first?.id, inserted.first?.id)
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
