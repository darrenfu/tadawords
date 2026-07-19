import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsContent

final class RepositoryFamilySyncCausalOrderHarnessTests: XCTestCase {
    fileprivate enum DailyFact: CaseIterable {
        case plan
        case completion
        case reward
    }

    fileprivate enum LearningFact {
        case attempt
        case correction
    }

    func testDerivedWordProgressIsNeverExportedAsAuthoritativeSyncData()
        async throws
    {
        let fixture = try RepositoryCausalHarnessFixture()
        defer { fixture.remove() }
        try await fixture.seedProfiles()
        let learning = LocalJSONLearningRecordRepository(
            snapshotURL: fixture.learningURL
        )
        try await learning.append(
            AttemptEvent(
                profileID: fixture.profileA.id,
                wordPromptID: WordPromptID(),
                learningMode: .read,
                evidence: .firstIndependentAttempt,
                outcome: .correct,
                occurredAt: fixture.now
            )
        )
        let store = fixture.makeStore(
            learning: learning,
            daily: LocalJSONDailyQuestRepository(snapshotURL: fixture.dailyURL)
        )

        let exported = try await store.records(for: fixture.profileA.id)

        XCTAssertTrue(exported.contains { $0.kind == .attempt })
        XCTAssertFalse(
            exported.contains { $0.kind == .wordProgress },
            "wordProgress is rebuilt from immutable events and must never be transported as conflict authority"
        )
    }

    func testRewardArrivingAfterCompletionAndRepositoryRestartStillConverges()
        async throws
    {
        let fixture = try RepositoryCausalHarnessFixture()
        defer { fixture.remove() }
        try await fixture.seedProfiles()
        let firstDailyRepository = LocalJSONDailyQuestRepository(
            snapshotURL: fixture.dailyURL
        )
        let firstStore = fixture.makeStore(
            learning: LocalJSONLearningRecordRepository(
                snapshotURL: fixture.learningURL
            ),
            daily: firstDailyRepository
        )
        _ = try await firstDailyRepository.createPlanIfAbsent(fixture.dailyPlan)
        let completionRecord = try fixture.record(
            name: "daily-completion-\(fixture.completion.id)",
            profileID: fixture.profileA.id,
            kind: .dailyCompletion,
            value: fixture.completion,
            revision: 1
        )
        try await firstStore.validate([completionRecord], for: fixture.profileA.id)
        try await firstStore.apply([completionRecord], for: fixture.profileA.id)
        let completionOnlyState = try await firstDailyRepository.state(
            for: fixture.dailyPlan.key
        )
        XCTAssertNil(completionOnlyState.rewardGrant)

        let restartedDailyRepository = LocalJSONDailyQuestRepository(
            snapshotURL: fixture.dailyURL
        )
        let restartedStore = fixture.makeStore(
            learning: LocalJSONLearningRecordRepository(
                snapshotURL: fixture.learningURL
            ),
            daily: restartedDailyRepository
        )
        let rewardRecord = try fixture.record(
            name: "reward-grant-\(fixture.reward.id)",
            profileID: fixture.profileA.id,
            kind: .rewardGrant,
            value: fixture.reward,
            revision: 2
        )
        try await restartedStore.validate([rewardRecord], for: fixture.profileA.id)
        try await restartedStore.apply([rewardRecord], for: fixture.profileA.id)

        let convergedState = try await restartedDailyRepository.state(
            for: fixture.dailyPlan.key
        )
        XCTAssertEqual(convergedState.todayCompletion, fixture.completion)
        XCTAssertEqual(
            convergedState.rewardGrant,
            fixture.reward,
            "A later reward fact must join the already durable Today completion instead of being dropped"
        )
    }

