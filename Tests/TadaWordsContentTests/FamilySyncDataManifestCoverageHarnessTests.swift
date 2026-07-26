import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsContent

final class FamilySyncDataManifestCoverageHarnessTests: XCTestCase {
    func testEveryRecordKindHasOneExplicitTransportClassification() {
        let synchronized = FamilySyncDataManifest.synchronizedRecordKinds
        let expectedSynchronized: Set<FamilySyncRecordKind> = [
            .profile,
            .wordPoolEntry,
            .practiceSettings,
            .attempt,
            .attemptCorrection,
            .dailyPlan,
            .dailyCompletion,
            .rewardGrant,
            .profileDeletion,
        ]
        let expectedAllKinds = expectedSynchronized.union([.wordProgress])

        XCTAssertEqual(Set(FamilySyncRecordKind.allCases), expectedAllKinds)
        XCTAssertEqual(synchronized, expectedSynchronized)
        let progressEntries = FamilySyncDataManifest.entries.filter {
            $0.recordKind == .wordProgress
        }
        XCTAssertFalse(progressEntries.isEmpty)
        XCTAssertTrue(
            progressEntries.allSatisfy { $0.classification == .derived },
            "wordProgress must be manifest-visible but never authoritative transport data"
        )
        XCTAssertEqual(
            Set(
                FamilySyncDataManifest.entries.compactMap { entry in
                    guard entry.classification == .synchronized,
                        entry.recordKind == nil
                    else { return nil }
                    return entry.fieldPath
                }
            ),
            approvedCommonEnvelopeFields
        )
    }

