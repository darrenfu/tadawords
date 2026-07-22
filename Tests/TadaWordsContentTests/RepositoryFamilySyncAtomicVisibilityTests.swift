import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsContent

final class RepositoryFamilySyncAtomicVisibilityTests: XCTestCase {
    func testPublicReadsWaitUntilTheWholeAcceptedGenerationCommits()
        async throws
    {
        let fixture = try AtomicVisibilityFixture()
        defer { fixture.remove() }
        try await fixture.seedLocalGeneration()
        let records = try await fixture.remoteGenerationRecords()
        let pause = PausingApplyBoundary(.profile)
        let store = fixture.makeStore { boundary in
            await pause.observe(boundary)
        }
        let applyTask = Task {
            try await store.apply(records, for: fixture.profile.id)
        }
        await pause.waitUntilReached()

        let completion = AsyncCompletionProbe()
        let readTask = Task {
            async let profile = fixture.profiles.profile(id: fixture.profile.id)
            async let settings = fixture.settings.settings(for: fixture.profile.id)
            let values = try await (profile, settings)
            await completion.markCompleted()
            return values
        }
        for _ in 0..<20 { await Task.yield() }
        let completedWhilePartial = await completion.isCompleted()
        XCTAssertFalse(completedWhilePartial)

        await pause.resume()
        try await applyTask.value
        let visible = try await readTask.value

        XCTAssertEqual(visible.0?.displayName, "Remote Complete")
        XCTAssertEqual(visible.1?.audio.voiceEnabled, false)
    }

    func testEveryAcceptedRepositoryBoundaryFailsClosedUntilExactReplayCommits()
        async throws
    {
        let boundaries: [FamilySyncApplyBoundary] = [
            .durableBegin,
            .profile,
            .wordPool,
            .promptAliases,
            .practiceSettings,
            .attempts,
            .corrections,
            .dailyQuest,
        ]

        for boundary in boundaries {
            let fixture = try AtomicVisibilityFixture()
            defer { fixture.remove() }
            try await fixture.seedLocalGeneration()
            let records = try await fixture.remoteGenerationRecords()
            let interruption = OneShotApplyBoundaryInterruption(boundary)
            let store = fixture.makeStore(interruption: interruption)

            do {
                try await store.apply(records, for: fixture.profile.id)
                XCTFail("Expected interruption at \(boundary)")
            } catch let error as AtomicVisibilityInterruption {
                XCTAssertEqual(error, .boundary(boundary))
            }

            try await assertRecoveryClosed(fixture)
            let pending = try await fixture.transactions.pendingTransactions()
            XCTAssertEqual(pending.count, 1)
            XCTAssertEqual(pending.first?.records, records)
            let receiptBeforeRecovery = try await fixture.transactions
                .lastCommittedReceipt(
                    for: fixture.profile.id
                )
            XCTAssertNil(receiptBeforeRecovery)

            try await store.recoverPendingApplies()

            let recoveryTransactionID =
                await fixture.gate.recoveryTransactionID(
                    for: fixture.profile.id
                )
            let pendingAfterRecovery =
                try await fixture.transactions.pendingTransactions()
            XCTAssertNil(recoveryTransactionID)
            XCTAssertTrue(
                pendingAfterRecovery.isEmpty
            )
            let receipt = try await fixture.transactions.lastCommittedReceipt(
                for: fixture.profile.id
            )
            XCTAssertEqual(receipt?.transactionID, pending.first?.id)
            let receiptToken = try await fixture.transactions
                .committedReceiptToken()
            try await store.recoverPendingApplies()
            let receiptTokenAfterNoOpRecovery = try await fixture.transactions
                .committedReceiptToken()
            XCTAssertEqual(receiptTokenAfterNoOpRecovery, receiptToken)
            try await fixture.assertRemoteGenerationVisible()
        }
    }

