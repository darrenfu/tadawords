import Foundation
import TadaWordsDomain

public actor RepositoryFamilySyncRecordStore: FamilySyncRecordStore {
    private let profileRepository: any KidProfileRepository
    private let wordPoolRepository: LocalJSONWordPoolRepository
    private let practiceSettingsRepository: LocalJSONPracticeSettingsRepository
    private let learningRepository: any ProfileLearningRecordRepository
    private let dailyQuestRepository: any DailyQuestHistoryRepository
    private let tombstoneRepository: any ProfileDeletionTombstoneRepository
    private let applyTransactionRepository: (any FamilySyncApplyTransactionRepository)?
    private let childSessionRepository: (any ChildSessionRepository)?
    private let voiceprintRepository: (any DeviceVoiceprintRepository)?
    private let handwritingPreferenceRemover: (any HandwritingPreferenceRemoving)?
    private let mutationGate: ProfileScopedMutationGate?
    private let deviceID: String
    private let clock: any AppClock
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        profileRepository: any KidProfileRepository,
        wordPoolRepository: LocalJSONWordPoolRepository,
        practiceSettingsRepository: LocalJSONPracticeSettingsRepository,
        learningRepository: any ProfileLearningRecordRepository,
        dailyQuestRepository: any DailyQuestHistoryRepository,
        tombstoneRepository: any ProfileDeletionTombstoneRepository,
        applyTransactionRepository:
            (any FamilySyncApplyTransactionRepository)? = nil,
        childSessionRepository: (any ChildSessionRepository)? = nil,
        voiceprintRepository: (any DeviceVoiceprintRepository)? = nil,
        handwritingPreferenceRemover: (any HandwritingPreferenceRemoving)? = nil,
        mutationGate: ProfileScopedMutationGate? = nil,
        deviceID: String,
        clock: any AppClock = SystemAppClock()
    ) {
        self.profileRepository = profileRepository
        self.wordPoolRepository = wordPoolRepository
        self.practiceSettingsRepository = practiceSettingsRepository
        self.learningRepository = learningRepository
        self.dailyQuestRepository = dailyQuestRepository
        self.tombstoneRepository = tombstoneRepository
        self.applyTransactionRepository = applyTransactionRepository
        self.childSessionRepository = childSessionRepository
        self.voiceprintRepository = voiceprintRepository
        self.handwritingPreferenceRemover = handwritingPreferenceRemover
        self.mutationGate = mutationGate
        self.deviceID = deviceID
        self.clock = clock
        encoder = InspectableSnapshotJSONCodec.makeEncoder()
        decoder = InspectableSnapshotJSONCodec.makeDecoder()
    }

    public func profileIDsForSync() async throws -> [ProfileID] {
        async let profiles = profileRepository.profiles()
        async let tombstones = tombstoneRepository.tombstones()
        return Array(
            Set(try await profiles.map(\.id))
                .union(try await tombstones.map(\.profileID))
        ).sorted { $0.description < $1.description }
    }

    public func isProfileDeleted(_ profileID: ProfileID) async throws -> Bool {
        try await tombstoneRepository.tombstone(for: profileID) != nil
    }

    public func applyIfUnchanged(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID,
        expected: FamilySyncRecordSetFingerprint
    ) async throws -> Bool {
        guard let mutationGate else {
            let current = try await self.records(for: profileID)
            guard FamilySyncRecordSetFingerprint(records: current) == expected else {
                return false
            }
            try await applyDurably(records, for: profileID)
            return true
        }

        await mutationGate.acquire(profileID)
        do {
            let applied = try await ProfileScopedMutationLeaseContext.$profileID
                .withValue(profileID) {
                    let current = try await self.records(for: profileID)
                    guard FamilySyncRecordSetFingerprint(records: current) == expected else {
                        return false
                    }
                    try await self.applyDurably(records, for: profileID)
                    return true
                }
            await mutationGate.release(profileID)
            return applied
        } catch {
            await mutationGate.release(profileID)
            throw error
        }
    }

    /// Replays any batch that was durably accepted before a prior process died.
    /// Bootstrap calls this before reading Profiles for SwiftUI, so the UI can
    /// never observe a half-applied cross-repository transaction.
    public func replayPendingApplyTransactions() async throws {
        guard let applyTransactionRepository else { return }
        for transaction
            in try await applyTransactionRepository
            .pendingTransactions()
        {
            try await replay(transaction)
        }
    }

    public func records(
        for profileID: ProfileID
    ) async throws -> [FamilySyncRecord] {
        var records: [FamilySyncRecord] = []
        if let tombstone = try await tombstoneRepository.tombstone(
            for: profileID
        ) {
            return [
                try record(
                    name: "profile-\(profileID)",
                    profileID: profileID,
                    kind: .profileDeletion,
                    value: tombstone,
                    updatedAt: tombstone.deletedAt,
                    isDeleted: true
                )
            ]
        }
        guard let profile = try await profileRepository.profile(id: profileID) else {
            return records
        }
        records.append(
            try record(
                name: "profile-\(profileID)",
                profileID: profileID,
                kind: .profile,
                value: FamilySyncProfilePayload(profile: profile),
                updatedAt: profile.updatedAt
            )
        )

        let wordRevision = fileRevisionDate(wordPoolRepository.snapshotURL)
        let settingsRevision = fileRevisionDate(
            practiceSettingsRepository.snapshotURL
        )
        for mode in LearningMode.allCases {
            let entries = try await wordPoolRepository.entries(
                for: profileID,
                learningMode: mode,
                includingInactive: true
            )
            records += try entries.map { entry in
                try record(
                    name: "word-entry-\(entry.id)",
                    profileID: profileID,
                    kind: .wordPoolEntry,
                    value: entry,
                    updatedAt: max(entry.lastQueuedAt, wordRevision),
                    logicalRevision: entry.logicalRevision
                )
            }
        }
        try await registerWordPromptAliases(for: profileID)

        if let settings = try await practiceSettingsRepository.settings(for: profileID) {
            records += try PracticeSettingsSyncGroup.allCases.map { group in
                try record(
                    name: group.recordName(for: profileID),
                    profileID: profileID,
                    kind: .practiceSettings,
                    value: PracticeSettingsSyncPayload(
                        settings: settings,
                        group: group
                    ),
                    updatedAt: settingsRevision
                )
            }
        }

        let attempts = try await learningRepository.attempts(
            for: profileID,
            wordPromptID: nil
        )
        for attempt in attempts {
            records.append(
                try record(
                    name: "attempt-\(attempt.id)",
                    profileID: profileID,
                    kind: .attempt,
                    value: attempt,
                    updatedAt: attempt.occurredAt
                )
            )
        }
        let corrections: [AttemptCorrectionEvent]
        if let routedRepository =
            learningRepository as? any RoutedAttemptCorrectionRepository
        {
            corrections = try await routedRepository.corrections(
                routedTo: profileID
            )
        } else {
            var legacyCorrections: [AttemptCorrectionEvent] = []
            for attempt in attempts {
                legacyCorrections += try await learningRepository.corrections(
                    for: attempt.id
                )
            }
            corrections = legacyCorrections
        }
        for correction in corrections {
            if let routedRepository = learningRepository
                as? any RoutedAttemptCorrectionRepository,
                let sourceRecord = try await routedRepository.sourceRecord(
                    for: correction.id
                ),
                sourceRecord.profileID == profileID,
                sourceRecord.kind == .attemptCorrection,
                sourceRecord.recordName
                    == "attempt-correction-\(correction.id)",
                sourceRecord.payload
                    == (try? encoder.encode(correction))
            {
                records.append(sourceRecord)
                continue
            }
            records.append(
                try record(
                    name: "attempt-correction-\(correction.id)",
                    profileID: profileID,
                    kind: .attemptCorrection,
                    value: correction,
                    updatedAt: correction.correctedAt
                )
            )
        }
        let completions = try await dailyQuestRepository.allCompletions(for: profileID)
        for plan in try await dailyQuestRepository.allPlans(for: profileID) {
            records.append(
                try record(
                    name: dailyPlanRecordName(plan.key),
                    profileID: profileID,
                    kind: .dailyPlan,
                    value: plan,
                    updatedAt: max(
                        completions
                            .filter { $0.dailyPlanID == plan.id }
                            .map(\.completedAt)
                            .max() ?? profile.createdAt,
                        profile.createdAt
                    )
                )
            )
        }
        records += try completions.map { completion in
            try record(
                name: dailyCompletionRecordName(completion),
                profileID: profileID,
                kind: .dailyCompletion,
                value: completion,
                updatedAt: completion.completedAt
            )
        }
        records += try await dailyQuestRepository.rewardGrants(for: profileID).map {
            grant in
            try record(
                name: rewardGrantRecordName(grant),
                profileID: profileID,
                kind: .rewardGrant,
                value: grant,
                updatedAt: grant.grantedAt
            )
        }
        return records.sorted { $0.recordName < $1.recordName }
    }

    public func apply(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        guard let mutationGate else {
            try await applyDurably(records, for: profileID)
            return
        }
        await mutationGate.acquire(profileID)
        do {
            try await ProfileScopedMutationLeaseContext.$profileID.withValue(
                profileID
            ) {
                try await self.applyDurably(records, for: profileID)
            }
            await mutationGate.release(profileID)
        } catch {
            await mutationGate.release(profileID)
            throw error
        }
    }

    private func applyValidated(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        if records.contains(where: { $0.kind == .profileDeletion && $0.isDeleted }) {
            let newest =
                records
                .filter { $0.kind == .profileDeletion && $0.isDeleted }
                .max { $0.updatedAt < $1.updatedAt }!
            let tombstone =
                (try? decode(ProfileDeletionTombstone.self, from: newest))
                ?? ProfileDeletionTombstone(
                    profileID: profileID,
                    deletedAt: newest.updatedAt
                )
            try await tombstoneRepository.save(tombstone)
            try await deleteProfileData(profileID)
            try await tombstoneRepository.markCommitted(for: profileID)
            return
        }

        // A Profile ID is terminal once its deletion ledger is durable. This
        // store-level guard also covers crash replay and direct callers, not
        // only the coordinator's normal stale-record filter.
        if try await tombstoneRepository.tombstone(for: profileID) != nil {
            return
        }

        for record in records where record.kind == .profile {
            let incoming = try decode(FamilySyncProfilePayload.self, from: record)
            let localVoiceprintStatus =
                try await profileRepository.profile(
                    id: profileID
                )?.voiceprintStatus ?? .notEnrolled
            try await profileRepository.save(
                incoming.materialized(
                    preservingVoiceprintStatus: localVoiceprintStatus
                )
            )
        }
        for record in records where record.kind == .wordPoolEntry {
            try await wordPoolRepository.mergeSynced(
                try decode(WordPoolEntry.self, from: record),
                logicalRevision: record.logicalRevision
            )
        }
        try await registerWordPromptAliases(for: profileID)
        let settingsRecords =
            records
            .filter { $0.kind == .practiceSettings }
            .sorted { left, right in
                let legacyName = "practice-settings-\(profileID)"
                if left.recordName == legacyName { return true }
                if right.recordName == legacyName { return false }
                return left.recordName < right.recordName
            }
        for record in settingsRecords {
            let legacyName = "practice-settings-\(profileID)"
            if record.recordName == legacyName {
                try await practiceSettingsRepository.save(
                    try decode(ProfilePracticeSettings.self, from: record)
                )
                continue
            }
            let payload = try decode(
                PracticeSettingsSyncPayload.self,
                from: record
            )
            let current =
                try await practiceSettingsRepository.settings(
                    for: profileID
                ) ?? .defaults(for: profileID)
            try await practiceSettingsRepository.save(
                try payload.applying(to: current)
            )
        }
        for record in records where record.kind == .attempt {
            try await learningRepository.append(
                try decode(AttemptEvent.self, from: record)
            )
        }
        for record in records where record.kind == .attemptCorrection {
            let correction = try decode(
                AttemptCorrectionEvent.self,
                from: record
            )
            if let routedRepository =
                learningRepository as? any RoutedAttemptCorrectionRepository
            {
                try await routedRepository.append(
                    correction,
                    routedTo: profileID,
                    sourceRecord: record
                )
            } else {
                try await learningRepository.append(correction)
            }
        }
        // `WordProgress` is a rebuildable projection of immutable attempts and
        // corrections. Legacy remote snapshots are validated but never become
        // local authority and are not exported again.

        let dailyBatch = DailyQuestCanonicalMergeBatch(
            plans:
                try records
                .filter { $0.kind == .dailyPlan }
                .map { try decode(DailyQuestPlan.self, from: $0) },
            completions:
                try records
                .filter { $0.kind == .dailyCompletion }
                .map { try decode(DailyQuestCompletion.self, from: $0) },
            rewardGrants:
                try records
                .filter { $0.kind == .rewardGrant }
                .map { try decode(RewardGrant.self, from: $0) }
        )
        if !dailyBatch.isEmpty {
            if let stagedRepository = dailyQuestRepository
                as? any CausallyStagedDailyQuestHistoryRepository
            {
                _ = try await stagedRepository.stageCanonical(dailyBatch)
            } else {
                _ = try await dailyQuestRepository.mergeCanonical(dailyBatch)
            }
        }
    }

    private func applyDurably(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        guard records.allSatisfy({ $0.profileID == profileID }) else {
            throw RepositoryFamilySyncError.profileMismatch
        }
        try await validate(records, for: profileID)
        guard !records.isEmpty, let applyTransactionRepository else {
            try await applyValidated(records, for: profileID)
            return
        }

        switch try await applyTransactionRepository.begin(
            profileID: profileID,
            records: records,
            at: clock.now
        ) {
        case .alreadyCommitted:
            return
        case .pending(let transaction):
            // Use the durable copy. If a previous attempt failed after some
            // repository writes, every mutation below is idempotent and the
            // exact accepted bytes remain the recovery authority.
            try await applyValidated(
                transaction.records,
                for: transaction.profileID
            )
            _ = try await applyTransactionRepository.markCommitted(
                transactionID: transaction.id,
                at: clock.now
            )
        }
    }

    private func replay(
        _ transaction: FamilySyncPendingApplyTransaction
    ) async throws {
        let operation = {
            try await self.validate(
                transaction.records,
                for: transaction.profileID
            )
            try await self.applyValidated(
                transaction.records,
                for: transaction.profileID
            )
            _ = try await self.applyTransactionRepository?.markCommitted(
                transactionID: transaction.id,
                at: self.clock.now
            )
        }
        guard let mutationGate else {
            try await operation()
            return
        }

        await mutationGate.acquire(transaction.profileID)
        do {
            try await ProfileScopedMutationLeaseContext.$profileID
                .withValue(transaction.profileID) {
                    try await operation()
                }
            await mutationGate.release(transaction.profileID)
        } catch {
            await mutationGate.release(transaction.profileID)
            throw error
        }
    }

    /// Validates the complete batch before the first repository mutation. An
    /// envelope can never use Profile A as its routing identity while carrying
    /// a Profile B payload (especially a destructive Profile tombstone).
    public func validate(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        let persistedAttemptIDs = Set(
            try await learningRepository.attempts(
                for: profileID,
                wordPromptID: nil
            ).map(\.id)
        )
        var allowedAttemptIDs = persistedAttemptIDs
        var attemptIDsOwnedByAnotherProfile = Set<AttemptID>()
        for profile in try await profileRepository.profiles() where profile.id != profileID {
            attemptIDsOwnedByAnotherProfile.formUnion(
                try await learningRepository.attempts(
                    for: profile.id,
                    wordPromptID: nil
                ).map(\.id)
            )
        }

        for record in records {
            do {
                try record.validateCompatibility()
                if record.kind == .profileDeletion {
                    try require(record.isDeleted, record: record)
                } else {
                    // Per-record semantic tombstones are a separate versioned
                    // schema. Until then, a deleted flag on a value record must
                    // never be decoded and accidentally persisted as active data.
                    try require(!record.isDeleted, record: record)
                }
                switch record.kind {
                case .profile:
                    let value = try decode(
                        FamilySyncProfilePayload.self,
                        from: record
                    )
                    try require(
                        value.id == profileID
                            && record.recordName == "profile-\(profileID)",
                        record: record
                    )
                case .wordPoolEntry:
                    let value = try decode(WordPoolEntry.self, from: record)
                    let canonicalID = WordPoolStableIdentity.entryID(
                        profileID: value.profileID,
                        learningMode: value.learningMode,
                        normalizedText: value.normalizedText
                    )
                    try require(
                        value.profileID == profileID
                            && (record.recordName == "word-entry-\(canonicalID)"
                                // One migration read is allowed for records
                                // emitted before business-key IDs shipped.
                                // Storage canonicalizes the payload and all
                                // later exports use the stable name above.
                                || record.recordName == "word-entry-\(value.id)"
                                || value.legacyEntryIDs.contains {
                                    record.recordName == "word-entry-\($0)"
                                }),
                        record: record
                    )
                case .practiceSettings:
                    let legacyName = "practice-settings-\(profileID)"
                    if record.recordName == legacyName {
                        let value = try decode(
                            ProfilePracticeSettings.self,
                            from: record
                        )
                        try require(value.profileID == profileID, record: record)
                    } else {
                        let payload = try decode(
                            PracticeSettingsSyncPayload.self,
                            from: record
                        )
                        try require(
                            payload.schemaVersion
                                == PracticeSettingsSyncPayload.currentSchemaVersion
                                && payload.profileID == profileID
                                && record.recordName
                                    == payload.group.recordName(for: profileID),
                            record: record
                        )
                    }
                case .attempt:
                    let value = try decode(AttemptEvent.self, from: record)
                    try require(
                        value.profileID == profileID
                            && record.recordName == "attempt-\(value.id)",
                        record: record
                    )
                    if let routedRepository =
                        learningRepository
                        as? any RoutedAttemptCorrectionRepository,
                        let correctionOwner =
                            try await routedRepository
                            .correctionRoute(for: value.id)
                    {
                        try require(correctionOwner == profileID, record: record)
                    }
                    allowedAttemptIDs.insert(value.id)
                case .attemptCorrection:
                    // Ownership is checked in a second pass after every incoming
                    // attempt ID has been collected, so CloudKit event order is
                    // irrelevant.
                    let value = try decode(AttemptCorrectionEvent.self, from: record)
                    try require(
                        record.recordName == "attempt-correction-\(value.id)",
                        record: record
                    )
                case .wordProgress:
                    let value = try decode(WordProgress.self, from: record)
                    try require(
                        value.profileID == profileID
                            && record.recordName
                                == "word-progress-\(profileID)-\(value.wordPromptID)-\(value.learningMode.rawValue)",
                        record: record
                    )
                case .dailyPlan:
                    let value = try decode(DailyQuestPlan.self, from: record)
                    try require(
                        value.key.profileID == profileID
                            && record.recordName == dailyPlanRecordName(value.key),
                        record: record
                    )
                case .dailyCompletion:
                    let value = try decode(DailyQuestCompletion.self, from: record)
                    try require(
                        value.profileID == profileID
                            && value.key.profileID == profileID
                            && (record.recordName
                                == dailyCompletionRecordName(value)
                                || record.recordName
                                    == "daily-completion-\(value.id)"),
                        record: record
                    )
                case .rewardGrant:
                    let value = try decode(RewardGrant.self, from: record)
                    try require(
                        value.key.profileID == profileID
                            && (record.recordName == rewardGrantRecordName(value)
                                || record.recordName
                                    == "reward-grant-\(value.id)"),
                        record: record
                    )
                case .profileDeletion:
                    let value = try decode(ProfileDeletionTombstone.self, from: record)
                    try require(
                        record.isDeleted
                            && value.profileID == profileID
                            && record.recordName == "profile-\(profileID)",
                        record: record
                    )
                }
            } catch let error as RepositoryFamilySyncError {
                throw error
            } catch {
                throw RepositoryFamilySyncError.invalidRecordPayload(
                    recordName: record.recordName,
                    kind: record.kind
                )
            }
        }

        for record in records where record.kind == .attemptCorrection {
            let correction = try decode(AttemptCorrectionEvent.self, from: record)
            try require(
                !attemptIDsOwnedByAnotherProfile.contains(
                    correction.originalAttemptID
                ),
                record: record
            )
            if let routedRepository =
                learningRepository as? any RoutedAttemptCorrectionRepository,
                let correctionOwner =
                    try await routedRepository
                    .correctionRoute(for: correction.originalAttemptID)
            {
                try require(correctionOwner == profileID, record: record)
            }
            // A correction may legitimately arrive before its immutable
            // attempt in a later CKSyncEngine batch. The learning repository
            // stages that orphan; absence is not an identity violation.
            _ = allowedAttemptIDs.contains(correction.originalAttemptID)
        }
    }

    private func require(
        _ condition: @autoclosure () -> Bool,
        record: FamilySyncRecord
    ) throws {
        guard condition() else {
            throw RepositoryFamilySyncError.invalidRecordIdentity(
                recordName: record.recordName,
                kind: record.kind
            )
        }
    }

    private func deleteProfileData(_ profileID: ProfileID) async throws {
        try await wordPoolRepository.deleteAll(for: profileID)
        try await practiceSettingsRepository.delete(for: profileID)
        try await learningRepository.deleteLearningRecords(for: profileID)
        try await dailyQuestRepository.deleteHistory(for: profileID)
        try await profileRepository.delete(id: profileID)
        if try await childSessionRepository?.lastSelectedProfileID() == profileID {
            try await childSessionRepository?.clearLastSelectedProfileID()
        }
        try await voiceprintRepository?.delete(for: profileID)
        handwritingPreferenceRemover?.remove(for: profileID)
    }

    private func record<Value: Encodable>(
        name: String,
        profileID: ProfileID,
        kind: FamilySyncRecordKind,
        value: Value,
        updatedAt: Date,
        isDeleted: Bool = false,
        logicalRevision: FamilySyncLogicalRevision? = nil
    ) throws -> FamilySyncRecord {
        let recordDeviceID = logicalRevision?.deviceID ?? deviceID
        return FamilySyncRecord(
            recordName: name,
            profileID: profileID,
            kind: kind,
            payload: try encoder.encode(value),
            updatedAt: updatedAt,
            deviceID: recordDeviceID,
            isDeleted: isDeleted,
            logicalRevision: logicalRevision
        )
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from record: FamilySyncRecord
    ) throws -> Value {
        try decoder.decode(type, from: record.payload)
    }

    private func fileRevisionDate(_ url: URL) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate])
            as? Date ?? .distantPast
    }

    private func registerWordPromptAliases(
        for profileID: ProfileID
    ) async throws {
        guard
            let aliasRepository =
                learningRepository as? any WordPromptAliasRegistering
        else { return }

        var aliases: [WordPromptAlias] = []
        for mode in LearningMode.allCases {
            let entries = try await wordPoolRepository.entries(
                for: profileID,
                learningMode: mode,
                includingInactive: true
            )
            aliases += entries.flatMap { entry in
                entry.legacyPromptIDs.map { legacyPromptID in
                    WordPromptAlias(
                        profileID: entry.profileID,
                        learningMode: entry.learningMode,
                        legacyPromptID: legacyPromptID,
                        canonicalPromptID: entry.prompt.id
                    )
                }
            }
        }
        try await aliasRepository.registerPromptAliases(aliases)
    }

    private func dailyPlanRecordName(_ key: DailyQuestKey) -> String {
        "daily-plan-\(key.profileID)-\(key.learningMode.rawValue)-\(key.localDay)"
    }

    private func dailyCompletionRecordName(
        _ completion: DailyQuestCompletion
    ) -> String {
        guard completion.runKind == .today else {
            return "daily-completion-\(completion.id)"
        }
        return "daily-completion-\(dailyBusinessKeyToken(completion.key))"
    }

    private func rewardGrantRecordName(_ grant: RewardGrant) -> String {
        "reward-grant-\(dailyBusinessKeyToken(grant.key.dailyQuestKey))"
    }

    private func dailyBusinessKeyToken(_ key: DailyQuestKey) -> String {
        "\(key.profileID)-\(key.learningMode.rawValue)-\(key.localDay)"
    }

    private func remap(
        _ completion: DailyQuestCompletion,
        to dailyPlanID: QuestID
    ) -> DailyQuestCompletion {
        DailyQuestCompletion(
            id: completion.id,
            dailyPlanID: dailyPlanID,
            runQuestID: completion.runQuestID,
            profileID: completion.profileID,
            learningMode: completion.learningMode,
            localDay: completion.localDay,
            runKind: completion.runKind,
            points: completion.points,
            stars: completion.stars,
            completedAt: completion.completedAt
        )
    }

    private func remap(
        _ reward: RewardGrant,
        dailyPlanID: QuestID,
        completionID: DailyQuestCompletionID
    ) -> RewardGrant {
        RewardGrant(
            id: reward.id,
            key: reward.key,
            dailyPlanID: dailyPlanID,
            completionID: completionID,
            item: reward.item,
            grantedAt: reward.grantedAt
        )
    }
}

public enum RepositoryFamilySyncError: Error, Equatable, Sendable {
    case profileMismatch
    case invalidRecordIdentity(
        recordName: String,
        kind: FamilySyncRecordKind
    )
    case invalidRecordPayload(
        recordName: String,
        kind: FamilySyncRecordKind
    )
}
