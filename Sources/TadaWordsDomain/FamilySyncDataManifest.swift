import Foundation

public enum FamilySyncDataClassification: String, Codable, CaseIterable, Sendable {
    case synchronized
    case derived
    case deviceLocal
}

public struct FamilySyncDataManifestEntry: Codable, Equatable, Sendable {
    public let fieldPath: String
    public let classification: FamilySyncDataClassification
    public let recordKind: FamilySyncRecordKind?
    public let rationale: String
    /// Stable IDs consumed by release gates. `snapshot:` IDs prove every
    /// persisted field received an explicit sync classification; `code:` IDs
    /// point to a reviewed runtime/cache projection when no snapshot field is
    /// involved.
    public let evidenceIDs: Set<String>

    public init(
        fieldPath: String,
        classification: FamilySyncDataClassification,
        recordKind: FamilySyncRecordKind? = nil,
        rationale: String,
        evidenceIDs: Set<String>
    ) {
        self.fieldPath = fieldPath
        self.classification = classification
        self.recordKind = recordKind
        self.rationale = rationale
        self.evidenceIDs = evidenceIDs
    }
}

/// Machine-readable counterpart to Docs/FAMILY-SYNC-DATA-MANIFEST.md.
/// Additions to a persisted snapshot must be classified here before release.
public enum FamilySyncDataManifest {
    public static let schemaVersion = 1