    func testEveryDeletionBoundaryFailsClosedAndReplayCannotResurrectProfile()
        async throws
    {
        let boundaries: [FamilySyncApplyBoundary] = [
            .deletionTombstone,
            .deletionProfileData,
            .deletionCommitted,
        ]

        for boundary in boundaries {
            let fixture = try AtomicVisibilityFixture()
            defer { fixture.remove() }
            try await fixture.seedLocalGeneration()
            let deletionRecord = try fixture.deletionRecord()
            let interruption = OneShotApplyBoundaryInterruption(boundary)
            let store = fixture.makeStore(interruption: interruption)

            do {
                try await store.apply(
                    [deletionRecord],
                    for: fixture.profile.id
                )
                XCTFail("Expected deletion interruption at \(boundary)")
            } catch let error as AtomicVisibilityInterruption {
                XCTAssertEqual(error, .boundary(boundary))
            }

            try await assertRecoveryClosed(fixture)
            let pending = try await fixture.transactions.pendingTransactions()
            XCTAssertEqual(pending.count, 1)
            let receiptBeforeRecovery = try await fixture.transactions
                .lastCommittedReceipt(
                    for: fixture.profile.id
                )
            XCTAssertNil(receiptBeforeRecovery)
            try await store.recoverPendingApplies()

            let savedProfile = try await fixture.profiles.profile(
                id: fixture.profile.id
            )
            let savedSettings = try await fixture.settings.settings(
                for: fixture.profile.id
            )
            let pendingAfterRecovery =
                try await fixture.transactions.pendingTransactions()
            XCTAssertNil(savedProfile)
            XCTAssertNil(savedSettings)
            XCTAssertTrue(pendingAfterRecovery.isEmpty)
            let receipt = try await fixture.transactions.lastCommittedReceipt(
                for: fixture.profile.id
            )
            XCTAssertEqual(receipt?.transactionID, pending.first?.id)
            let receiptToken = try await fixture.transactions
                .committedReceiptToken()
            try await store.recoverPendingApplies()
            let receiptTokenAfterNoOpRecovery = try await fixture.transactions
                .committedReceiptToken()
            XCTAssertEqual(receiptTokenAfterNoOpRecovery, receiptToken)
            let exported = try await store.records(for: fixture.profile.id)
            XCTAssertEqual(exported.map(\.kind), [.profileDeletion])
            XCTAssertTrue(exported.allSatisfy(\.isDeleted))
        }
    }

    private func assertRecoveryClosed(
        _ fixture: AtomicVisibilityFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let transactionID = await fixture.gate.recoveryTransactionID(
            for: fixture.profile.id
        )
        XCTAssertNotNil(transactionID, file: file, line: line)

        do {
            _ = try await fixture.profiles.profile(id: fixture.profile.id)
            XCTFail("Profile reads must fail closed", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? ProfileScopedMutationGateError,
                .recoveryRequired(fixture.profile.id),
                file: file,
                line: line
            )
        }
        do {
            _ = try await fixture.settings.settings(for: fixture.profile.id)
            XCTFail("Settings reads must fail closed", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? ProfileScopedMutationGateError,
                .recoveryRequired(fixture.profile.id),
                file: file,
                line: line
            )
        }
    }
}

private enum AtomicVisibilityInterruption: Error, Equatable {
    case boundary(FamilySyncApplyBoundary)
}

private actor OneShotApplyBoundaryInterruption {
    private let target: FamilySyncApplyBoundary
    private var didInterrupt = false

    init(_ target: FamilySyncApplyBoundary) {
        self.target = target
    }

    func observe(_ boundary: FamilySyncApplyBoundary) throws {
        guard boundary == target, !didInterrupt else { return }
        didInterrupt = true
        throw AtomicVisibilityInterruption.boundary(boundary)
    }
}

