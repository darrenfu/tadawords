import Foundation

public enum FamilySyncEvidenceLevel: String, Codable, CaseIterable, Sendable {
    case unit
    case integration
    case simulator
    case physicalDevice
    case human
}

public enum FamilySyncEvidenceStatus: String, Codable, Sendable {
    case passed
    case pending
}

public struct FamilySyncAcceptanceEvidence: Codable, Equatable, Sendable {
    public let id: String
    public let level: FamilySyncEvidenceLevel
    public let status: FamilySyncEvidenceStatus
    public let locator: String
    public let summary: String

    public init(
        id: String,
        level: FamilySyncEvidenceLevel,
        status: FamilySyncEvidenceStatus,
        locator: String,
        summary: String
    ) {
        self.id = id
        self.level = level
        self.status = status
        self.locator = locator
        self.summary = summary
    }
}

public struct FamilySyncManifestCoverageRow: Codable, Equatable, Sendable {
    public let fieldPath: String
    public let evidence: [FamilySyncAcceptanceEvidence]

    public init(
        fieldPath: String,
        evidence: [FamilySyncAcceptanceEvidence]
    ) {
        self.fieldPath = fieldPath
        self.evidence = evidence
    }

    public func evidence(
        at level: FamilySyncEvidenceLevel
    ) -> FamilySyncAcceptanceEvidence? {
        evidence.first { $0.level == level }
    }
}

/// Exact release-evidence matrix for every field in the sync data manifest.
///
/// Source tests are evidence only when a concrete test file is named. Device
/// and human gates remain `pending` until their exact-HEAD artifacts are
/// recorded; adding source code can never turn those gates green implicitly.
public enum FamilySyncAcceptanceCoverageMatrix {
    public static let schemaVersion = 1

    public static let rows: [FamilySyncManifestCoverageRow] =
        FamilySyncDataManifest.entries.map { entry in
            let automated = automatedCoverage(for: entry.fieldPath)
            let simulator = simulatorCoverage(for: entry.fieldPath)
            return FamilySyncManifestCoverageRow(
                fieldPath: entry.fieldPath,
                evidence: [
                    evidence(
                        fieldPath: entry.fieldPath,
                        level: .unit,
                        seed: automated.unit
                    ),
                    evidence(
                        fieldPath: entry.fieldPath,
                        level: .integration,
                        seed: automated.integration
                    ),
                    evidence(
                        fieldPath: entry.fieldPath,
                        level: .simulator,
                        seed: simulator
                    ),
                    pendingEvidence(
                        fieldPath: entry.fieldPath,
                        level: .physicalDevice,
                        gate: "gate:physical-iphone-ipad-exact-head",
                        summary:
                            "Pending exact-HEAD signed iPhone and iPad acceptance."
                    ),
                    pendingEvidence(
                        fieldPath: entry.fieldPath,
                        level: .human,
                        gate: "gate:human-family-share-recovery-acceptance",
                        summary:
                            "Pending human validation of sharing, account prompts, background delivery, accessibility, and recovery copy."
                    ),
                ]
            )
        }

    public static var releaseAccepted: Bool {
        rows.allSatisfy { row in
            row.evidence.allSatisfy { $0.status == .passed }
        }
    }

    public static var pendingEvidence: [FamilySyncAcceptanceEvidence] {
        rows.flatMap(\.evidence).filter { $0.status == .pending }
    }

    private struct EvidenceSeed {
        let locator: String
        let summary: String
    }

    private struct AutomatedCoverage {
        let unit: EvidenceSeed?
        let integration: EvidenceSeed?
    }