    func testEveryPlanCompletionRewardArrivalOrderConvergesByteForByteAcrossRestarts()
        async throws
    {
        let fixture = try RepositoryCausalHarnessFixture()
        defer { fixture.remove() }
        try await fixture.seedProfiles()
        let permutations: [[DailyFact]] = [
            [.plan, .completion, .reward],
            [.plan, .reward, .completion],
            [.completion, .plan, .reward],
            [.completion, .reward, .plan],
            [.reward, .plan, .completion],
            [.reward, .completion, .plan],
        ]
        var baseline: Data?

        for (index, permutation) in permutations.enumerated() {
            let snapshotURL = fixture.directory.appendingPathComponent(
                "daily-permutation-\(index).json"
            )
            let finalBytes = try await applyDailyFacts(
                permutation,
                snapshotURL: snapshotURL,
                fixture: fixture
            )
            if let baseline {
                let baselineSnapshot =
                    try InspectableSnapshotJSONCodec
                    .makeDecoder().decode(
                        DailyQuestSnapshot.self,
                        from: baseline
                    )
                let finalSnapshot =
                    try InspectableSnapshotJSONCodec
                    .makeDecoder().decode(
                        DailyQuestSnapshot.self,
                        from: finalBytes
                    )
                XCTAssertEqual(
                    finalBytes,
                    baseline,
                    "Plan, Today completion, and reward must have one byte-equivalent canonical snapshot for order \(permutation). Decoded differences: \(dailySnapshotDifferences(baselineSnapshot, finalSnapshot))"
                )
            } else {
                baseline = finalBytes
            }
        }
    }

    func testOrphanCorrectionRoutedToProfileACannotAttachToLaterAttemptFromProfileB()
        async throws
    {
        let fixture = try RepositoryCausalHarnessFixture()
        defer { fixture.remove() }
        try await fixture.seedProfiles()
        let firstLearningRepository = LocalJSONLearningRecordRepository(
            snapshotURL: fixture.learningURL
        )
        let firstStore = fixture.makeStore(
            learning: firstLearningRepository,
            daily: LocalJSONDailyQuestRepository(snapshotURL: fixture.dailyURL)
        )
        let correction = AttemptCorrectionEvent(
            originalAttemptID: fixture.attemptID,
            correctedOutcome: .correct,
            reason: .guardianOverride,
            correctedAt: fixture.now
        )
        let correctionRecord = try fixture.record(
            name: "attempt-correction-\(correction.id)",
            profileID: fixture.profileA.id,
            kind: .attemptCorrection,
            value: correction,
            revision: 1
        )
        try await firstStore.validate([correctionRecord], for: fixture.profileA.id)
        try await firstStore.apply([correctionRecord], for: fixture.profileA.id)
        let staged = try await firstLearningRepository.corrections(
            for: fixture.attemptID
        )
        XCTAssertEqual(staged, [correction])

        let restartedLearningRepository = LocalJSONLearningRecordRepository(
            snapshotURL: fixture.learningURL
        )
        let restartedStore = fixture.makeStore(
            learning: restartedLearningRepository,
            daily: LocalJSONDailyQuestRepository(snapshotURL: fixture.dailyURL)
        )
        let attempt = AttemptEvent(
            id: fixture.attemptID,
            profileID: fixture.profileB.id,
            wordPromptID: WordPromptID(),
            learningMode: .read,
            evidence: .firstIndependentAttempt,
            outcome: .incorrect,
            occurredAt: fixture.now.addingTimeInterval(1)
        )
        let attemptRecord = try fixture.record(
            name: "attempt-\(attempt.id)",
            profileID: fixture.profileB.id,
            kind: .attempt,
            value: attempt,
            revision: 2
        )

        do {
            try await restartedStore.validate([attemptRecord], for: fixture.profileB.id)
            XCTFail(
                "The durable orphan correction is owned by Profile A; the same AttemptID must be rejected for Profile B"
            )
        } catch {
            XCTAssertNotNil(error as? RepositoryFamilySyncError)
        }

        let profileAAttempt = fixture.profileAAttempt
        let profileAAttemptRecord = try fixture.record(
            name: "attempt-\(profileAAttempt.id)",
            profileID: fixture.profileA.id,
            kind: .attempt,
            value: profileAAttempt,
            revision: 3
        )
        try await restartedStore.validate(
            [profileAAttemptRecord],
            for: fixture.profileA.id
        )
        try await restartedStore.apply(
            [profileAAttemptRecord],
            for: fixture.profileA.id
        )

        let attempts = try await restartedLearningRepository.attempts(
            for: fixture.profileA.id,
            wordPromptID: fixture.wordPromptID
        )
        let progress = try await restartedLearningRepository.progress(
            for: fixture.profileA.id,
            wordPromptID: fixture.wordPromptID,
            learningMode: .read
        )
        let persistedCorrections =
            try await restartedLearningRepository
            .corrections(for: fixture.attemptID)
        XCTAssertEqual(attempts, [profileAAttempt])
        XCTAssertEqual(persistedCorrections, [correction])
        XCTAssertEqual(progress?.firstIndependentAttemptCount, 1)
        XCTAssertEqual(
            progress?.firstIndependentCorrectCount,
            1,
            "Profile A's owned correction must project over Profile A's later attempt after Profile B was rejected"
        )
    }