    public static let entries: [FamilySyncDataManifestEntry] = [
        sync("profiles.id", .profile, "Stable family identity."),
        sync("profiles.displayName", .profile, "Parent-authored Profile metadata."),
        sync("profiles.avatar", .profile, "Bounded source avatar; photos move as CKAsset."),
        sync("profiles.selectedWorld", .profile, "Child-visible Profile choice."),
        sync("profiles.starterWorld", .profile, "World progression input."),
        sync("profiles.guardianUnlockedWorlds", .profile, "Parent-authored override."),
        sync("profiles.selectedCartoonIconAssetID", .profile, "Child-visible Profile choice."),
        sync("profiles.selectedTreasureAvatar", .profile, "Child-visible earned choice."),
        sync("profiles.schoolGrade", .profile, "Parent-authored learning level."),
        sync("profiles.ageYears", .profile, "Parent-authored learning level."),
        sync(
            "profiles.photoAttachment.*", .profile,
            "Bounded CKAsset metadata and prepared JPEG bytes."),
        local(
            "profiles.voiceprintStatus",
            "Enrollment is independently derived from this device Keychain. The dedicated synchronized Profile wire payload omits this field entirely, including sentinel values."
        ),
        sync("profiles.createdAt", .profile, "Stable Profile history."),
        sync("profiles.updatedAt", .profile, "Audit metadata; logical revision decides conflicts."),

        sync("wordPool.entries.id", .wordPoolEntry, "Stable membership identity."),
        sync("wordPool.entries.profileID", .wordPoolEntry, "Profile scope."),
        sync("wordPool.entries.prompt", .wordPoolEntry, "Parent-selected learning content."),
        sync("wordPool.entries.addedAt", .wordPoolEntry, "Queue history."),
        sync("wordPool.entries.source", .wordPoolEntry, "Content provenance."),
        sync("wordPool.entries.isActive", .wordPoolEntry, "Removal/reactivation state."),
        sync("wordPool.entries.lastQueuedAt", .wordPoolEntry, "Queue order input."),
        sync("wordPool.entries.positionInLastBatch", .wordPoolEntry, "Queue order input."),
        sync(
            "wordPool.entries.legacyEntryIDs", .wordPoolEntry,
            "One-way aliases for pre-business-key membership records."),
        sync(
            "wordPool.entries.legacyPromptIDs", .wordPoolEntry,
            "One-way aliases that retain immutable attempt history."),
        sync(
            "wordPool.entries.logicalRevision", .wordPoolEntry,
            "Removal, reactivation, and move conflict authority."),

        sync("practiceSettings.profileID", .practiceSettings, "Profile scope."),
        sync("practiceSettings.read.*", .practiceSettings, "Parent-selected Read quest policy."),
        sync("practiceSettings.write.*", .practiceSettings, "Parent-selected Write quest policy."),
        sync("practiceSettings.audio.*", .practiceSettings, "Parent-selected audio preference."),
        sync(
            "practiceSettings.notifications.*", .practiceSettings,
            "Parent-selected notification preference."),
        sync(
            "practiceSettings.interface.leftHandedLayoutEnabled", .practiceSettings,
            "Profile interface choice."),
        sync(
            "practiceSettings.interface.selectedHandwritingTool", .practiceSettings,
            "Profile handwriting tool choice; ink color remains device-local."),
        sync(
            "practiceSettings.wordRecommendationMode", .practiceSettings,
            "Parent-selected word policy."),

        sync("learning.attempts.*", .attempt, "Immutable learning event with stable UUID."),
        sync(
            "learning.corrections.*", .attemptCorrection,
            "Immutable guardian correction with stable UUID."),
        local(
            "learning.correctionRoutes.*",
            "Durable source-envelope routing for correction-first delivery."),
        derived(
            "learning.promptAliases.*",
            "Durable local resolver rebuilt from synchronized WordPool aliases; immutable attempts keep their original prompt IDs."
        ),
        derived(
            "learning.progress.*", .wordProgress,
            "Rebuilt from attempts and corrections; never conflict authority."),

        sync("dailyQuests.plans.*", .dailyPlan, "Canonical Profile, mode, and local-day plan."),
        sync("dailyQuests.completions.*", .dailyCompletion, "Canonical quest completion fact."),
        sync("dailyQuests.rewardGrants.*", .rewardGrant, "Stable earned reward fact."),
        sync(
            "dailyQuests.pendingCompletions.*", .dailyCompletion,
            "Durable causal staging until its plan and reward arrive."),
        sync(
            "dailyQuests.pendingRewardGrants.*", .rewardGrant,
            "Durable causal staging until its plan and completion arrive."),
        sync("profileDeletions.*", .profileDeletion, "Terminal non-resurrection tombstone."),
        sync(
            "cloudDeletionLedger.*", .profileDeletion,
            "Privacy-minimal owner barrier retained outside the erasable Profile zone."),

        syncEnvelope("familySyncEnvelope.recordName", "Stable CloudKit record routing name."),
        syncEnvelope("familySyncEnvelope.profileID", "Profile scope for every record."),
        syncEnvelope("familySyncEnvelope.kindIdentifier", "Versioned payload type."),
        syncEnvelope("familySyncEnvelope.payload", "Canonical record-kind payload bytes."),
        syncEnvelope("familySyncEnvelope.updatedAt", "Audit and display timestamp."),
        syncEnvelope("familySyncEnvelope.isDeleted", "Record-level deletion marker."),
        syncEnvelope("familySyncEnvelope.schemaVersion", "Writer schema boundary."),
        syncEnvelope(
            "familySyncEnvelope.minimumReadableVersion",
            "Fail-closed reader compatibility boundary."),
        syncEnvelope(
            "familySyncEnvelope.logicalRevision.counter",
            "Monotonic conflict-order component."),
        syncEnvelope(
            "familySyncEnvelope.logicalRevision.deviceID",
            "Random per-install UUID used only to break equal logical revisions; it is not an Apple hardware, advertising, or account identifier."
        ),
        syncEnvelope("familySyncEnvelope.payloadChecksum", "Integrity boundary."),
        syncEnvelope("familySyncEnvelope.payloadSize", "Payload-size validation boundary."),

        local("childSession.lastSelectedProfileID", "Launch convenience differs by device."),
        local(
            "familySyncDeviceIdentity.installationUUIDFile",
            "The source file stays on this installation; its opaque UUID value is copied into synchronized logical-revision envelopes for deterministic conflict resolution."
        ),
        local("familySyncPreference.*", "Consent and opt-out are explicit on each device."),
        local("familySyncJournal.*", "Transport recovery metadata; no child payload."),
        local(
            "familySyncApplyTransaction.*",
            "Crash-recovery payload is local-only; committed receipts are privacy-minimal."),
        local(
            "cloudBindings.*",
            "Account and database routing belongs to this installation; terminal Profile metadata is purged without touching unrelated zones."
        ),
        local(
            "ckSyncEngine.privateState",
            "Opaque private-database change token; terminal Profile pending/outgoing changes are removed by zone."
        ),
        local(
            "ckSyncEngine.sharedState",
            "Opaque shared-database change token; terminal Profile pending/outgoing changes are removed by zone."
        ),
        local(
            "cloudProfilePhotoAssetSources.*",
            "Crash-restartable CKAsset upload sources reconstructed from the local Profile snapshot and purged on terminal removal."
        ),
        local(
            "notifications.scheduledRequestIdentifiers", "OS requests are recreated on each device."
        ),
        local(
            "handwriting.legacyToolAndColorPreference",
            "Legacy migration residue; the selected tool moves into Profile settings while hidden ink color stays local."
        ),
        local(
            "voiceprint.keychainTemplate",
            "Biometric-like child voice data never leaves the device."),
        local("voiceprint.enrollmentSamples", "Raw audio is discarded and never synchronized."),
        local("cache.pictureHints", "Disposable decoded bundled-asset cache."),
        local("cache.teacherWordAudio", "Disposable download cache."),
        local("cache.musicAndSoundEffects", "Rendered asset cache."),
        local("cache.ocrAndRecognition", "Disposable inference cache."),

        derived("views.questCalendar", "Projection of canonical completions."),
        derived("views.worldUnlocks", "Projection of Today completions and guardian overrides."),
        derived("views.badgeCollection", "Projection of reward grants."),
        derived("views.scoresAndReports", "Projection of attempts, corrections, and completions."),
        derived("views.lastSyncPresentation", "Projection of the device-local journal status."),
    ]