    func testManifestEntriesHaveStableMachineEvidenceIDs() {
        let entries = FamilySyncDataManifest.entries
        XCTAssertEqual(Set(entries.map(\.fieldPath)).count, entries.count)

        for entry in entries {
            XCTAssertFalse(entry.fieldPath.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertFalse(entry.rationale.trimmingCharacters(in: .whitespaces).isEmpty)
            guard let evidenceIDs = evidenceIDs(for: entry) else {
                XCTFail(
                    "\(entry.fieldPath) has no machine-readable evidenceIDs property"
                )
                continue
            }
            XCTAssertFalse(
                evidenceIDs.isEmpty,
                "\(entry.fieldPath) must cite at least one stable evidence ID"
            )
            XCTAssertTrue(
                evidenceIDs.allSatisfy {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            )
        }
    }

    func testPrivacyBoundaryKeepsSensitiveDeviceDataOutOfSynchronizedRecords() {
        let classifications = Dictionary(
            uniqueKeysWithValues: FamilySyncDataManifest.entries.map {
                ($0.fieldPath, $0.classification)
            }
        )

        let synchronized = [
            "profiles.displayName",
            "profiles.photoAttachment.*",
            "wordPool.entries.prompt",
            "learning.attempts.*",
            "familySyncEnvelope.logicalRevision.deviceID",
        ]
        let deviceLocal = [
            "childSession.lastSelectedProfileID",
            "familySyncDeviceIdentity.installationUUIDFile",
            "familySyncPreference.*",
            "notifications.scheduledRequestIdentifiers",
            "voiceprint.keychainTemplate",
            "voiceprint.enrollmentSamples",
            "cache.ocrAndRecognition",
        ]
        let derived = [
            "learning.progress.*",
            "views.scoresAndReports",
        ]

        for fieldPath in synchronized {
            XCTAssertEqual(
                classifications[fieldPath],
                .synchronized,
                "\(fieldPath) is part of the reviewed CloudKit payload boundary"
            )
        }
        for fieldPath in deviceLocal {
            XCTAssertEqual(
                classifications[fieldPath],
                .deviceLocal,
                "\(fieldPath) must never cross the device boundary"
            )
        }
        for fieldPath in derived {
            XCTAssertEqual(
                classifications[fieldPath],
                .derived,
                "\(fieldPath) must be rebuilt locally from canonical facts"
            )
        }

        XCTAssertFalse(
            FamilySyncDataManifest.entries.contains {
                $0.classification == .synchronized
                    && $0.fieldPath.localizedCaseInsensitiveContains("voiceprint")
            },
            "No voiceprint field may become synchronized"
        )
    }

    func testSynchronizedFieldAllowlistRequiresPrivacyReviewForEveryNewPath() {
        let actual = Set(
            FamilySyncDataManifest.entries.compactMap { entry in
                entry.classification == .synchronized ? entry.fieldPath : nil
            }
        )

        XCTAssertEqual(actual, approvedSynchronizedFields)
    }

    func testEncodedEnvelopeMetadataMatchesReviewedPrivacyContract() throws {
        let record = FamilySyncRecord(
            recordName: "privacy-contract",
            profileID: ProfileID(),
            kind: .profile,
            payload: Data("{}".utf8),
            updatedAt: Date(timeIntervalSince1970: 1),
            deviceID: "4F7D9FA6-184E-4BB4-9A16-C4D92BE2AE11",
            logicalRevision: FamilySyncLogicalRevision(
                counter: 3,
                deviceID: "4F7D9FA6-184E-4BB4-9A16-C4D92BE2AE11"
            )
        )
        let data = try JSONEncoder().encode(FamilySyncEnvelope(record: record))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(
            Set(object.keys),
            Set(
                approvedCommonEnvelopeFields.map {
                    $0.replacingOccurrences(of: "familySyncEnvelope.", with: "")
                        .split(separator: ".", maxSplits: 1)
                        .first
                        .map(String.init) ?? ""
                }))
        let revision = try XCTUnwrap(
            object["logicalRevision"] as? [String: Any]
        )
        XCTAssertEqual(Set(revision.keys), ["counter", "deviceID"])
        XCTAssertEqual(
            revision["deviceID"] as? String,
            "4F7D9FA6-184E-4BB4-9A16-C4D92BE2AE11"
        )
    }

    func testSynchronizedPayloadJSONKeysMatchReviewedPrivacyContracts() throws {
        let reviewedPayloadKinds: Set<FamilySyncRecordKind> = [
            .profile,
            .wordPoolEntry,
            .practiceSettings,
            .attempt,
            .attemptCorrection,
            .dailyPlan,
            .dailyCompletion,
            .rewardGrant,
            .profileDeletion,
        ]
        XCTAssertEqual(
            reviewedPayloadKinds,
            FamilySyncDataManifest.synchronizedRecordKinds,
            "Every synchronized record kind needs a concrete JSON payload contract below."
        )

        let profileID = ProfileID()
        let date = Date(timeIntervalSince1970: 1_725_000_000)
        let prompt = try WordPrompt(
            learningMode: .read,
            text: "dog",
            audioCue: .contextual(
                "I see a dog.",
                pronunciationKey: "dog"
            )
        )
        let revision = FamilySyncLogicalRevision(
            counter: 7,
            deviceID: "privacy-contract-device"
        )

        let photoProfile = FamilySyncProfilePayload(
            profile: KidProfile(
                id: profileID,
                displayName: "Reader",
                avatar: .embeddedPhoto(
                    data: Data([0xFF, 0xD8, 0xFF]),
                    source: .camera
                ),
                selectedWorld: .moonpetalKingdom,
                starterWorld: .pawsAndPines,
                guardianUnlockedWorlds: [.moonpetalKingdom, .pawsAndPines],
                selectedCartoonIconAssetID: "rainbow-unicorn",
                schoolGrade: .preK,
                ageYears: 4,
                voiceprintStatus: .enrolled(
                    modelVersion: "must-not-sync",
                    enrolledAt: date
                ),
                createdAt: date,
                updatedAt: date.addingTimeInterval(5)
            )
        )
        let treasureProfile = FamilySyncProfilePayload(
            profile: KidProfile(
                id: profileID,
                displayName: "Reader",
                avatar: .cartoonAnimal(assetID: "smiling-fox"),
                selectedWorld: .moonpetalKingdom,
                selectedTreasureAvatar: TreasureAvatarSelection(
                    rewardItemID: RewardItemID(rawValue: "moonpetal-crown"),
                    iconAssetID: "crown.fill"
                ),
                schoolGrade: .preK,
                ageYears: 4,
                voiceprintStatus: .needsRefresh,
                createdAt: date
            )
        )
        let profileRootKeys = try topLevelKeyUnion(
            [photoProfile, treasureProfile]
        )
        XCTAssertEqual(
            profileRootKeys,
            [
                "id", "displayName", "avatar", "selectedWorld", "starterWorld",
                "guardianUnlockedWorlds", "selectedCartoonIconAssetID",
                "selectedTreasureAvatar", "schoolGrade", "ageYears",
                "createdAt", "updatedAt",
            ],
            "Every encoded profile field needs an explicit privacy review."
        )
        assertStoredProperties(
            of: photoProfile,
            equal: profileRootKeys,
            contract: "profile"
        )
        assertStoredProperties(
            of: try XCTUnwrap(treasureProfile.selectedTreasureAvatar),
            equal: ["rewardItemID", "iconAssetID"],
            contract: "profile.selectedTreasureAvatar"
        )
        try assertJSONKeyContract(
            photoProfile,
            contract: "profile.photo",
            expected: [
                "avatar": ["photo"],
                "avatar.photo": ["assetID", "source"],
            ]
        )
        try assertJSONKeyContract(
            treasureProfile,
            contract: "profile.treasure",
            expected: [
                "avatar": ["cartoonAnimal"],
                "avatar.cartoonAnimal": ["assetID"],
                "selectedTreasureAvatar": ["rewardItemID", "iconAssetID"],
            ]
        )

        let wordPoolEntry = WordPoolEntry(
            profileID: profileID,
            prompt: prompt,
            addedAt: date,
            source: .guardianManual,
            isActive: true,
            lastQueuedAt: date.addingTimeInterval(10),
            positionInLastBatch: 2,
            legacyEntryIDs: [WordPoolEntryID()],
            legacyPromptIDs: [WordPromptID()],
            logicalRevision: revision
        )
        try assertJSONKeyContract(
            wordPoolEntry,
            contract: "wordPoolEntry",
            expected: [
                "": [
                    "id", "profileID", "prompt", "addedAt", "source", "isActive",
                    "lastQueuedAt", "positionInLastBatch", "legacyEntryIDs",
                    "legacyPromptIDs", "logicalRevision",
                ],
                "prompt": [
                    "id", "learningMode", "displayText", "normalizedText",
                    "audioCue",
                ],
                "prompt.audioCue": ["spokenContext", "pronunciationKey"],
                "logicalRevision": ["counter", "deviceID"],
            ]
        )
        assertStoredProperties(
            of: wordPoolEntry,
            equal: [
                "id", "profileID", "prompt", "addedAt", "source", "isActive",
                "lastQueuedAt", "positionInLastBatch", "legacyEntryIDs",
                "legacyPromptIDs", "logicalRevision",
            ],
            contract: "wordPoolEntry"
        )
        assertStoredProperties(
            of: prompt,
            equal: [
                "id", "learningMode", "displayText", "normalizedText", "audioCue",
            ],
            contract: "wordPoolEntry.prompt"
        )
        assertStoredProperties(
            of: prompt.audioCue,
            equal: ["spokenContext", "pronunciationKey"],
            contract: "wordPoolEntry.prompt.audioCue"
        )
        assertStoredProperties(
            of: revision,
            equal: ["counter", "deviceID"],
            contract: "wordPoolEntry.logicalRevision"
        )

        try assertPracticeSettingsPayloadContracts(profileID: profileID)

        let attempt = AttemptEvent(
            questID: QuestID(),
            profileID: profileID,
            wordPromptID: prompt.id,
            learningMode: .read,
            evidence: .firstIndependentAttempt,
            outcome: .technicalFailure(.noUsableAudio),
            timing: AttemptTiming(
                totalResponseTime: ElapsedTime(seconds: 2.1),
                speechOnsetLatency: ElapsedTime(seconds: 0.2),
                firstStrokeLatency: ElapsedTime(seconds: 0.3),
                activeStrokeTime: ElapsedTime(seconds: 1.1),
                idleTime: ElapsedTime(seconds: 0.4),
                replayPauseTime: ElapsedTime(seconds: 0.5)
            ),
            occurredAt: date,
            replayCount: 1,
            recognitionConfidence: RecognitionConfidence(0.75),
            paceContext: PaceContext(
                learningMode: .read,
                deviceClass: .tablet,
                inputMethod: .speech,
                wordLength: 3
            )
        )
        try assertJSONKeyContract(
            attempt,
            contract: "attempt",
            expected: [
                "": [
                    "id", "questID", "profileID", "wordPromptID", "learningMode",
                    "evidence", "outcome", "timing", "occurredAt", "replayCount",
                    "recognitionConfidence", "paceContext",
                ],
                "timing": [
                    "totalResponseTime", "speechOnsetLatency", "firstStrokeLatency",
                    "activeStrokeTime", "idleTime", "replayPauseTime",
                ],
                "timing.totalResponseTime": ["seconds"],
                "timing.speechOnsetLatency": ["seconds"],
                "timing.firstStrokeLatency": ["seconds"],
                "timing.activeStrokeTime": ["seconds"],
                "timing.idleTime": ["seconds"],
                "timing.replayPauseTime": ["seconds"],
                "recognitionConfidence": ["value"],
                "paceContext": [
                    "learningMode", "deviceClass", "inputMethod", "wordLength",
                ],
                "outcome": ["technicalFailure"],
                "outcome.technicalFailure": ["_0"],
            ]
        )
        assertStoredProperties(
            of: attempt,
            equal: [
                "id", "questID", "profileID", "wordPromptID", "learningMode",
                "evidence", "outcome", "timing", "occurredAt", "replayCount",
                "recognitionConfidence", "paceContext",
            ],
            contract: "attempt"
        )
        assertStoredProperties(
            of: attempt.timing,
            equal: [
                "totalResponseTime", "speechOnsetLatency", "firstStrokeLatency",
                "activeStrokeTime", "idleTime", "replayPauseTime",
            ],
            contract: "attempt.timing"
        )
        assertStoredProperties(
            of: try XCTUnwrap(attempt.timing.totalResponseTime),
            equal: ["seconds"],
            contract: "attempt.timing.elapsedTime"
        )
        assertStoredProperties(
            of: try XCTUnwrap(attempt.recognitionConfidence),
            equal: ["value"],
            contract: "attempt.recognitionConfidence"
        )
        assertStoredProperties(
            of: try XCTUnwrap(attempt.paceContext),
            equal: ["learningMode", "deviceClass", "inputMethod", "wordLength"],
            contract: "attempt.paceContext"
        )

        let correction = AttemptCorrectionEvent(
            originalAttemptID: attempt.id,
            correctedOutcome: .correct,
            reason: .recognitionReevaluation(modelVersion: "teacher-v1"),
            correctedAt: date.addingTimeInterval(20)
        )
        try assertJSONKeyContract(
            correction,
            contract: "attemptCorrection",
            expected: [
                "": [
                    "id", "originalAttemptID", "correctedOutcome", "reason",
                    "correctedAt",
                ],
                "correctedOutcome": ["correct"],
                "correctedOutcome.correct": [],
                "reason": ["recognitionReevaluation"],
                "reason.recognitionReevaluation": ["modelVersion"],
            ]
        )
        assertStoredProperties(
            of: correction,
            equal: [
                "id", "originalAttemptID", "correctedOutcome", "reason", "correctedAt",
            ],
            contract: "attemptCorrection"
        )

        let localDay = try LocalDay(year: 2026, month: 7, day: 19)
        let questPlan = QuestPlan(
            profileID: profileID,
            configuration: QuestConfiguration(
                learningMode: .read,
                newWordLimit: 5,
                reviewWordLimit: 4,
                attentionBudget: 9,
                contentOrder: .newThenReview
            ),
            reviewWordIDs: [prompt.id],
            newWordIDs: [WordPromptID()],
            deferredReviewWordIDs: [WordPromptID()],
            createdAt: date
        )
        let dailyPlan = DailyQuestPlan(localDay: localDay, questPlan: questPlan)
        try assertJSONKeyContract(
            dailyPlan,
            contract: "dailyPlan",
            expected: [
                "": ["localDay", "questPlan"],
                "localDay": ["year", "month", "day"],
                "questPlan": [
                    "id", "profileID", "configuration", "reviewWordIDs",
                    "newWordIDs", "deferredReviewWordIDs", "createdAt",
                ],
                "questPlan.configuration": [
                    "learningMode", "newWordLimit", "reviewWordLimit",
                    "attentionBudget", "contentOrder",
                ],
            ]
        )
        assertStoredProperties(
            of: dailyPlan,
            equal: ["localDay", "questPlan"],
            contract: "dailyPlan"
        )
        assertStoredProperties(
            of: localDay,
            equal: ["year", "month", "day"],
            contract: "dailyPlan.localDay"
        )
        assertStoredProperties(
            of: questPlan,
            equal: [
                "id", "profileID", "configuration", "reviewWordIDs", "newWordIDs",
                "deferredReviewWordIDs", "createdAt",
            ],
            contract: "dailyPlan.questPlan"
        )
        assertStoredProperties(
            of: questPlan.configuration,
            equal: [
                "learningMode", "newWordLimit", "reviewWordLimit",
                "attentionBudget", "contentOrder",
            ],
            contract: "dailyPlan.questPlan.configuration"
        )

        let completion = DailyQuestCompletion(
            dailyPlanID: questPlan.id,
            runQuestID: QuestID(),
            profileID: profileID,
            learningMode: .read,
            localDay: localDay,
            runKind: .today,
            points: 100,
            stars: QuestStars(earned: Set(QuestStar.allCases)),
            completedAt: date.addingTimeInterval(30)
        )
        try assertJSONKeyContract(
            completion,
            contract: "dailyCompletion",
            expected: [
                "": [
                    "id", "dailyPlanID", "runQuestID", "profileID", "learningMode",
                    "localDay", "runKind", "points", "stars", "completedAt",
                ],
                "localDay": ["year", "month", "day"],
            ]
        )
        assertStoredProperties(
            of: completion,
            equal: [
                "id", "dailyPlanID", "runQuestID", "profileID", "learningMode",
                "localDay", "runKind", "points", "stars", "completedAt",
            ],
            contract: "dailyCompletion"
        )
        assertStoredProperties(
            of: completion.stars,
            equal: ["earned"],
            contract: "dailyCompletion.stars"
        )
        try assertJSONStringArrayContract(
            completion,
            path: "stars",
            equal: Set(QuestStar.allCases.map(\.rawValue)),
            contract: "dailyCompletion.stars"
        )

        let rewardItem = RewardCatalogItem(
            id: RewardItemID(rawValue: "moonpetal-rainbow"),
            world: .moonpetalKingdom,
            displayName: "Rainbow Crown",
            iconAssetID: "rainbow",
            tier: .milestone,
            requiredTodayQuestCount: 2
        )
        let reward = RewardGrant(
            key: RewardGrantKey(
                profileID: profileID,
                world: .moonpetalKingdom,
                localDay: localDay,
                learningMode: .read
            ),
            dailyPlanID: questPlan.id,
            completionID: completion.id,
            item: rewardItem,
            grantedAt: date.addingTimeInterval(31)
        )
        try assertJSONKeyContract(
            reward,
            contract: "rewardGrant",
            expected: [
                "": [
                    "id", "key", "dailyPlanID", "completionID", "item", "grantedAt",
                ],
                "key": ["profileID", "world", "localDay", "learningMode"],
                "key.localDay": ["year", "month", "day"],
                "item": [
                    "id", "world", "displayName", "iconAssetID", "tier",
                    "requiredTodayQuestCount",
                ],
            ]
        )
        assertStoredProperties(
            of: reward,
            equal: ["id", "key", "dailyPlanID", "completionID", "item", "grantedAt"],
            contract: "rewardGrant"
        )
        assertStoredProperties(
            of: reward.key,
            equal: ["profileID", "world", "localDay", "learningMode"],
            contract: "rewardGrant.key"
        )
        assertStoredProperties(
            of: rewardItem,
            equal: [
                "id", "world", "displayName", "iconAssetID", "tier",
                "requiredTodayQuestCount",
            ],
            contract: "rewardGrant.item"
        )

        let deletion = ProfileDeletionTombstone(
            profileID: profileID,
            deletedAt: date.addingTimeInterval(60)
        )
        try assertJSONKeyContract(
            deletion,
            contract: "profileDeletion",
            expected: ["": ["profileID", "deletedAt"]]
        )
        assertStoredProperties(
            of: deletion,
            equal: ["profileID", "deletedAt"],
            contract: "profileDeletion"
        )
    }

    func testPersistedSnapshotFieldsMatchReviewedInventoryAndManifestEvidence()
        throws
    {
        let snapshots: [String: any Encodable] = [
            "ChildSessionSnapshot": ChildSessionSnapshot(
                lastSelectedProfileID: ProfileID()
            ),
            "DailyQuestSnapshot": DailyQuestSnapshot(
                plans: [],
                completions: [],
                rewardGrants: []
            ),
            "FamilySyncJournalSnapshot": FamilySyncJournalSnapshot(),
            "FamilySyncApplyTransactionSnapshot":
                FamilySyncApplyTransactionSnapshot(),
            "FamilySyncPreferenceSnapshot": FamilySyncPreferenceSnapshot(
                isEnabled: true,
                disclosureVersion:
                    FamilySyncPreferenceSnapshot.currentDisclosureVersion,
                consentedAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 2)
            ),
            "KidProfileSnapshot": KidProfileSnapshot(profiles: []),
            "LearningRecordSnapshot": LearningRecordSnapshot(
                attempts: [],
                corrections: [],
                progress: []
            ),
            "PracticeSettingsSnapshot": PracticeSettingsSnapshot(settings: []),
            "WordPoolSnapshot": WordPoolSnapshot(entries: []),
        ]
        let reviewedInventory: [String: Set<String>] = [
            "ChildSessionSnapshot": [
                "schemaVersion", "lastSelectedProfileID",
            ],
            "DailyQuestSnapshot": [
                "schemaVersion",
                "canonicalBusinessKeyVersion",
                "plans",
                "completions",
                "rewardGrants",
                "pendingCompletions",
                "pendingRewardGrants",
            ],
            "FamilySyncJournalSnapshot": [
                "schemaVersion",
                "localManifest",
                "acknowledgedManifest",
                "outbox",
                "status",
            ],
            "FamilySyncApplyTransactionSnapshot": [
                "schemaVersion",
                "pending",
                "lastCommitted",
            ],
            "FamilySyncPreferenceSnapshot": [
                "schemaVersion",
                "isEnabled",
                "disclosureVersion",
                "consentedAt",
                "updatedAt",
            ],
            "KidProfileSnapshot": ["schemaVersion", "profiles"],
            "LearningRecordSnapshot": [
                "schemaVersion",
                "projectionAlgorithmVersion",
                "canonicalFactsChecksum",
                "attempts",
                "corrections",
                "correctionRoutes",
                "promptAliases",
                "progress",
            ],
            "PracticeSettingsSnapshot": ["schemaVersion", "settings"],
            "WordPoolSnapshot": ["schemaVersion", "entries"],
        ]
        XCTAssertEqual(Set(snapshots.keys), Set(reviewedInventory.keys))

        for (name, snapshot) in snapshots {
            XCTAssertEqual(
                try topLevelKeys(snapshot),
                reviewedInventory[name],
                "Persisted fields changed for \(name). Review its sync classification and update this inventory explicitly."
            )
        }

        let requiredEvidence = Set(
            reviewedInventory.flatMap { snapshotName, fields in
                fields.map { "snapshot:\(snapshotName).\($0)" }
            }
        )
        let manifestSnapshotEvidence = Set(
            FamilySyncDataManifest.entries.flatMap {
                evidenceIDs(for: $0) ?? []
            }.filter { $0.hasPrefix("snapshot:") }
        )
        XCTAssertEqual(
            manifestSnapshotEvidence,
            requiredEvidence,
            "Every persisted snapshot field needs exactly one reviewed machine evidence ID"
        )
    }

    private func assertPracticeSettingsPayloadContracts(
        profileID: ProfileID
    ) throws {
        let route = LearningRouteSettings(
            newWordLimit: 5,
            reviewWordLimit: 4,
            contentOrder: .reviewThenNew,
            emergencyAfterSeconds: 240
        )
        let audio = AudioPreferences(
            voiceEnabled: true,
            musicEnabled: false,
            soundEffectsEnabled: true,
            reducedSoundEnabled: true,
            calmEmergencyEnabled: true
        )
        let reminderTime = LearningReminderTime(hour: 16, minute: 45)
        let quietHours = NotificationQuietHours(
            startsAt: LearningReminderTime(hour: 20, minute: 15),
            endsAt: LearningReminderTime(hour: 7, minute: 30)
        )
        let notifications = LearningNotificationPreferences(
            dailyReminderEnabled: true,
            poolLowEnabled: true,
            questCompletionEnabled: true,
            syncFailureEnabled: true,
            weeklySummaryEnabled: true,
            dailyReminderTime: reminderTime,
            quietHours: quietHours
        )
        let interface = PracticeInterfacePreferences(
            leftHandedLayoutEnabled: true,
            selectedHandwritingTool: .brush
        )
        let values: [PracticeSettingsSyncGroup: PracticeSettingsSyncValue] = [
            .read: .read(route),
            .write: .write(route),
            .audio: .audio(audio),
            .notifications: .notifications(notifications),
            .interface: .interface(interface),
            .wordPolicy: .wordPolicy(.manualOnly),
        ]

        XCTAssertEqual(Set(PracticeSettingsSyncGroup.allCases), Set(values.keys))
        for group in PracticeSettingsSyncGroup.allCases {
            let value = try XCTUnwrap(values[group])
            let payload = PracticeSettingsSyncPayload(
                profileID: profileID,
                value: value
            )
            var expected: [String: Set<String>] = [
                "": ["schemaVersion", "profileID", "value"],
                "value": ["group", "value"],
            ]
            switch group {
            case .read, .write:
                expected["value.value"] = [
                    "newWordLimit", "reviewWordLimit", "contentOrder",
                    "emergencyAfterSeconds",
                ]
            case .audio:
                expected["value.value"] = [
                    "voiceEnabled", "musicEnabled", "soundEffectsEnabled",
                    "reducedSoundEnabled", "calmEmergencyEnabled",
                ]
            case .notifications:
                expected["value.value"] = [
                    "dailyReminderEnabled", "poolLowEnabled",
                    "questCompletionEnabled", "syncFailureEnabled",
                    "weeklySummaryEnabled", "dailyReminderTime", "quietHours",
                ]
                expected["value.value.dailyReminderTime"] = ["hour", "minute"]
                expected["value.value.quietHours"] = ["startsAt", "endsAt"]
                expected["value.value.quietHours.startsAt"] = ["hour", "minute"]
                expected["value.value.quietHours.endsAt"] = ["hour", "minute"]
            case .interface:
                expected["value.value"] = [
                    "leftHandedLayoutEnabled", "selectedHandwritingTool",
                ]
            case .wordPolicy:
                break
            }
            try assertJSONKeyContract(
                payload,
                contract: "practiceSettings.\(group.rawValue)",
                expected: expected
            )
            assertStoredProperties(
                of: payload,
                equal: ["schemaVersion", "profileID", "value"],
                contract: "practiceSettings.\(group.rawValue)"
            )
        }

        assertStoredProperties(
            of: route,
            equal: [
                "newWordLimit", "reviewWordLimit", "contentOrder",
                "emergencyAfterSeconds",
            ],
            contract: "practiceSettings.read/write.value"
        )
        assertStoredProperties(
            of: audio,
            equal: [
                "voiceEnabled", "musicEnabled", "soundEffectsEnabled",
                "reducedSoundEnabled", "calmEmergencyEnabled",
            ],
            contract: "practiceSettings.audio.value"
        )
        assertStoredProperties(
            of: notifications,
            equal: [
                "dailyReminderEnabled", "poolLowEnabled", "questCompletionEnabled",
                "syncFailureEnabled", "weeklySummaryEnabled", "dailyReminderTime",
                "quietHours",
            ],
            contract: "practiceSettings.notifications.value"
        )
        assertStoredProperties(
            of: reminderTime,
            equal: ["hour", "minute"],
            contract: "practiceSettings.notifications.dailyReminderTime"
        )
        assertStoredProperties(
            of: quietHours,
            equal: ["startsAt", "endsAt"],
            contract: "practiceSettings.notifications.quietHours"
        )
        assertStoredProperties(
            of: interface,
            equal: ["leftHandedLayoutEnabled", "selectedHandwritingTool"],
            contract: "practiceSettings.interface.value"
        )
    }

    private func assertJSONKeyContract(
        _ value: any Encodable,
        contract: String,
        expected: [String: Set<String>],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let data = try InspectableSnapshotJSONCodec.makeEncoder().encode(value)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "\(contract) must encode as a keyed JSON object",
            file: file,
            line: line
        )

        for (path, expectedKeys) in expected {
            var node: Any = root
            for component in path.split(separator: ".").map(String.init) {
                guard let object = node as? [String: Any] else {
                    XCTFail(
                        "\(contract).\(path) must be a keyed JSON object",
                        file: file,
                        line: line
                    )
                    return
                }
                node = try XCTUnwrap(
                    object[component],
                    "\(contract) is missing JSON path \(path)",
                    file: file,
                    line: line
                )
            }
            guard let object = node as? [String: Any] else {
                XCTFail(
                    "\(contract).\(path) must be a keyed JSON object",
                    file: file,
                    line: line
                )
                return
            }
            XCTAssertEqual(
                Set(object.keys),
                expectedKeys,
                "\(contract).\(path.isEmpty ? "root" : path) changed. Review every added or removed synchronized JSON field for privacy impact.",
                file: file,
                line: line
            )
        }
    }