    func testAttemptAndCorrectionArrivalOrdersConvergeByteForByteAcrossRestart()
        async throws
    {
        let fixture = try RepositoryCausalHarnessFixture()
        defer { fixture.remove() }
        try await fixture.seedProfiles()
        let attemptFirstURL = fixture.directory.appendingPathComponent(
            "learning-attempt-first.json"
        )
        let correctionFirstURL = fixture.directory.appendingPathComponent(
            "learning-correction-first.json"
        )

        let attemptFirstBytes = try await applyLearningFacts(
            [.attempt, .correction],
            snapshotURL: attemptFirstURL,
            fixture: fixture
        )
        let correctionFirstBytes = try await applyLearningFacts(
            [.correction, .attempt],
            snapshotURL: correctionFirstURL,
            fixture: fixture
        )

        XCTAssertEqual(
            correctionFirstBytes,
            attemptFirstBytes,
            "Attempt and correction order must converge to one byte-equivalent facts-and-projection snapshot"
        )
        let restarted = LocalJSONLearningRecordRepository(
            snapshotURL: correctionFirstURL
        )
        let progress = try await restarted.progress(
            for: fixture.profileA.id,
            wordPromptID: fixture.wordPromptID,
            learningMode: .read
        )
        XCTAssertEqual(progress?.firstIndependentAttemptCount, 1)
        XCTAssertEqual(progress?.firstIndependentCorrectCount, 1)
    }

    func testCorrectionFirstRemainsExportableAcrossRestartUntilOwnedAttemptJoins()
        async throws
    {
        let fixture = try RepositoryCausalHarnessFixture()
        defer { fixture.remove() }
        try await fixture.seedProfiles()
        let snapshotURL = fixture.directory.appendingPathComponent(
            "learning-orphan-export.json"
        )
        let correctionRecord = try fixture.learningRecord(for: .correction)
        var learning = LocalJSONLearningRecordRepository(snapshotURL: snapshotURL)
        var store = fixture.makeStore(
            learning: learning,
            daily: LocalJSONDailyQuestRepository(snapshotURL: fixture.dailyURL)
        )
        try await store.validate([correctionRecord], for: fixture.profileA.id)
        try await store.apply([correctionRecord], for: fixture.profileA.id)

        learning = LocalJSONLearningRecordRepository(snapshotURL: snapshotURL)
        store = fixture.makeStore(
            learning: learning,
            daily: LocalJSONDailyQuestRepository(snapshotURL: fixture.dailyURL)
        )
        let orphanExport = try await store.records(for: fixture.profileA.id)
        XCTAssertEqual(
            orphanExport.filter { $0.kind == .attemptCorrection },
            [correctionRecord],
            "A correction-first fact must remain transport-visible while its attempt is still in flight"
        )

        let attemptRecord = try fixture.learningRecord(for: .attempt)
        try await store.validate([attemptRecord], for: fixture.profileA.id)
        try await store.apply([attemptRecord], for: fixture.profileA.id)
        let joinedExport = try await store.records(for: fixture.profileA.id)
        XCTAssertEqual(
            joinedExport.filter { $0.kind == .attemptCorrection }.count,
            1
        )
        let progress = try await learning.progress(
            for: fixture.profileA.id,
            wordPromptID: fixture.wordPromptID,
            learningMode: .read
        )
        XCTAssertEqual(progress?.firstIndependentCorrectCount, 1)
    }

