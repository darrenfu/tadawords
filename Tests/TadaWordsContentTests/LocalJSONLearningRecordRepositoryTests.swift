import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class LocalJSONLearningRecordRepositoryTests: XCTestCase {
    func testMissingFileReadsEmptyAndFirstAppendCreatesInspectableSnapshot()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONLearningRecordRepository(
            snapshotURL: snapshotURL
        )

        let attempts = try await repository.attempts(
            for: ContentTestFixture.profileID,
            wordPromptID: nil
        )
        let progress = try await repository.progress(
            for: ContentTestFixture.profileID,
            wordPromptID: ContentTestFixture.wordID(1)
        )
        XCTAssertTrue(attempts.isEmpty)
        XCTAssertNil(progress)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))

        try await repository.append(attempt(number: 1))

        let text = try String(contentsOf: snapshotURL, encoding: .utf8)
        XCTAssertTrue(text.contains("\"schemaVersion\""))
        XCTAssertTrue(text.contains("\"attempts\""))
        XCTAssertTrue(text.contains("\"corrections\""))
        XCTAssertTrue(text.contains("\"progress\""))
    }

    func testRestartPreservesRecordsAndDeterministicRetrieval() async throws {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONLearningRecordRepository(
            snapshotURL: snapshotURL
        )
        let late = attempt(
            number: 2,
            wordNumber: 1,
            at: ContentTestFixture.day.addingTimeInterval(20)
        )
        let early = attempt(
            number: 1,
            wordNumber: 1,
            at: ContentTestFixture.day.addingTimeInterval(10)
        )
        let write = attempt(
            number: 3,
            wordNumber: 2,
            mode: .write,
            at: ContentTestFixture.day.addingTimeInterval(15)
        )
        let otherProfile = attempt(
            number: 4,
            profileID: ContentTestFixture.secondProfileID,
            wordNumber: 1,
            at: ContentTestFixture.day.addingTimeInterval(5)
        )
        for event in [late, otherProfile, write, early] {
            try await repository.append(event)
        }

        let laterCorrection = correction(
            number: 2,
            attemptID: early.id,
            at: ContentTestFixture.day.addingTimeInterval(40)
        )
        let earlierCorrection = correction(
            number: 1,
            attemptID: early.id,
            outcome: .incorrect,
            at: ContentTestFixture.day.addingTimeInterval(30)
        )
        try await repository.append(laterCorrection)
        try await repository.append(earlierCorrection)

        let readProgress = progress(
            profileID: ContentTestFixture.profileID,
            wordNumber: 1,
            mode: .read,
            correctCount: 2
        )
        let writeProgress = progress(
            profileID: ContentTestFixture.profileID,
            wordNumber: 2,
            mode: .write,
            correctCount: 1
        )
        let otherProgress = progress(
            profileID: ContentTestFixture.secondProfileID,
            wordNumber: 1,
            mode: .read,
            correctCount: 1
        )
        try await repository.save(readProgress)
        try await repository.save(writeProgress)
        try await repository.save(otherProgress)

        let restarted = LocalJSONLearningRecordRepository(
            snapshotURL: snapshotURL
        )
        let restoredAttempts = try await restarted.attempts(
            for: ContentTestFixture.profileID,
            wordPromptID: nil
        )
        let restoredWordAttempts = try await restarted.attempts(
            for: ContentTestFixture.profileID,
            wordPromptID: ContentTestFixture.wordID(1)
        )
        let restoredCorrections = try await restarted.corrections(
            for: early.id
        )
        let restoredReadProgress = try await restarted.progress(
            for: ContentTestFixture.profileID,
            wordPromptID: ContentTestFixture.wordID(1)
        )
        let restoredWriteProgress = try await restarted.progress(
            for: ContentTestFixture.profileID,
            wordPromptID: ContentTestFixture.wordID(2),
            learningMode: .write
        )
        let restoredOtherProgress = try await restarted.progress(
            for: ContentTestFixture.secondProfileID,
            wordPromptID: ContentTestFixture.wordID(1)
        )

        XCTAssertEqual(restoredAttempts, [early, write, late])
        XCTAssertEqual(restoredWordAttempts, [early, late])
        XCTAssertEqual(
            restoredCorrections,
            [earlierCorrection, laterCorrection]
        )
        XCTAssertEqual(
            restoredReadProgress?.firstIndependentCorrectCount,
            readProgress.firstIndependentCorrectCount
        )
        XCTAssertEqual(
            restoredWriteProgress?.firstIndependentCorrectCount,
            writeProgress.firstIndependentCorrectCount
        )
        XCTAssertEqual(
            restoredOtherProgress?.firstIndependentCorrectCount,
            otherProgress.firstIndependentCorrectCount
        )
        XCTAssertEqual(restoredReadProgress?.firstIndependentAttemptCount, 2)
        XCTAssertEqual(restoredWriteProgress?.firstIndependentAttemptCount, 1)
        XCTAssertEqual(restoredOtherProgress?.firstIndependentAttemptCount, 1)
    }

    func testIdenticalAppendsAndSavesAreIdempotentButConflictsFail()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONLearningRecordRepository(
            snapshotURL: snapshotURL
        )
        let event = attempt(number: 1, outcome: .incorrect)
        let appendedCorrection = correction(
            number: 1,
            attemptID: event.id
        )
        let savedProgress = progress(correctCount: 1)

        try await repository.append(event)
        try await repository.append(appendedCorrection)
        try await repository.save(savedProgress)
        let originalData = try Data(contentsOf: snapshotURL)

        try await repository.append(event)
        try await repository.append(appendedCorrection)
        try await repository.save(savedProgress)
        XCTAssertEqual(try Data(contentsOf: snapshotURL), originalData)
        let storedAttempts = try await repository.attempts(
            for: ContentTestFixture.profileID,
            wordPromptID: event.wordPromptID
        )
        let storedCorrections = try await repository.corrections(
            for: event.id
        )
        XCTAssertEqual(storedAttempts, [event])
        XCTAssertEqual(storedCorrections, [appendedCorrection])

        let conflictingEvent = AttemptEvent(
            id: event.id,
            questID: event.questID,
            profileID: event.profileID,
            wordPromptID: event.wordPromptID,
            learningMode: event.learningMode,
            evidence: event.evidence,
            outcome: .correct,
            occurredAt: event.occurredAt
        )
        do {
            try await repository.append(conflictingEvent)
            XCTFail("Expected conflicting attempt ID")
        } catch {
            XCTAssertEqual(
                error as? LearningRecordRepositoryError,
                .conflictingAttemptID(event.id)
            )
        }

        let conflictingCorrection = AttemptCorrectionEvent(
            id: appendedCorrection.id,
            originalAttemptID: appendedCorrection.originalAttemptID,
            correctedOutcome: .incorrect,
            reason: .guardianOverride,
            correctedAt: appendedCorrection.correctedAt
        )
        do {
            try await repository.append(conflictingCorrection)
            XCTFail("Expected conflicting correction ID")
        } catch {
            XCTAssertEqual(
                error as? LearningRecordRepositoryError,
                .conflictingCorrectionID(appendedCorrection.id)
            )
        }
        XCTAssertEqual(try Data(contentsOf: snapshotURL), originalData)
    }

    func testCorrectionNeverRewritesOriginalAndMayArriveFirst() async throws {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONLearningRecordRepository(
            snapshotURL: snapshotURL
        )
        let original = attempt(number: 1, outcome: .incorrect)
        let appendedCorrection = correction(
            number: 1,
            attemptID: original.id,
            outcome: .correct
        )

        try await repository.append(appendedCorrection)
        try await repository.append(original)

        let restarted = LocalJSONLearningRecordRepository(
            snapshotURL: snapshotURL
        )
        let restoredAttempts = try await restarted.attempts(
            for: original.profileID,
            wordPromptID: original.wordPromptID
        )
        let restoredOriginal = try XCTUnwrap(restoredAttempts.first)
        let restoredCorrections = try await restarted.corrections(
            for: original.id
        )
        XCTAssertEqual(restoredOriginal.outcome, .incorrect)
        XCTAssertEqual(restoredCorrections, [appendedCorrection])
    }

    func testGuardedRepositoryRejectsStaleCorrectionAfterProfileDeletion()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let mutationGate = ProfileScopedMutationGate()
        let repository = LocalJSONLearningRecordRepository(
            snapshotURL: snapshotURL,
            mutationGate: mutationGate
        )
        let original = attempt(number: 1, outcome: .incorrect)
        let staleCorrection = correction(
            number: 1,
            attemptID: original.id,
            outcome: .correct
        )
        try await repository.append(original)

        try await withProfileScopedMutationLease(
            mutationGate,
            for: original.profileID,
            allowingTerminal: true,
            isolation: mutationGate
        ) {
            await mutationGate.seal(original.profileID)
            try await repository.deleteLearningRecords(for: original.profileID)
        }
        let bytesAfterDeletion = try Data(contentsOf: snapshotURL)

        do {
            try await repository.append(staleCorrection)
            XCTFail("A stale correction must not recreate deleted learning data.")
        } catch {
            XCTAssertEqual(
                error as? LearningRecordRepositoryError,
                .missingCorrectionRoute(original.id)
            )
        }

        XCTAssertEqual(try Data(contentsOf: snapshotURL), bytesAfterDeletion)
        let restarted = LocalJSONLearningRecordRepository(
            snapshotURL: snapshotURL,
            mutationGate: mutationGate
        )
        let corrections = try await restarted.corrections(for: original.id)
        let route = try await restarted.correctionRoute(for: original.id)
        XCTAssertEqual(corrections, [])
        XCTAssertNil(route)
    }

    func testAppendAtomicallyRebuildsProgressWithoutAnExplicitSave()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONLearningRecordRepository(
            snapshotURL: snapshotURL
        )
        let original = attempt(number: 1, outcome: .incorrect)

        try await repository.append(original)
        let initiallyDerivedValue = try await repository.progress(
            for: original.profileID,
            wordPromptID: original.wordPromptID
        )
        let initiallyDerived = try XCTUnwrap(initiallyDerivedValue)
        XCTAssertEqual(initiallyDerived.firstIndependentAttemptCount, 1)
        XCTAssertEqual(initiallyDerived.firstIndependentCorrectCount, 0)

        try await repository.append(
            correction(
                number: 1,
                attemptID: original.id,
                outcome: .correct,
                at: ContentTestFixture.day.addingTimeInterval(1)
            )
        )

        let restarted = LocalJSONLearningRecordRepository(
            snapshotURL: snapshotURL
        )
        let correctedValue = try await restarted.progress(
            for: original.profileID,
            wordPromptID: original.wordPromptID
        )
        let corrected = try XCTUnwrap(correctedValue)
        XCTAssertEqual(corrected.firstIndependentAttemptCount, 1)
        XCTAssertEqual(corrected.firstIndependentCorrectCount, 1)

        let migratedData = try Data(contentsOf: snapshotURL)
        let migrated = try snapshotDecoder.decode(
            LearningRecordSnapshot.self,
            from: migratedData
        )
        XCTAssertEqual(
            migrated.schemaVersion,
            LearningRecordSnapshot.currentSchemaVersion
        )
        XCTAssertEqual(
            migrated.projectionAlgorithmVersion,
            LearningRecordSnapshot.currentProjectionAlgorithmVersion
        )
        XCTAssertEqual(migrated.canonicalFactsChecksum.count, 64)
    }

    func testVersionOneSnapshotDropsStaleProgressAndMigratesAtomically()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let original = attempt(number: 1, outcome: .correct)
        let staleProgress = progress(correctCount: 0)
        let versionOne = LearningRecordSnapshot(
            schemaVersion: 1,
            attempts: [original],
            corrections: [],
            progress: [staleProgress]
        )
        try encodeSnapshot(versionOne).write(to: snapshotURL)

        let repository = LocalJSONLearningRecordRepository(
            snapshotURL: snapshotURL
        )
        let rebuiltValue = try await repository.progress(
            for: original.profileID,
            wordPromptID: original.wordPromptID
        )
        let rebuilt = try XCTUnwrap(rebuiltValue)
        XCTAssertEqual(rebuilt.firstIndependentAttemptCount, 1)
        XCTAssertEqual(rebuilt.firstIndependentCorrectCount, 1)
        XCTAssertNotEqual(rebuilt, staleProgress)

        let migratedData = try Data(contentsOf: snapshotURL)
        let migrated = try snapshotDecoder.decode(
            LearningRecordSnapshot.self,
            from: migratedData
        )
        XCTAssertEqual(
            migrated.schemaVersion,
            LearningRecordSnapshot.currentSchemaVersion
        )
        let persistedProgress = try XCTUnwrap(migrated.progress.first)
        XCTAssertEqual(migrated.progress.count, 1)
        XCTAssertEqual(
            persistedProgress.firstIndependentAttemptCount,
            rebuilt.firstIndependentAttemptCount
        )
        XCTAssertEqual(
            persistedProgress.firstIndependentCorrectCount,
            rebuilt.firstIndependentCorrectCount
        )
        XCTAssertEqual(migrated.canonicalFactsChecksum.count, 64)

        let restarted = LocalJSONLearningRecordRepository(
            snapshotURL: snapshotURL
        )
        _ = try await restarted.attempts(
            for: original.profileID,
            wordPromptID: nil
        )
        XCTAssertEqual(try Data(contentsOf: snapshotURL), migratedData)
    }

    func testProjectionMetadataMismatchRebuildsStaleVersionTwoProgress()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let original = attempt(number: 1, outcome: .correct)
        let stale = LearningRecordSnapshot(
            projectionAlgorithmVersion: 0,
            canonicalFactsChecksum: "stale",
            attempts: [original],
            corrections: [],
            progress: [progress(correctCount: 0)]
        )
        try encodeSnapshot(stale).write(to: snapshotURL)

        let repository = LocalJSONLearningRecordRepository(
            snapshotURL: snapshotURL
        )
        let rebuiltValue = try await repository.progress(
            for: original.profileID,
            wordPromptID: original.wordPromptID
        )
        let rebuilt = try XCTUnwrap(rebuiltValue)
        XCTAssertEqual(rebuilt.firstIndependentCorrectCount, 1)

        let repaired = try snapshotDecoder.decode(
            LearningRecordSnapshot.self,
            from: Data(contentsOf: snapshotURL)
        )
        XCTAssertEqual(
            repaired.projectionAlgorithmVersion,
            LearningRecordSnapshot.currentProjectionAlgorithmVersion
        )
        XCTAssertNotEqual(repaired.canonicalFactsChecksum, "stale")
    }

    func testForgedStaleProjectionWithMatchingFactsMetadataIsRebuilt()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let original = attempt(number: 1, outcome: .correct)
        let writer = LocalJSONLearningRecordRepository(snapshotURL: snapshotURL)
        try await writer.append(original)

        let canonical = try snapshotDecoder.decode(
            LearningRecordSnapshot.self,
            from: Data(contentsOf: snapshotURL)
        )
        let forgedProgress = progress(correctCount: 0)
        let forged = LearningRecordSnapshot(
            schemaVersion: canonical.schemaVersion,
            projectionAlgorithmVersion: canonical.projectionAlgorithmVersion,
            canonicalFactsChecksum: canonical.canonicalFactsChecksum,
            attempts: canonical.attempts,
            corrections: canonical.corrections,
            progress: [forgedProgress]
        )
        try encodeSnapshot(forged).write(to: snapshotURL)

        let reader = LocalJSONLearningRecordRepository(snapshotURL: snapshotURL)
        let repairedValue = try await reader.progress(
            for: original.profileID,
            wordPromptID: original.wordPromptID
        )
        let repaired = try XCTUnwrap(repairedValue)
        XCTAssertEqual(repaired.firstIndependentAttemptCount, 1)
        XCTAssertEqual(repaired.firstIndependentCorrectCount, 1)
        XCTAssertNotEqual(repaired, forgedProgress)

        let persisted = try snapshotDecoder.decode(
            LearningRecordSnapshot.self,
            from: Data(contentsOf: snapshotURL)
        )
        XCTAssertEqual(persisted.progress.count, 1)
        XCTAssertEqual(
            persisted.progress.first?.firstIndependentCorrectCount,
            1
        )
    }

    func testCanonicalEventPermutationsProduceByteEquivalentSnapshots()
        async throws
    {
        let firstURL = try makeSnapshotURL()
        let secondURL = try makeSnapshotURL()
        let first = LocalJSONLearningRecordRepository(snapshotURL: firstURL)
        let second = LocalJSONLearningRecordRepository(snapshotURL: secondURL)
        let incorrect = attempt(
            number: 1,
            outcome: .incorrect,
            at: ContentTestFixture.day
        )
        let correct = attempt(
            number: 2,
            outcome: .correct,
            at: ContentTestFixture.day.addingTimeInterval(2)
        )
        let override = correction(
            number: 1,
            attemptID: incorrect.id,
            outcome: .correct,
            at: ContentTestFixture.day.addingTimeInterval(1)
        )

        try await first.append(incorrect)
        try await first.append(correct)
        try await first.append(override)

        try await second.append(override)
        try await second.append(correct)
        try await second.append(incorrect)

        XCTAssertEqual(
            try Data(contentsOf: firstURL),
            try Data(contentsOf: secondURL)
        )
        let finalProgressValue = try await second.progress(
            for: incorrect.profileID,
            wordPromptID: incorrect.wordPromptID
        )
        let finalProgress = try XCTUnwrap(finalProgressValue)
        XCTAssertEqual(finalProgress.firstIndependentAttemptCount, 2)
        XCTAssertEqual(finalProgress.firstIndependentCorrectCount, 2)
    }

    func testProgressIsProfileWordAndModeSafe() async throws {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONLearningRecordRepository(
            snapshotURL: snapshotURL
        )
        let readProgress = progress(mode: .read, correctCount: 1)
        let updatedReadProgress = progress(mode: .read, correctCount: 2)
        try await repository.save(readProgress)
        try await repository.save(updatedReadProgress)

        let conflictingWriteProgress = progress(mode: .write, correctCount: 1)
        do {
            try await repository.save(conflictingWriteProgress)
            XCTFail("Expected a mode conflict for the same profile and word ID")
        } catch {
            XCTAssertEqual(
                error as? LearningRecordRepositoryError,
                .conflictingProgressMode(
                    profileID: ContentTestFixture.profileID,
                    wordPromptID: ContentTestFixture.wordID(1),
                    existingMode: .read,
                    incomingMode: .write
                )
            )
        }

        let otherProfileProgress = progress(
            profileID: ContentTestFixture.secondProfileID,
            mode: .write,
            correctCount: 1
        )
        try await repository.save(otherProfileProgress)

        let restoredReadProgress = try await repository.progress(
            for: ContentTestFixture.profileID,
            wordPromptID: ContentTestFixture.wordID(1)
        )
        let absentWriteProgress = try await repository.progress(
            for: ContentTestFixture.profileID,
            wordPromptID: ContentTestFixture.wordID(1),
            learningMode: .write
        )
        let restoredOtherProgress = try await repository.progress(
            for: ContentTestFixture.secondProfileID,
            wordPromptID: ContentTestFixture.wordID(1)
        )
        XCTAssertEqual(restoredReadProgress, updatedReadProgress)
        XCTAssertNil(absentWriteProgress)
        XCTAssertEqual(restoredOtherProgress, otherProfileProgress)
    }

    func testCorruptFileIsPreservedLatchedAndReloadableAfterRepair()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let corruptData = Data("not valid json".utf8)
        try corruptData.write(to: snapshotURL)
        let repository = LocalJSONLearningRecordRepository(
            snapshotURL: snapshotURL
        )

        await assertInvalidJSON {
            _ = try await repository.attempts(
                for: ContentTestFixture.profileID,
                wordPromptID: nil
            )
        }
        await assertInvalidJSON {
            try await repository.append(self.attempt(number: 1))
        }
        XCTAssertEqual(try Data(contentsOf: snapshotURL), corruptData)

        try encodeSnapshot(emptySnapshot).write(to: snapshotURL)
        await assertInvalidJSON {
            _ = try await repository.attempts(
                for: ContentTestFixture.profileID,
                wordPromptID: nil
            )
        }
        try await repository.reloadFromDisk()
        let recoveredAttempts = try await repository.attempts(
            for: ContentTestFixture.profileID,
            wordPromptID: nil
        )
        XCTAssertTrue(recoveredAttempts.isEmpty)
    }

    func testWriteFailureDoesNotCommitAttemptOrProgress() async throws {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONLearningRecordRepository(
            snapshotURL: snapshotURL
        )
        _ = try await repository.attempts(
            for: ContentTestFixture.profileID,
            wordPromptID: nil
        )

        let blockingParent = snapshotURL.deletingLastPathComponent()
        try FileManager.default.removeItem(at: blockingParent)
        try Data("preserve".utf8).write(to: blockingParent)

        do {
            try await repository.append(attempt(number: 1))
            XCTFail("Expected write failure")
        } catch let error as LocalLearningRecordRepositoryError {
            guard case .writeFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        do {
            try await repository.save(progress(correctCount: 1))
            XCTFail("Expected write failure")
        } catch let error as LocalLearningRecordRepositoryError {
            guard case .writeFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let storedAttempts = try await repository.attempts(
            for: ContentTestFixture.profileID,
            wordPromptID: nil
        )
        let storedProgress = try await repository.progress(
            for: ContentTestFixture.profileID,
            wordPromptID: ContentTestFixture.wordID(1)
        )
        XCTAssertTrue(storedAttempts.isEmpty)
        XCTAssertNil(storedProgress)
        XCTAssertEqual(
            try Data(contentsOf: blockingParent),
            Data("preserve".utf8)
        )
    }

    func testConcurrentAppendsAreDurableAndDeterministic() async throws {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONLearningRecordRepository(
            snapshotURL: snapshotURL
        )
        let events = (0..<32).map { number in
            attempt(
                number: number + 1,
                wordNumber: (number % 3) + 1,
                at: ContentTestFixture.day.addingTimeInterval(
                    Double(31 - number)
                )
            )
        }

        let successCount = await withTaskGroup(
            of: Bool.self,
            returning: Int.self
        ) { group in
            for event in events {
                group.addTask {
                    do {
                        try await repository.append(event)
                        try await repository.append(event)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            var count = 0
            for await succeeded in group where succeeded {
                count += 1
            }
            return count
        }
        XCTAssertEqual(successCount, events.count)

        let restarted = LocalJSONLearningRecordRepository(
            snapshotURL: snapshotURL
        )
        let restored = try await restarted.attempts(
            for: ContentTestFixture.profileID,
            wordPromptID: nil
        )
        XCTAssertEqual(restored.count, events.count)
        XCTAssertEqual(
            restored.map(\.occurredAt),
            events.map(\.occurredAt).sorted()
        )
    }

    func testInvalidDuplicateSnapshotIsNeverOverwritten() async throws {
        let snapshotURL = try makeSnapshotURL()
        let duplicatedEvent = attempt(number: 1)
        let invalidSnapshot = LearningRecordSnapshot(
            attempts: [duplicatedEvent, duplicatedEvent],
            corrections: [],
            progress: []
        )
        let invalidData = try encodeSnapshot(invalidSnapshot)
        try invalidData.write(to: snapshotURL)
        let repository = LocalJSONLearningRecordRepository(
            snapshotURL: snapshotURL
        )

        do {
            _ = try await repository.attempts(
                for: ContentTestFixture.profileID,
                wordPromptID: nil
            )
            XCTFail("Expected invalid snapshot")
        } catch let error as LocalLearningRecordRepositoryError {
            guard case .invalidSnapshot(_, .duplicateAttemptID) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: snapshotURL), invalidData)
    }

    private var emptySnapshot: LearningRecordSnapshot {
        LearningRecordSnapshot(
            attempts: [],
            corrections: [],
            progress: []
        )
    }

    private func attempt(
        number: Int,
        profileID: ProfileID = ContentTestFixture.profileID,
        wordNumber: Int = 1,
        mode: LearningMode = .read,
        outcome: AttemptOutcome = .correct,
        at date: Date = ContentTestFixture.day
    ) -> AttemptEvent {
        AttemptEvent(
            id: AttemptID(rawValue: stableUUID(prefix: "71", number: number)),
            questID: QuestID(
                rawValue: stableUUID(prefix: "72", number: number)
            ),
            profileID: profileID,
            wordPromptID: ContentTestFixture.wordID(wordNumber),
            learningMode: mode,
            evidence: .firstIndependentAttempt,
            outcome: outcome,
            timing: AttemptTiming(
                totalResponseTime: ElapsedTime(seconds: Double(number))
            ),
            occurredAt: date,
            replayCount: number % 2
        )
    }

    private func correction(
        number: Int,
        attemptID: AttemptID,
        outcome: AttemptOutcome = .correct,
        at date: Date = ContentTestFixture.day
    ) -> AttemptCorrectionEvent {
        AttemptCorrectionEvent(
            id: AttemptCorrectionID(
                rawValue: stableUUID(prefix: "73", number: number)
            ),
            originalAttemptID: attemptID,
            correctedOutcome: outcome,
            reason: .guardianOverride,
            correctedAt: date
        )
    }

    private func progress(
        profileID: ProfileID = ContentTestFixture.profileID,
        wordNumber: Int = 1,
        mode: LearningMode = .read,
        correctCount: Int
    ) -> WordProgress {
        WordProgress(
            profileID: profileID,
            wordPromptID: ContentTestFixture.wordID(wordNumber),
            learningMode: mode,
            memoryState: MemoryState(
                stabilityDays: Double(correctCount),
                difficulty: 0.4,
                nextReviewAt: ContentTestFixture.day.addingTimeInterval(86_400),
                lastIndependentAttemptAt: ContentTestFixture.day,
                consecutiveIndependentSuccesses: correctCount,
                lapseCount: 0
            ),
            firstIndependentAttemptCount: max(1, correctCount),
            firstIndependentCorrectCount: correctCount,
            lastEncounterAt: ContentTestFixture.day
        )
    }

    private func stableUUID(prefix: String, number: Int) -> UUID {
        let suffix = String(format: "%012X", number)
        return UUID(
            uuidString: "\(prefix)000000-0000-0000-0000-\(suffix)"
        )!
    }

    private func makeSnapshotURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TadaWordsLearningRecordTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return directoryURL.appendingPathComponent("learning-records.json")
    }

    private func encodeSnapshot(
        _ snapshot: LearningRecordSnapshot
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    private var snapshotDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    private func assertInvalidJSON(
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected invalid JSON")
        } catch let error as LocalLearningRecordRepositoryError {
            guard case .invalidJSON = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