    public static var synchronizedRecordKinds: Set<FamilySyncRecordKind> {
        Set(
            entries.compactMap { entry in
                guard entry.classification == .synchronized else { return nil }
                return entry.recordKind
            })
    }

    private static func sync(
        _ fieldPath: String,
        _ recordKind: FamilySyncRecordKind,
        _ rationale: String
    ) -> FamilySyncDataManifestEntry {
        FamilySyncDataManifestEntry(
            fieldPath: fieldPath,
            classification: .synchronized,
            recordKind: recordKind,
            rationale: rationale,
            evidenceIDs: evidenceIDs(for: fieldPath)
        )
    }

    private static func syncEnvelope(
        _ fieldPath: String,
        _ rationale: String
    ) -> FamilySyncDataManifestEntry {
        FamilySyncDataManifestEntry(
            fieldPath: fieldPath,
            classification: .synchronized,
            rationale: rationale,
            evidenceIDs: evidenceIDs(for: fieldPath)
        )
    }

    private static func derived(
        _ fieldPath: String,
        _ recordKind: FamilySyncRecordKind?,
        _ rationale: String
    ) -> FamilySyncDataManifestEntry {
        FamilySyncDataManifestEntry(
            fieldPath: fieldPath,
            classification: .derived,
            recordKind: recordKind,
            rationale: rationale,
            evidenceIDs: evidenceIDs(for: fieldPath)
        )
    }

    private static func derived(
        _ fieldPath: String,
        _ rationale: String
    ) -> FamilySyncDataManifestEntry {
        derived(fieldPath, nil, rationale)
    }

    private static func local(
        _ fieldPath: String,
        _ rationale: String
    ) -> FamilySyncDataManifestEntry {
        FamilySyncDataManifestEntry(
            fieldPath: fieldPath,
            classification: .deviceLocal,
            rationale: rationale,
            evidenceIDs: evidenceIDs(for: fieldPath)
        )
    }