    func testTwoDevicesWithDifferentTodayUUIDsUseStableKeysAndConvergeByteForByte()
        async throws
    {
        let fixture = try RepositoryCausalHarnessFixture()
        defer { fixture.remove() }
        try await fixture.seedProfiles()
        let deviceA = fixture.makeDailyDeviceFacts(
            deviceID: "device-a",
            completedAt: fixture.now.addingTimeInterval(20)
        )
        let deviceB = fixture.makeDailyDeviceFacts(
            deviceID: "device-b",
            completedAt: fixture.now.addingTimeInterval(40)
        )
        XCTAssertNotEqual(deviceA.plan.id, deviceB.plan.id)
        XCTAssertNotEqual(deviceA.completion.id, deviceB.completion.id)
        XCTAssertNotEqual(deviceA.reward.id, deviceB.reward.id)
        XCTAssertEqual(deviceA.plan.key, deviceB.plan.key)

        let recordsA = try await exportedDailyRecords(
            deviceA,
            snapshotURL: fixture.directory.appendingPathComponent("daily-device-a.json"),
            fixture: fixture
        )
        let recordsB = try await exportedDailyRecords(
            deviceB,
            snapshotURL: fixture.directory.appendingPathComponent("daily-device-b.json"),
            fixture: fixture
        )
        for kind in [
            FamilySyncRecordKind.dailyPlan,
            .dailyCompletion,
            .rewardGrant,
        ] {
            let namesA = recordsA.filter { $0.kind == kind }.map(\.recordName)
            let namesB = recordsB.filter { $0.kind == kind }.map(\.recordName)
            XCTAssertEqual(namesA.count, 1)
            XCTAssertEqual(
                namesA,
                namesB,
                "\(kind) must use one stable Profile x Mode x LocalDay record key, not a device-local UUID"
            )
        }

        let forward = try await applyDailyRecordBatches(
            [recordsA, recordsB],
            snapshotURL: fixture.directory.appendingPathComponent(
                "daily-converged-a-b.json"
            ),
            fixture: fixture
        )
        let reverse = try await applyDailyRecordBatches(
            [recordsB, recordsA],
            snapshotURL: fixture.directory.appendingPathComponent(
                "daily-converged-b-a.json"
            ),
            fixture: fixture
        )
        let forwardSnapshot = try InspectableSnapshotJSONCodec.makeDecoder()
            .decode(DailyQuestSnapshot.self, from: forward)
        let reverseSnapshot = try InspectableSnapshotJSONCodec.makeDecoder()
            .decode(DailyQuestSnapshot.self, from: reverse)
        let reconnectDifferences = dailySnapshotDifferences(
            forwardSnapshot,
            reverseSnapshot
        )
        XCTAssertEqual(
            reverse,
            forward,
            "Two independently generated Today UUID graphs must converge to one canonical snapshot regardless of reconnect order. Decoded differences: \(reconnectDifferences)"
        )
        let decoded = try InspectableSnapshotJSONCodec.makeDecoder().decode(
            DailyQuestSnapshot.self,
            from: forward
        )
        XCTAssertEqual(decoded.plans.count, 1)
        XCTAssertEqual(
            decoded.completions.filter { $0.runKind == .today }.count,
            1
        )
        XCTAssertEqual(decoded.rewardGrants.count, 1)
    }