    private static func automatedCoverage(
        for fieldPath: String
    ) -> AutomatedCoverage {
        if fieldPath == "profiles.photoAttachment.*" {
            return coverage(
                unit: "Tests/TadaWordsDomainTests/ProfilePhotoAttachmentTests.swift",
                integration:
                    "Tests/TadaWordsApplePlatformTests/CloudKitProfilePhotoAssetTests.swift",
                summary: "Bounded JPEG validation and production CKAsset round trip."
            )
        }
        if fieldPath.hasPrefix("profiles.") {
            return coverage(
                unit: "Tests/TadaWordsContentTests/KidProfileRepositoryTests.swift",
                integration:
                    "Tests/TadaWordsContentTests/RepositoryFamilySyncRecordStoreTests.swift",
                summary:
                    "Profile persistence plus sync export/apply and device-local voiceprint preservation."
            )
        }
        if fieldPath.hasPrefix("wordPool.") {
            return coverage(
                unit:
                    "Tests/TadaWordsContentTests/LocalJSONWordPoolRepositoryTests.swift",
                integration:
                    "Tests/TadaWordsContentTests/RepositoryFamilySyncWordBusinessKeyHarnessTests.swift",
                summary: "Restartable pool storage and order-independent business-key convergence."
            )
        }
        if fieldPath.hasPrefix("practiceSettings.") {
            return coverage(
                unit:
                    "Tests/TadaWordsContentTests/PracticeSettingsSyncGroupsTests.swift",
                integration:
                    "Tests/TadaWordsContentTests/RepositoryFamilySyncRecordStoreTests.swift",
                summary: "Independent settings groups and repository sync application."
            )
        }
        if fieldPath.hasPrefix("learning.") {
            return coverage(
                unit:
                    "Tests/TadaWordsContentTests/LocalJSONLearningRecordRepositoryTests.swift",
                integration:
                    "Tests/TadaWordsContentTests/RepositoryFamilySyncCausalOrderHarnessTests.swift",
                summary:
                    "Immutable facts, durable routes, aliases, and deterministic projection rebuild."
            )
        }
        if fieldPath.hasPrefix("dailyQuests.") {
            return coverage(
                unit: "Tests/TadaWordsContentTests/DailyQuestRepositoryTests.swift",
                integration:
                    "Tests/TadaWordsContentTests/RepositoryFamilySyncCausalOrderHarnessTests.swift",
                summary: "Canonical daily facts and every-arrival-order convergence."
            )
        }
        if fieldPath == "profileDeletions.*" {
            return coverage(
                unit:
                    "Tests/TadaWordsContentTests/RepositoryFamilySyncRecordStoreTests.swift",
                integration:
                    "Tests/TadaWordsContentTests/FamilySyncDeletionDominanceHarnessTests.swift",
                summary: "Terminal local tombstone and stale-device non-resurrection."
            )
        }
        if fieldPath == "cloudDeletionLedger.*" {
            return coverage(
                unit:
                    "Tests/TadaWordsContentTests/RepositoryFamilySyncDeletionPrivacyHarnessTests.swift",
                integration:
                    "Tests/TadaWordsApplePlatformTests/CloudKitFamilyDeletionSemanticsHarnessTests.swift",
                summary: "Privacy-minimal deletion barrier and CloudKit erasure semantics."
            )
        }
        if fieldPath == "childSession.lastSelectedProfileID" {
            return coverage(
                unit: "Tests/TadaWordsContentTests/ChildSessionRepositoryTests.swift",
                integration:
                    "Tests/TadaWordsContentTests/RepositoryFamilySyncDeletionPrivacyHarnessTests.swift",
                summary: "Device-local selection persistence and deletion cleanup."
            )
        }
        if fieldPath == "familySyncPreference.*" {
            return coverage(
                unit:
                    "Tests/TadaWordsContentTests/FamilySyncPreferenceRepositoryTests.swift",
                integration:
                    "Tests/TadaWordsContentTests/LocalFirstFamilySyncCoordinatorTests.swift",
                summary: "Default-off consent persistence and coordinator opt-out gate."
            )
        }
        if fieldPath == "familySyncJournal.*" {
            return coverage(
                unit:
                    "Tests/TadaWordsContentTests/FamilySyncJournalRepositoryTests.swift",
                integration:
                    "Tests/TadaWordsContentTests/FamilySyncTwoDeviceFaultHarnessTests.swift",
                summary: "Durable outbox, retry status, restart, and two-device fault recovery."
            )
        }
        if fieldPath == "familySyncApplyTransaction.*" {
            return coverage(
                unit:
                    "Tests/TadaWordsContentTests/FamilySyncApplyTransactionRepositoryTests.swift",
                integration:
                    "Tests/TadaWordsContentTests/FamilySyncDurableReplayCoordinatorHarnessTests.swift",
                summary: "Crash-safe apply transaction, receipt, replay, and acknowledgement."
            )
        }
        if fieldPath == "cloudBindings.*"
            || fieldPath.hasPrefix("ckSyncEngine.")
        {
            return coverage(
                unit:
                    "Tests/TadaWordsApplePlatformTests/CloudKitFamilySyncRoutingTests.swift",
                integration:
                    "Tests/TadaWordsApplePlatformTests/CloudKitFamilySyncDurableInboxHarnessTests.swift",
                summary:
                    "Database routing, account isolation, engine state, and durable inbox replay."
            )
        }
        if fieldPath == "cloudProfilePhotoAssetSources.*" {
            return coverage(
                unit:
                    "Tests/TadaWordsDomainTests/ProfilePhotoAttachmentTests.swift",
                integration:
                    "Tests/TadaWordsApplePlatformTests/CloudKitProfilePhotoAssetTests.swift",
                summary: "Durable staging, acknowledgement cleanup, and crash reconstruction."
            )
        }
        if fieldPath == "notifications.scheduledRequestIdentifiers" {
            return coverage(
                unit:
                    "Tests/TadaWordsApplePlatformTests/AppleLearningNotificationSchedulerTests.swift",
                integration:
                    "Tests/TadaWordsAppShellTests/ProductionNotificationReconcilerTests.swift",
                summary: "Device-local scheduling and post-sync preference reconciliation."
            )
        }
        if fieldPath == "handwriting.legacyToolAndColorPreference" {
            return coverage(
                unit: "Tests/TadaWordsDomainTests/PracticeSettingsTests.swift",
                integration:
                    "Tests/TadaWordsContentTests/PracticeSettingsSyncGroupsTests.swift",
                summary: "Legacy tool migration and synchronized interface group."
            )
        }
        if fieldPath.hasPrefix("voiceprint.") {
            return coverage(
                unit: "Tests/TadaWordsDomainTests/VoiceprintTests.swift",
                integration:
                    "Tests/TadaWordsContentTests/RepositoryFamilySyncDeletionPrivacyHarnessTests.swift",
                summary: "Local voice representation and deletion without transport exposure."
            )
        }
        if fieldPath == "cache.pictureHints" {
            return unitOnlyCoverage(
                "Tests/TadaWordsApplePlatformTests/AppleWordPictureHintServiceTests.swift",
                summary:
                    "Disposable picture-cache behavior is unit tested; sync-boundary integration remains pending."
            )
        }
        if fieldPath == "cache.teacherWordAudio" {
            return unitOnlyCoverage(
                "Tests/TadaWordsApplePlatformTests/RemoteTeacherWordAudioProviderTests.swift",
                summary:
                    "Disposable teacher-audio cache is unit tested; sync-boundary integration remains pending."
            )
        }
        if fieldPath == "cache.musicAndSoundEffects" {
            return unitOnlyCoverage(
                "Tests/TadaWordsApplePlatformTests/ProceduralAudioTests.swift",
                summary:
                    "Local audio generation is unit tested; sync-boundary integration remains pending."
            )
        }
        if fieldPath == "cache.ocrAndRecognition" {
            return unitOnlyCoverage(
                "Tests/TadaWordsApplePlatformTests/AppleImageTextRecognitionTests.swift",
                summary:
                    "Local OCR behavior is unit tested; sync-boundary integration remains pending."
            )
        }
        if fieldPath == "views.questCalendar" {
            return coverage(
                unit:
                    "Tests/TadaWordsFeaturesTests/QuestMonthCalendarPresentationTests.swift",
                integration:
                    "Tests/TadaWordsFeaturesTests/FamilySyncUIReceiptRefreshHarnessTests.swift",
                summary: "Calendar projection and committed-receipt UI refresh."
            )
        }
        if fieldPath == "views.lastSyncPresentation" {
            return coverage(
                unit:
                    "Tests/TadaWordsContentTests/FamilySyncJournalRepositoryTests.swift",
                integration:
                    "Tests/TadaWordsContentTests/FamilySyncTwoDeviceFaultHarnessTests.swift",
                summary: "Durable sync status and restart restoration."
            )
        }
        if fieldPath.hasPrefix("views.") {
            return coverage(
                unit:
                    "Tests/TadaWordsGuardianFeaturesTests/RepositoryGuardianFamilyStoreTests.swift",
                integration:
                    "Tests/TadaWordsGuardianFeaturesTests/FamilySyncGuardianReceiptRefreshHarnessTests.swift",
                summary: "Derived parent projections and post-merge receipt refresh."
            )
        }

        return AutomatedCoverage(unit: nil, integration: nil)
    }