    private func assertJSONStringArrayContract(
        _ value: any Encodable,
        path: String,
        equal expectedValues: Set<String>,
        contract: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let data = try InspectableSnapshotJSONCodec.makeEncoder().encode(value)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "\(contract) must encode as a keyed JSON object",
            file: file,
            line: line
        )
        var node: Any = root
        for component in path.split(separator: ".").map(String.init) {
            let object = try XCTUnwrap(
                node as? [String: Any],
                "\(contract) parent path must be a keyed JSON object",
                file: file,
                line: line
            )
            node = try XCTUnwrap(
                object[component],
                "\(contract) is missing JSON path \(path)",
                file: file,
                line: line
            )
        }
        let values = try XCTUnwrap(
            node as? [String],
            "\(contract).\(path) must be a JSON string array",
            file: file,
            line: line
        )
        XCTAssertEqual(
            Set(values),
            expectedValues,
            "\(contract).\(path) changed and needs an explicit privacy review.",
            file: file,
            line: line
        )
    }

    private func assertStoredProperties(
        of value: Any,
        equal expectedProperties: Set<String>,
        contract: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let properties = Set(
            Mirror(reflecting: value).children.compactMap(\.label)
        )
        XCTAssertEqual(
            properties,
            expectedProperties,
            "\(contract) stored properties changed. Optional fields omitted by JSONEncoder still require an explicit privacy review.",
            file: file,
            line: line
        )
    }

    private func topLevelKeyUnion<Value: Encodable>(
        _ values: [Value]
    ) throws -> Set<String> {
        try values.reduce(into: Set<String>()) { keys, value in
            keys.formUnion(try topLevelKeys(value))
        }
    }

    private func evidenceIDs(
        for entry: FamilySyncDataManifestEntry
    ) -> Set<String>? {
        guard
            let value = Mirror(reflecting: entry).children.first(where: {
                $0.label == "evidenceIDs"
            })?.value
        else { return nil }
        if let set = value as? Set<String> { return set }
        if let array = value as? [String] { return Set(array) }
        return nil
    }

    private func topLevelKeys(_ value: any Encodable) throws -> Set<String> {
        let data = try InspectableSnapshotJSONCodec.makeEncoder().encode(value)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return Set(object.keys)
    }

    private var approvedCommonEnvelopeFields: Set<String> {
        [
            "familySyncEnvelope.recordName",
            "familySyncEnvelope.profileID",
            "familySyncEnvelope.kindIdentifier",
            "familySyncEnvelope.payload",
            "familySyncEnvelope.updatedAt",
            "familySyncEnvelope.isDeleted",
            "familySyncEnvelope.schemaVersion",
            "familySyncEnvelope.minimumReadableVersion",
            "familySyncEnvelope.logicalRevision.counter",
            "familySyncEnvelope.logicalRevision.deviceID",
            "familySyncEnvelope.payloadChecksum",
            "familySyncEnvelope.payloadSize",
        ]
    }

    private var approvedSynchronizedFields: Set<String> {
        Set([
            "profiles.id",
            "profiles.displayName",
            "profiles.avatar",
            "profiles.selectedWorld",
            "profiles.starterWorld",
            "profiles.guardianUnlockedWorlds",
            "profiles.selectedCartoonIconAssetID",
            "profiles.selectedTreasureAvatar",
            "profiles.schoolGrade",
            "profiles.ageYears",
            "profiles.photoAttachment.*",
            "profiles.createdAt",
            "profiles.updatedAt",
            "wordPool.entries.id",
            "wordPool.entries.profileID",
            "wordPool.entries.prompt",
            "wordPool.entries.addedAt",
            "wordPool.entries.source",
            "wordPool.entries.isActive",
            "wordPool.entries.lastQueuedAt",
            "wordPool.entries.positionInLastBatch",
            "wordPool.entries.legacyEntryIDs",
            "wordPool.entries.legacyPromptIDs",
            "wordPool.entries.logicalRevision",
            "practiceSettings.profileID",
            "practiceSettings.read.*",
            "practiceSettings.write.*",
            "practiceSettings.audio.*",
            "practiceSettings.notifications.*",
            "practiceSettings.interface.leftHandedLayoutEnabled",
            "practiceSettings.interface.selectedHandwritingTool",
            "practiceSettings.wordRecommendationMode",
            "learning.attempts.*",
            "learning.corrections.*",
            "dailyQuests.plans.*",
            "dailyQuests.completions.*",
            "dailyQuests.rewardGrants.*",
            "dailyQuests.pendingCompletions.*",
            "dailyQuests.pendingRewardGrants.*",
            "profileDeletions.*",
            "cloudDeletionLedger.*",
        ]).union(approvedCommonEnvelopeFields)
    }
}