    private func applyDailyFacts(
        _ facts: [DailyFact],
        snapshotURL: URL,
        fixture: RepositoryCausalHarnessFixture
    ) async throws -> Data {
        for fact in facts {
            let daily = LocalJSONDailyQuestRepository(snapshotURL: snapshotURL)
            let store = fixture.makeStore(
                learning: LocalJSONLearningRecordRepository(
                    snapshotURL: fixture.learningURL
                ),
                daily: daily
            )
            let record = try fixture.dailyRecord(for: fact)
            try await store.validate([record], for: fixture.profileA.id)
            try await store.apply([record], for: fixture.profileA.id)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: snapshotURL.path),
                "A standalone \(fact) fact must be durably staged before the next repository process"
            )
        }

        let restarted = LocalJSONDailyQuestRepository(snapshotURL: snapshotURL)
        let state = try await restarted.state(for: fixture.dailyPlan.key)
        XCTAssertEqual(state.plan, fixture.dailyPlan)
        XCTAssertEqual(state.todayCompletion, fixture.completion)
        XCTAssertEqual(state.rewardGrant, fixture.reward)
        return try Data(contentsOf: snapshotURL)
    }

    private func applyLearningFacts(
        _ facts: [LearningFact],
        snapshotURL: URL,
        fixture: RepositoryCausalHarnessFixture
    ) async throws -> Data {
        for fact in facts {
            let learning = LocalJSONLearningRecordRepository(
                snapshotURL: snapshotURL
            )
            let store = fixture.makeStore(
                learning: learning,
                daily: LocalJSONDailyQuestRepository(
                    snapshotURL: fixture.directory.appendingPathComponent(
                        "learning-order-daily.json"
                    )
                )
            )
            let record = try fixture.learningRecord(for: fact)
            try await store.validate([record], for: fixture.profileA.id)
            try await store.apply([record], for: fixture.profileA.id)
        }
        return try Data(contentsOf: snapshotURL)
    }

    private func exportedDailyRecords(
        _ facts: RepositoryCausalHarnessFixture.DailyDeviceFacts,
        snapshotURL: URL,
        fixture: RepositoryCausalHarnessFixture
    ) async throws -> [FamilySyncRecord] {
        let daily = LocalJSONDailyQuestRepository(snapshotURL: snapshotURL)
        _ = try await daily.createPlanIfAbsent(facts.plan)
        _ = try await daily.recordCompletion(
            facts.completion,
            proposedRewardGrant: facts.reward
        )
        let store = fixture.makeStore(
            learning: LocalJSONLearningRecordRepository(
                snapshotURL: fixture.learningURL
            ),
            daily: daily,
            deviceID: facts.deviceID
        )
        return try await store.records(for: fixture.profileA.id).filter {
            $0.kind == .dailyPlan || $0.kind == .dailyCompletion
                || $0.kind == .rewardGrant
        }
    }

    private func applyDailyRecordBatches(
        _ batches: [[FamilySyncRecord]],
        snapshotURL: URL,
        fixture: RepositoryCausalHarnessFixture
    ) async throws -> Data {
        for batch in batches {
            let daily = LocalJSONDailyQuestRepository(snapshotURL: snapshotURL)
            let store = fixture.makeStore(
                learning: LocalJSONLearningRecordRepository(
                    snapshotURL: fixture.learningURL
                ),
                daily: daily
            )
            try await store.validate(batch, for: fixture.profileA.id)
            try await store.apply(batch, for: fixture.profileA.id)
        }
        return try Data(contentsOf: snapshotURL)
    }

    private func dailySnapshotDifferences(
        _ baseline: DailyQuestSnapshot,
        _ candidate: DailyQuestSnapshot
    ) -> [String] {
        var differences: [String] = []
        if baseline.schemaVersion != candidate.schemaVersion {
            differences.append(
                "schemaVersion \(baseline.schemaVersion) != \(candidate.schemaVersion)"
            )
        }
        if baseline.canonicalBusinessKeyVersion
            != candidate.canonicalBusinessKeyVersion
        {
            differences.append(
                "canonicalBusinessKeyVersion \(baseline.canonicalBusinessKeyVersion) != \(candidate.canonicalBusinessKeyVersion)"
            )
        }
        if baseline.plans != candidate.plans {
            differences.append("plans \(baseline.plans) != \(candidate.plans)")
        }
        if baseline.completions != candidate.completions {
            differences.append(
                "completions \(baseline.completions) != \(candidate.completions)"
            )
        }
        if baseline.rewardGrants != candidate.rewardGrants {
            differences.append(
                "rewardGrants \(baseline.rewardGrants) != \(candidate.rewardGrants)"
            )
        }
        if baseline.pendingCompletions != candidate.pendingCompletions {
            differences.append(
                "pendingCompletions \(baseline.pendingCompletions) != \(candidate.pendingCompletions)"
            )
        }
        if baseline.pendingRewardGrants != candidate.pendingRewardGrants {
            differences.append(
                "pendingRewardGrants \(baseline.pendingRewardGrants) != \(candidate.pendingRewardGrants)"
            )
        }
        return differences
    }
}