    /// Simulator evidence is deliberately narrower than source coverage. Each
    /// passing row must be observable through one of the six production-
    /// composition UI flows; unobserved photo, correction, cache, voiceprint,
    /// notification, and projection fields stay pending.
    private static func simulatorCoverage(
        for fieldPath: String
    ) -> EvidenceSeed? {
        let remoteBundleFields: Set<String> = [
            "profiles.id",
            "profiles.displayName",
            "wordPool.entries.id",
            "wordPool.entries.profileID",
            "wordPool.entries.prompt",
            "wordPool.entries.isActive",
            "practiceSettings.read.*",
            "practiceSettings.write.*",
            "learning.attempts.*",
            "learning.progress.*",
            "dailyQuests.completions.*",
            "dailyQuests.rewardGrants.*",
            "familySyncApplyTransaction.*",
            "views.badgeCollection",
            "views.scoresAndReports",
        ]
        if remoteBundleFields.contains(fieldPath) {
            return simulatorTest(
                "testRemoteBundleRefreshesKidAndParentSurfaces",
                summary:
                    "Remote Profile facts commit through the durable apply path and refresh Kid and Parent surfaces."
            )
        }

        if fieldPath == "familySyncJournal.*" {
            return simulatorTest(
                "testOfflinePendingSurvivesTerminationAndClearsAfterOnlineAck",
                summary:
                    "Offline pending state survives process termination and clears only after an online acknowledgement."
            )
        }

        if fieldPath == "profileDeletions.*" {
            return simulatorTest(
                "testRemoteDeletionAbandonsActiveKidAndReturnsToChooser",
                summary:
                    "A terminal remote deletion removes the active child and recovers Kid navigation."
            )
        }

        if fieldPath == "childSession.lastSelectedProfileID" {
            return simulatorTest(
                "testRemoteDeletionRecoversParentEditorToAddChild",
                summary:
                    "A terminal remote deletion clears the remembered child and recovers the Parent editor."
            )
        }

        if fieldPath == "views.lastSyncPresentation" {
            return simulatorTest(
                "testSignedOutAndRestrictedStatesRemainParentVisible",
                summary:
                    "Signed-out and restricted iCloud states remain visible on the Parent sync surface."
            )
        }

        return nil
    }

