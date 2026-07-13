import Foundation
import TadaWordsDomain

public actor RepositoryFamilySyncRecordStore: FamilySyncRecordStore {
    private let profileRepository: any KidProfileRepository
    private let wordPoolRepository: LocalJSONWordPoolRepository
    private let practiceSettingsRepository: LocalJSONPracticeSettingsRepository
    private let learningRepository: any ProfileLearningRecordRepository
    private let dailyQuestRepository: any DailyQuestHistoryRepository
    private let tombstoneRepository: any ProfileDeletionTombstoneRepository
    private let deviceID: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        profileRepository: any KidProfileRepository,
        wordPoolRepository: LocalJSONWordPoolRepository,
        practiceSettingsRepository: LocalJSONPracticeSettingsRepository,
        learningRepository: any ProfileLearningRecordRepository,
        dailyQuestRepository: any DailyQuestHistoryRepository,
        tombstoneRepository: any ProfileDeletionTombstoneRepository,
        deviceID: String
    ) {
        self.profileRepository = profileRepository
        self.wordPoolRepository = wordPoolRepository
        self.practiceSettingsRepository = practiceSettingsRepository
        self.learningRepository = learningRepository
        self.dailyQuestRepository = dailyQuestRepository
        self.tombstoneRepository = tombstoneRepository
        self.deviceID = deviceID
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
                value: syncableProfile(profile),
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
                    updatedAt: max(entry.lastQueuedAt, wordRevision)
                )
            }
        }

        if let settings = try await practiceSettingsRepository.settings(for: profileID) {
            records.append(
                try record(
                    name: "practice-settings-\(profileID)",
                    profileID: profileID,
                    kind: .practiceSettings,
                    value: settings,
                    updatedAt: settingsRevision
                )
            )
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
            for correction in try await learningRepository.corrections(
                for: attempt.id
            ) {
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
        }
        for progress in try await learningRepository.allProgress(for: profileID) {
            records.append(
                try record(
                    name:
                        "word-progress-\(profileID)-\(progress.wordPromptID)-\(progress.learningMode.rawValue)",
                    profileID: profileID,
                    kind: .wordProgress,
                    value: progress,
                    updatedAt: progress.lastEncounterAt ?? .distantPast
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
                name: "daily-completion-\(completion.id)",
                profileID: profileID,
                kind: .dailyCompletion,
                value: completion,
                updatedAt: completion.completedAt
            )
        }
        records += try await dailyQuestRepository.rewardGrants(for: profileID).map {
            grant in
            try record(
                name: "reward-grant-\(grant.id)",
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
        guard records.allSatisfy({ $0.profileID == profileID }) else {
            throw RepositoryFamilySyncError.profileMismatch
        }
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

        for record in records where record.kind == .profile {
            try await tombstoneRepository.delete(for: profileID)
            let incoming = try decode(KidProfile.self, from: record)
            let localVoiceprintStatus =
                try await profileRepository.profile(
                    id: profileID
                )?.voiceprintStatus ?? .notEnrolled
            try await profileRepository.save(
                profile(incoming, preserving: localVoiceprintStatus)
            )
        }
        for record in records where record.kind == .wordPoolEntry {
            try await wordPoolRepository.mergeSynced(
                try decode(WordPoolEntry.self, from: record)
            )
        }
        for record in records where record.kind == .practiceSettings {
            try await practiceSettingsRepository.save(
                try decode(ProfilePracticeSettings.self, from: record)
            )
        }
        for record in records where record.kind == .attempt {
            try await learningRepository.append(
                try decode(AttemptEvent.self, from: record)
            )
        }
        for record in records where record.kind == .attemptCorrection {
            try await learningRepository.append(
                try decode(AttemptCorrectionEvent.self, from: record)
            )
        }
        for record in records where record.kind == .wordProgress {
            try await learningRepository.save(
                try decode(WordProgress.self, from: record)
            )
        }

        var planByKey: [DailyQuestKey: DailyQuestPlan] = [:]
        for record in records where record.kind == .dailyPlan {
            let incoming = try decode(DailyQuestPlan.self, from: record)
            planByKey[incoming.key] =
                try await dailyQuestRepository
                .createPlanIfAbsent(incoming)
        }
        let rewards = try Dictionary(
            uniqueKeysWithValues:
                records
                .filter { $0.kind == .rewardGrant }
                .map { record in
                    let reward = try decode(RewardGrant.self, from: record)
                    return (reward.completionID, reward)
                }
        )
        for record in records where record.kind == .dailyCompletion {
            let incoming = try decode(DailyQuestCompletion.self, from: record)
            let persistedState = try await dailyQuestRepository.state(
                for: incoming.key
            )
            let storedPlan = planByKey[incoming.key] ?? persistedState.plan
            guard let storedPlan else { continue }
            let completion = remap(incoming, to: storedPlan.id)
            let reward = rewards[incoming.id].map {
                remap($0, dailyPlanID: storedPlan.id, completionID: completion.id)
            }
            _ = try await dailyQuestRepository.recordCompletion(
                completion,
                proposedRewardGrant: reward
            )
        }
    }

    private func deleteProfileData(_ profileID: ProfileID) async throws {
        try await wordPoolRepository.deleteAll(for: profileID)
        try await practiceSettingsRepository.delete(for: profileID)
        try await learningRepository.deleteLearningRecords(for: profileID)
        try await dailyQuestRepository.deleteHistory(for: profileID)
        try await profileRepository.delete(id: profileID)
    }

    private func syncableProfile(_ profile: KidProfile) -> KidProfile {
        self.profile(profile, preserving: .notEnrolled)
    }

    private func profile(
        _ profile: KidProfile,
        preserving voiceprintStatus: VoiceprintEnrollmentStatus
    ) -> KidProfile {
        KidProfile(
            id: profile.id,
            displayName: profile.displayName,
            avatar: profile.avatar,
            selectedWorld: profile.selectedWorld,
            starterWorld: profile.starterWorld,
            guardianUnlockedWorlds: profile.guardianUnlockedWorlds,
            schoolGrade: profile.schoolGrade,
            ageYears: profile.ageYears,
            voiceprintStatus: voiceprintStatus,
            createdAt: profile.createdAt,
            updatedAt: profile.updatedAt
        )
    }

    private func record<Value: Encodable>(
        name: String,
        profileID: ProfileID,
        kind: FamilySyncRecordKind,
        value: Value,
        updatedAt: Date,
        isDeleted: Bool = false
    ) throws -> FamilySyncRecord {
        FamilySyncRecord(
            recordName: name,
            profileID: profileID,
            kind: kind,
            payload: try encoder.encode(value),
            updatedAt: updatedAt,
            deviceID: deviceID,
            isDeleted: isDeleted
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

    private func dailyPlanRecordName(_ key: DailyQuestKey) -> String {
        "daily-plan-\(key.profileID)-\(key.learningMode.rawValue)-\(key.localDay)"
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
}