private struct RepositoryCausalHarnessFixture {
    let directory: URL
    let learningURL: URL
    let dailyURL: URL
    let profiles = InMemoryKidProfileRepository()
    let words: LocalJSONWordPoolRepository
    let settings: LocalJSONPracticeSettingsRepository
    let tombstones = InMemoryProfileDeletionTombstoneRepository()
    let now = Date(timeIntervalSince1970: 2_140_000_000)
    let profileA: KidProfile
    let profileB: KidProfile
    let attemptID = AttemptID()
    let correctionID = AttemptCorrectionID()
    let wordPromptID = WordPromptID()
    let dailyPlan: DailyQuestPlan
    let completion: DailyQuestCompletion
    let reward: RewardGrant

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaRepositoryCausalHarness-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        learningURL = directory.appendingPathComponent("learning.json")
        dailyURL = directory.appendingPathComponent("daily.json")
        words = LocalJSONWordPoolRepository(
            snapshotURL: directory.appendingPathComponent("words.json")
        )
        settings = LocalJSONPracticeSettingsRepository(
            snapshotURL: directory.appendingPathComponent("settings.json")
        )
        profileA = KidProfile(
            displayName: "A",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: now
        )
        profileB = KidProfile(
            displayName: "B",
            avatar: .cartoonAnimal(assetID: "fox"),
            selectedWorld: .moonpetalKingdom,
            createdAt: now
        )
        let localDay = try LocalDay(year: 2037, month: 10, day: 25)
        let plan = QuestPlan(
            profileID: profileA.id,
            configuration: QuestConfiguration(
                learningMode: .read,
                newWordLimit: 5,
                reviewWordLimit: 5,
                attentionBudget: 10,
                contentOrder: .newThenReview
            ),
            reviewWordIDs: [],
            newWordIDs: [WordPromptID()],
            createdAt: now
        )
        dailyPlan = DailyQuestPlan(localDay: localDay, questPlan: plan)
        completion = DailyQuestCompletion(
            dailyPlanID: plan.id,
            runQuestID: plan.id,
            profileID: profileA.id,
            learningMode: .read,
            localDay: localDay,
            runKind: .today,
            points: 80,
            stars: QuestStars(earned: [.completion, .accuracy]),
            completedAt: now.addingTimeInterval(10)
        )
        reward = RewardGrant(
            key: RewardGrantKey(
                profileID: profileA.id,
                world: .moonpetalKingdom,
                localDay: localDay,
                learningMode: .read
            ),
            dailyPlanID: plan.id,
            completionID: completion.id,
            item: RewardCatalogItem(
                id: RewardItemID(rawValue: "causal-harness-crown"),
                world: .moonpetalKingdom,
                displayName: "Causal Crown",
                iconAssetID: "crown.fill"
            ),
            grantedAt: now.addingTimeInterval(11)
        )
    }

    func seedProfiles() async throws {
        try await profiles.save(profileA)
        try await profiles.save(profileB)
    }

    func makeStore(
        learning: LocalJSONLearningRecordRepository,
        daily: LocalJSONDailyQuestRepository,
        deviceID: String = "causal-harness"
    ) -> RepositoryFamilySyncRecordStore {
        RepositoryFamilySyncRecordStore(
            profileRepository: profiles,
            wordPoolRepository: words,
            practiceSettingsRepository: settings,
            learningRepository: learning,
            dailyQuestRepository: daily,
            tombstoneRepository: tombstones,
            deviceID: deviceID
        )
    }

    func record<Value: Encodable>(
        name: String,
        profileID: ProfileID,
        kind: FamilySyncRecordKind,
        value: Value,
        revision: UInt64
    ) throws -> FamilySyncRecord {
        FamilySyncRecord(
            recordName: name,
            profileID: profileID,
            kind: kind,
            payload: try InspectableSnapshotJSONCodec.makeEncoder().encode(value),
            updatedAt: now,
            deviceID: "remote-device",
            logicalRevision: FamilySyncLogicalRevision(
                counter: revision,
                deviceID: "remote-device"
            )
        )
    }

    var profileAAttempt: AttemptEvent {
        AttemptEvent(
            id: attemptID,
            profileID: profileA.id,
            wordPromptID: wordPromptID,
            learningMode: .read,
            evidence: .firstIndependentAttempt,
            outcome: .incorrect,
            occurredAt: now.addingTimeInterval(1)
        )
    }

    var profileACorrection: AttemptCorrectionEvent {
        AttemptCorrectionEvent(
            id: correctionID,
            originalAttemptID: attemptID,
            correctedOutcome: .correct,
            reason: .guardianOverride,
            correctedAt: now.addingTimeInterval(2)
        )
    }

    fileprivate func dailyRecord(
        for fact: RepositoryFamilySyncCausalOrderHarnessTests.DailyFact
    ) throws -> FamilySyncRecord {
        switch fact {
        case .plan:
            try record(
                name:
                    "daily-plan-\(dailyPlan.key.profileID)-\(dailyPlan.key.learningMode.rawValue)-\(dailyPlan.key.localDay)",
                profileID: profileA.id,
                kind: .dailyPlan,
                value: dailyPlan,
                revision: 1
            )
        case .completion:
            try record(
                name: "daily-completion-\(completion.id)",
                profileID: profileA.id,
                kind: .dailyCompletion,
                value: completion,
                revision: 2
            )
        case .reward:
            try record(
                name: "reward-grant-\(reward.id)",
                profileID: profileA.id,
                kind: .rewardGrant,
                value: reward,
                revision: 3
            )
        }
    }

    fileprivate func learningRecord(
        for fact: RepositoryFamilySyncCausalOrderHarnessTests.LearningFact
    ) throws -> FamilySyncRecord {
        switch fact {
        case .attempt:
            try record(
                name: "attempt-\(profileAAttempt.id)",
                profileID: profileA.id,
                kind: .attempt,
                value: profileAAttempt,
                revision: 1
            )
        case .correction:
            try record(
                name: "attempt-correction-\(profileACorrection.id)",
                profileID: profileA.id,
                kind: .attemptCorrection,
                value: profileACorrection,
                revision: 2
            )
        }
    }

    struct DailyDeviceFacts {
        let deviceID: String
        let plan: DailyQuestPlan
        let completion: DailyQuestCompletion
        let reward: RewardGrant
    }

    func makeDailyDeviceFacts(
        deviceID: String,
        completedAt: Date
    ) -> DailyDeviceFacts {
        let plan = DailyQuestPlan(
            localDay: dailyPlan.localDay,
            questPlan: QuestPlan(
                profileID: profileA.id,
                configuration: dailyPlan.questPlan.configuration,
                reviewWordIDs: dailyPlan.questPlan.reviewWordIDs,
                newWordIDs: dailyPlan.questPlan.newWordIDs,
                createdAt: dailyPlan.questPlan.createdAt
            )
        )
        let completion = DailyQuestCompletion(
            dailyPlanID: plan.id,
            runQuestID: plan.id,
            profileID: profileA.id,
            learningMode: .read,
            localDay: dailyPlan.localDay,
            runKind: .today,
            points: 90,
            stars: QuestStars(earned: [.completion, .accuracy]),
            completedAt: completedAt
        )
        let reward = RewardGrant(
            key: RewardGrantKey(
                profileID: profileA.id,
                world: .moonpetalKingdom,
                localDay: dailyPlan.localDay,
                learningMode: .read
            ),
            dailyPlanID: plan.id,
            completionID: completion.id,
            item: self.reward.item,
            grantedAt: completedAt.addingTimeInterval(1)
        )
        return DailyDeviceFacts(
            deviceID: deviceID,
            plan: plan,
            completion: completion,
            reward: reward
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