    private static func simulatorTest(
        _ method: String,
        summary: String
    ) -> EvidenceSeed {
        EvidenceSeed(
            locator:
                "Tests/TadaWordsUITests/TadaWordsFamilySyncUITests.swift#\(method)",
            summary: summary
        )
    }

    private static func coverage(
        unit: String,
        integration: String,
        summary: String
    ) -> AutomatedCoverage {
        AutomatedCoverage(
            unit: EvidenceSeed(locator: unit, summary: summary),
            integration: EvidenceSeed(locator: integration, summary: summary)
        )
    }

    private static func unitOnlyCoverage(
        _ unit: String,
        summary: String
    ) -> AutomatedCoverage {
        AutomatedCoverage(
            unit: EvidenceSeed(locator: unit, summary: summary),
            integration: nil
        )
    }

    private static func evidence(
        fieldPath: String,
        level: FamilySyncEvidenceLevel,
        seed: EvidenceSeed?
    ) -> FamilySyncAcceptanceEvidence {
        guard let seed else {
            let gate =
                level == .simulator
                ? "gate:simulator-family-sync-e2e"
                : "gate:\(level.rawValue)-coverage-\(slug(fieldPath))"
            return pendingEvidence(
                fieldPath: fieldPath,
                level: level,
                gate: gate,
                summary: "No concrete passing \(level.rawValue) artifact is recorded yet."
            )
        }
        return FamilySyncAcceptanceEvidence(
            id: "\(level.rawValue):\(slug(fieldPath))",
            level: level,
            status: .passed,
            locator: seed.locator,
            summary: seed.summary
        )
    }

    private static func pendingEvidence(
        fieldPath: String,
        level: FamilySyncEvidenceLevel,
        gate: String,
        summary: String
    ) -> FamilySyncAcceptanceEvidence {
        FamilySyncAcceptanceEvidence(
            id: "pending:\(level.rawValue):\(slug(fieldPath))",
            level: level,
            status: .pending,
            locator: gate,
            summary: summary
        )
    }

    private static func slug(_ value: String) -> String {
        value.lowercased().map { character in
            character.isLetter || character.isNumber ? character : "-"
        }.reduce(into: "") { result, character in
            if character != "-" || result.last != "-" {
                result.append(character)
            }
        }.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