private actor PausingApplyBoundary {
    private let target: FamilySyncApplyBoundary
    private var reached = false
    private var isReleased = false
    private var reachWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(_ target: FamilySyncApplyBoundary) {
        self.target = target
    }

    func observe(_ boundary: FamilySyncApplyBoundary) async {
        guard boundary == target else { return }
        reached = true
        let waiters = reachWaiters
        reachWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilReached() async {
        guard !reached else { return }
        await withCheckedContinuation { continuation in
            reachWaiters.append(continuation)
        }
    }

    func resume() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}

private actor AsyncCompletionProbe {
    private var completed = false

    func markCompleted() {
        completed = true
    }

    func isCompleted() -> Bool {
        completed
    }
}

private struct AtomicVisibilityFixture {
    let directory: URL
    let gate = ProfileScopedMutationGate()
    let profiles: LocalJSONKidProfileRepository
    let words: LocalJSONWordPoolRepository
    let settings: LocalJSONPracticeSettingsRepository
    let learning: LocalJSONLearningRecordRepository
    let daily: LocalJSONDailyQuestRepository
    let tombstones: LocalJSONProfileDeletionTombstoneRepository
    let transactions: LocalJSONFamilySyncApplyTransactionRepository
    let now = Date(timeIntervalSince1970: 2_200_000_000)
    let profile: KidProfile

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaAtomicVisibility-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        profiles = LocalJSONKidProfileRepository(
            snapshotURL: directory.appendingPathComponent("profiles.json"),
            mutationGate: gate
        )
        words = LocalJSONWordPoolRepository(
            snapshotURL: directory.appendingPathComponent("words.json"),
            mutationGate: gate
        )
        settings = LocalJSONPracticeSettingsRepository(
            snapshotURL: directory.appendingPathComponent("settings.json"),
            mutationGate: gate
        )
        learning = LocalJSONLearningRecordRepository(
            snapshotURL: directory.appendingPathComponent("learning.json"),
            mutationGate: gate
        )
        daily = LocalJSONDailyQuestRepository(
            snapshotURL: directory.appendingPathComponent("daily.json"),
            mutationGate: gate
        )
        tombstones = LocalJSONProfileDeletionTombstoneRepository(
            snapshotURL: directory.appendingPathComponent("deletions.json"),
            mutationGate: gate
        )
        transactions = LocalJSONFamilySyncApplyTransactionRepository(
            snapshotURL: directory.appendingPathComponent("transactions.json")
        )
        profile = KidProfile(
            displayName: "Committed Old",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: now.addingTimeInterval(-100)
        )
    }

    func seedLocalGeneration() async throws {
        try await profiles.save(profile)
        try await settings.save(.defaults(for: profile.id))
    }

    func remoteGenerationRecords() async throws -> [FamilySyncRecord] {
        let remoteDirectory = directory.appendingPathComponent(
            "remote",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: remoteDirectory,
            withIntermediateDirectories: true
        )
        let remoteProfiles = LocalJSONKidProfileRepository(
            snapshotURL: remoteDirectory.appendingPathComponent("profiles.json")
        )
        let remoteWords = LocalJSONWordPoolRepository(
            snapshotURL: remoteDirectory.appendingPathComponent("words.json"),
            deviceID: "remote-device"
        )
        let remoteSettings = LocalJSONPracticeSettingsRepository(
            snapshotURL: remoteDirectory.appendingPathComponent("settings.json")
        )
        let remoteLearning = LocalJSONLearningRecordRepository(
            snapshotURL: remoteDirectory.appendingPathComponent("learning.json")
        )
        let remoteDaily = LocalJSONDailyQuestRepository(
            snapshotURL: remoteDirectory.appendingPathComponent("daily.json")
        )
        let remoteProfile = KidProfile(
            id: profile.id,
            displayName: "Remote Complete",
            avatar: .cartoonAnimal(assetID: "fox"),
            selectedWorld: .pawsAndPines,
            starterWorld: profile.starterWorld,
            schoolGrade: .kindergarten,
            ageYears: 5,
            createdAt: profile.createdAt,
            updatedAt: now
        )
        try await remoteProfiles.save(remoteProfile)
        try await remoteSettings.save(
            ProfilePracticeSettings(
                profileID: profile.id,
                audio: AudioPreferences(
                    voiceEnabled: false,
                    musicEnabled: false,
                    soundEffectsEnabled: true,
                    reducedSoundEnabled: true,
                    calmEmergencyEnabled: false
                )
            )
        )
        let prompt = try WordPrompt(learningMode: .read, text: "at")
        _ = try await remoteWords.upsert([
            WordPoolEntryDraft(
                profileID: profile.id,
                prompt: prompt,
                addedAt: now,
                source: .guardianManual,
                positionInBatch: 0
            )
        ])
        let attempt = AttemptEvent(
            profileID: profile.id,
            wordPromptID: prompt.id,
            learningMode: .read,
            evidence: .firstIndependentAttempt,
            outcome: .correct,
            occurredAt: now
        )
        try await remoteLearning.append(attempt)
        try await remoteLearning.append(
            AttemptCorrectionEvent(
                originalAttemptID: attempt.id,
                correctedOutcome: .incorrect,
                reason: .guardianOverride,
                correctedAt: now.addingTimeInterval(1)
            )
        )
        let localDay = try LocalDay(year: 2039, month: 9, day: 18)
        let dailyPlan = DailyQuestPlan(
            localDay: localDay,
            questPlan: QuestPlan(
                profileID: profile.id,
                configuration: .defaultRead,
                reviewWordIDs: [],
                newWordIDs: [prompt.id],
                createdAt: now
            )
        )
        _ = try await remoteDaily.createPlanIfAbsent(dailyPlan)
        let completion = DailyQuestCompletion(
            dailyPlanID: dailyPlan.id,
            runQuestID: dailyPlan.id,
            profileID: profile.id,
            learningMode: .read,
            localDay: localDay,
            runKind: .today,
            points: 80,
            stars: QuestStars(earned: [.completion, .accuracy]),
            completedAt: now.addingTimeInterval(2)
        )
        let rewardKey = RewardGrantKey(
            profileID: profile.id,
            world: remoteProfile.selectedWorld,
            localDay: localDay,
            learningMode: .read
        )
        _ = try await remoteDaily.recordCompletion(
            completion,
            proposedRewardGrant: RewardGrant(
                key: rewardKey,
                dailyPlanID: dailyPlan.id,
                completionID: completion.id,
                item: ThemedRewardCatalog().reward(for: rewardKey),
                grantedAt: completion.completedAt
            ),
        )
        let remoteStore = RepositoryFamilySyncRecordStore(
            profileRepository: remoteProfiles,
            wordPoolRepository: remoteWords,
            practiceSettingsRepository: remoteSettings,
            learningRepository: remoteLearning,
            dailyQuestRepository: remoteDaily,
            tombstoneRepository: InMemoryProfileDeletionTombstoneRepository(),
            deviceID: "remote-device",
            clock: AtomicVisibilityClock(now: now)
        )
        return try await remoteStore.records(for: profile.id)
    }

    func deletionRecord() throws -> FamilySyncRecord {
        let tombstone = ProfileDeletionTombstone(
            profileID: profile.id,
            deletedAt: now
        )
        return FamilySyncRecord(
            recordName: "profile-\(profile.id)",
            profileID: profile.id,
            kind: .profileDeletion,
            payload: try InspectableSnapshotJSONCodec.makeEncoder().encode(
                tombstone
            ),
            updatedAt: now,
            deviceID: "remote-device",
            isDeleted: true,
            logicalRevision: FamilySyncLogicalRevision(
                counter: 9,
                deviceID: "remote-device"
            )
        )
    }

    func makeStore(
        interruption: OneShotApplyBoundaryInterruption
    ) -> RepositoryFamilySyncRecordStore {
        makeStore { boundary in
            try await interruption.observe(boundary)
        }
    }

    func makeStore(
        onApplyBoundary:
            @escaping @Sendable (FamilySyncApplyBoundary) async throws -> Void
    ) -> RepositoryFamilySyncRecordStore {
        RepositoryFamilySyncRecordStore(
            profileRepository: profiles,
            wordPoolRepository: words,
            practiceSettingsRepository: settings,
            learningRepository: learning,
            dailyQuestRepository: daily,
            tombstoneRepository: tombstones,
            applyTransactionRepository: transactions,
            mutationGate: gate,
            deviceID: "local-device",
            clock: AtomicVisibilityClock(now: now),
            onApplyBoundary: onApplyBoundary
        )
    }

    func assertRemoteGenerationVisible(
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let savedProfile = try await profiles.profile(id: profile.id)
        let savedSettings = try await settings.settings(for: profile.id)
        let savedWords = try await words.entries(
            for: profile.id,
            learningMode: .read
        )
        let attempts = try await learning.attempts(
            for: profile.id,
            wordPromptID: nil
        )
        let corrections = try await learning.corrections(
            routedTo: profile.id
        )
        let completions = try await daily.allCompletions(for: profile.id)

        XCTAssertEqual(savedProfile?.displayName, "Remote Complete", file: file, line: line)
        XCTAssertEqual(savedSettings?.audio.voiceEnabled, false, file: file, line: line)
        XCTAssertEqual(
            savedWords.map(\.prompt.displayText),
            ["at"],
            file: file,
            line: line
        )
        XCTAssertEqual(attempts.count, 1, file: file, line: line)
        XCTAssertEqual(corrections.count, 1, file: file, line: line)
        XCTAssertEqual(completions.count, 1, file: file, line: line)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct AtomicVisibilityClock: AppClock {
    let now: Date
}