    private static func evidenceIDs(for fieldPath: String) -> Set<String> {
        let snapshotFields: [String: [String]] = [
            "profiles.id": [
                "snapshot:KidProfileSnapshot.schemaVersion",
                "snapshot:KidProfileSnapshot.profiles",
            ],
            "wordPool.entries.id": [
                "snapshot:WordPoolSnapshot.schemaVersion",
                "snapshot:WordPoolSnapshot.entries",
            ],
            "practiceSettings.profileID": [
                "snapshot:PracticeSettingsSnapshot.schemaVersion",
                "snapshot:PracticeSettingsSnapshot.settings",
            ],
            "learning.attempts.*": [
                "snapshot:LearningRecordSnapshot.schemaVersion",
                "snapshot:LearningRecordSnapshot.projectionAlgorithmVersion",
                "snapshot:LearningRecordSnapshot.canonicalFactsChecksum",
                "snapshot:LearningRecordSnapshot.attempts",
            ],
            "learning.corrections.*": [
                "snapshot:LearningRecordSnapshot.corrections"
            ],
            "learning.correctionRoutes.*": [
                "snapshot:LearningRecordSnapshot.correctionRoutes"
            ],
            "learning.promptAliases.*": [
                "snapshot:LearningRecordSnapshot.promptAliases"
            ],
            "learning.progress.*": [
                "snapshot:LearningRecordSnapshot.progress"
            ],
            "dailyQuests.plans.*": [
                "snapshot:DailyQuestSnapshot.schemaVersion",
                "snapshot:DailyQuestSnapshot.canonicalBusinessKeyVersion",
                "snapshot:DailyQuestSnapshot.plans",
            ],
            "dailyQuests.completions.*": [
                "snapshot:DailyQuestSnapshot.completions"
            ],
            "dailyQuests.rewardGrants.*": [
                "snapshot:DailyQuestSnapshot.rewardGrants"
            ],
            "dailyQuests.pendingCompletions.*": [
                "snapshot:DailyQuestSnapshot.pendingCompletions"
            ],
            "dailyQuests.pendingRewardGrants.*": [
                "snapshot:DailyQuestSnapshot.pendingRewardGrants"
            ],
            "childSession.lastSelectedProfileID": [
                "snapshot:ChildSessionSnapshot.schemaVersion",
                "snapshot:ChildSessionSnapshot.lastSelectedProfileID",
            ],
            "familySyncPreference.*": [
                "snapshot:FamilySyncPreferenceSnapshot.schemaVersion",
                "snapshot:FamilySyncPreferenceSnapshot.isEnabled",
                "snapshot:FamilySyncPreferenceSnapshot.disclosureVersion",
                "snapshot:FamilySyncPreferenceSnapshot.consentedAt",
                "snapshot:FamilySyncPreferenceSnapshot.updatedAt",
            ],
            "familySyncJournal.*": [
                "snapshot:FamilySyncJournalSnapshot.schemaVersion",
                "snapshot:FamilySyncJournalSnapshot.localManifest",
                "snapshot:FamilySyncJournalSnapshot.acknowledgedManifest",
                "snapshot:FamilySyncJournalSnapshot.outbox",
                "snapshot:FamilySyncJournalSnapshot.status",
            ],
            "familySyncApplyTransaction.*": [
                "snapshot:FamilySyncApplyTransactionSnapshot.schemaVersion",
                "snapshot:FamilySyncApplyTransactionSnapshot.pending",
                "snapshot:FamilySyncApplyTransactionSnapshot.lastCommitted",
            ],
        ]
        if fieldPath == "practiceSettings.interface.selectedHandwritingTool" {
            return [
                "test:PracticeSettingsSyncGroupsTests",
                "test:PracticeSettingsTests.testLegacyInterfacePreferencesDefaultToPencil",
            ]
        }
        return Set(
            snapshotFields[fieldPath]
                ?? ["code:family-sync-manifest:\(fieldPath)"]
        )
    }
}
