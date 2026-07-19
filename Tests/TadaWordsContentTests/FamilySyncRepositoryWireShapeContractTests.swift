import CoreFoundation
import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsContent

final class FamilySyncRepositoryWireShapeContractTests: XCTestCase {
    func testEveryRawWireEnumHasAnExplicitReviewedValueSet() {
        XCTAssertEqual(Set(LearningMode.allCases.map(\.rawValue)), ["read", "write"])
        XCTAssertEqual(
            Set(ProfileSchoolGrade.allCases.map(\.rawValue)),
            ["preK", "kindergarten", "grade1", "grade2", "grade3"]
        )
        XCTAssertEqual(
            Set(ProfileAvatar.PhotoSource.allCases.map(\.rawValue)),
            ["camera", "photoLibrary"]
        )
        XCTAssertEqual(
            Set(WorldTheme.allCases.map(\.rawValue)),
            [
                "moonpetalKingdom", "buildItBay", "pawsAndPines",
                "dinoDiscovery", "firehouseHeroes", "brickworkCity",
                "frostlightWorld", "coasterCarnival",
            ]
        )
        XCTAssertEqual(
            Set(WordPoolEntrySource.allCases.map(\.rawValue)),
            ["guardianManual", "gradeRecommendation"]
        )
        XCTAssertEqual(
            Set(EncounterEvidence.allCases.map(\.rawValue)),
            [
                "studyExposed", "firstIndependentAttempt", "unaidedRetry",
                "feedbackExposed", "guidedRetry", "helped", "technicalRetry",
                "recognitionUncertain",
            ]
        )
        XCTAssertEqual(
            Set(QuestContentOrder.allCases.map(\.rawValue)),
            ["newThenReview", "reviewThenNew"]
        )
        XCTAssertEqual(
            Set(DailyQuestRunKind.allCases.map(\.rawValue)),
            ["today", "practiceAgain"]
        )
        XCTAssertEqual(
            Set(QuestStar.allCases.map(\.rawValue)),
            ["completion", "accuracy", "personalPace"]
        )
        XCTAssertEqual(
            Set(RewardTier.allCases.map(\.rawValue)),
            ["smallCollectible", "milestone"]
        )
        XCTAssertEqual(
            Set(DeviceClass.allCases.map(\.rawValue)),
            ["phone", "tablet"]
        )
        XCTAssertEqual(
            Set(LearningInputMethod.allCases.map(\.rawValue)),
            ["speech", "fingerWriting", "pencilWriting", "letterKeyboard"]
        )
        XCTAssertEqual(
            Set(HandwritingTool.allCases.map(\.rawValue)),
            ["pencil", "crayon", "chalk", "brush"]
        )
        XCTAssertEqual(
            Set(WordRecommendationMode.allCases.map(\.rawValue)),
            ["manualOnly", "parentFirstAutomaticFallback", "gradeAutomatic"]
        )
        XCTAssertEqual(
            Set(FamilySyncRecordKind.allCases.map(\.rawValue)),
            [
                "profile", "wordPoolEntry", "practiceSettings", "attempt",
                "attemptCorrection", "wordProgress", "dailyPlan",
                "dailyCompletion", "rewardGrant", "profileDeletion",
            ]
        )
    }

    func testRepositoryExportsOnlyReviewedRecursiveJSONShapes() async throws {
        let fixture = try FamilySyncWireContractFixture()
        defer { fixture.remove() }
        let records = try await fixture.exportedRecords()

        XCTAssertEqual(
            Set(records.map(\.kind)),
            FamilySyncDataManifest.synchronizedRecordKinds
        )
        let profilePayloads =
            records
            .filter { $0.kind == .profile }
            .map(\.payload)
        XCTAssertFalse(profilePayloads.isEmpty)
        for payload in profilePayloads {
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: payload) as? [String: Any]
            )
            XCTAssertNil(
                object["voiceprintStatus"],
                "Voiceprint state is device-local and cannot appear on the wire."
            )
        }

        try assertAssociatedEnumFixturesAreExhaustive(in: records)

        var actual: [FamilySyncRecordKind: [String: Set<String>]] = [:]
        for record in records {
            let json = try JSONSerialization.jsonObject(with: record.payload)
            var shape: [String: Set<String>] = [:]
            flatten(json, path: "$", into: &shape)
            actual[record.kind, default: [:]].merge(shape) { $0.union($1) }
        }

        XCTAssertEqual(
            actual,
            approvedShapes,
            "A synchronized payload changed recursively. Review every new object key, array element, scalar, and associated-value shape before updating this contract.\n\(render(actual))"
        )
    }

    private func assertAssociatedEnumFixturesAreExhaustive(
        in records: [FamilySyncRecord]
    ) throws {
        let decoder = InspectableSnapshotJSONCodec.makeDecoder()
        let profiles = try records.filter { $0.kind == .profile }.map {
            try decoder.decode(FamilySyncProfilePayload.self, from: $0.payload)
        }
        for profile in profiles {
            XCTAssertEqual(
                Set(Mirror(reflecting: profile).children.compactMap(\.label)),
                [
                    "id", "displayName", "avatar", "selectedWorld",
                    "starterWorld", "guardianUnlockedWorlds",
                    "selectedCartoonIconAssetID", "selectedTreasureAvatar",
                    "schoolGrade", "ageYears", "createdAt", "updatedAt",
                ],
                "An optional Profile wire field cannot bypass JSON shape review by encoding nil."
            )
        }
        XCTAssertEqual(
            Set(profiles.map { avatarCase($0.avatar) }),
            ["cartoonAnimal", "photo", "treasure"]
        )

        let attempts = try records.filter { $0.kind == .attempt }.map {
            try decoder.decode(AttemptEvent.self, from: $0.payload)
        }
        XCTAssertEqual(
            Set(attempts.map { outcomeCase($0.outcome) }),
            [
                "correct", "incorrect", "recognitionUncertain",
                "technicalFailure", "skipped",
            ]
        )
        XCTAssertEqual(
            Set(attempts.compactMap { technicalFailureCase($0.outcome) }),
            Set(TechnicalFailureReason.allCases.map(\.rawValue))
        )
        XCTAssertEqual(
            Set(TechnicalFailureReason.allCases.map(\.rawValue)),
            [
                "permissionDenied", "noUsableAudio", "wrongSpeaker",
                "onDeviceRecognitionUnavailable", "serviceUnavailable",
                "timedOut", "corruptedInput",
            ]
        )

        let corrections =
            try records
            .filter { $0.kind == .attemptCorrection }
            .map {
                try decoder.decode(
                    AttemptCorrectionEvent.self,
                    from: $0.payload
                )
            }
        XCTAssertEqual(
            Set(corrections.map { correctionReasonCase($0.reason) }),
            [
                "guardianOverride", "recognitionReevaluation",
                "duplicateEvent", "other",
            ]
        )
        XCTAssertEqual(
            Set(corrections.map { outcomeCase($0.correctedOutcome) }),
            [
                "correct", "incorrect", "recognitionUncertain",
                "technicalFailure", "skipped",
            ]
        )
        XCTAssertEqual(
            Set(
                corrections.compactMap {
                    technicalFailureCase($0.correctedOutcome)
                }
            ),
            Set(TechnicalFailureReason.allCases.map(\.rawValue))
        )

        let settings =
            try records
            .filter { $0.kind == .practiceSettings }
            .map {
                try decoder.decode(
                    PracticeSettingsSyncPayload.self,
                    from: $0.payload
                )
            }
        XCTAssertEqual(
            Set(settings.map { practiceSettingsValueCase($0.value) }),
            Set(PracticeSettingsSyncGroup.allCases.map(\.rawValue))
        )
        for payload in settings {
            switch payload.value {
            case .interface(let preferences):
                XCTAssertNotEqual(preferences.selectedHandwritingTool, .crayon)
            case .wordPolicy(let mode):
                XCTAssertEqual(mode, .manualOnly)
            case .read, .write, .audio, .notifications:
                break
            }
        }
    }

    private func avatarCase(_ avatar: ProfileAvatar) -> String {
        switch avatar {
        case .cartoonAnimal:
            "cartoonAnimal"
        case .photo:
            "photo"
        case .treasure:
            "treasure"
        }
    }

    private func outcomeCase(_ outcome: AttemptOutcome) -> String {
        switch outcome {
        case .correct:
            "correct"
        case .incorrect:
            "incorrect"
        case .recognitionUncertain:
            "recognitionUncertain"
        case .technicalFailure:
            "technicalFailure"
        case .skipped:
            "skipped"
        }
    }

    private func technicalFailureCase(_ outcome: AttemptOutcome) -> String? {
        guard case .technicalFailure(let reason) = outcome else { return nil }
        return switch reason {
        case .permissionDenied:
            TechnicalFailureReason.permissionDenied.rawValue
        case .noUsableAudio:
            TechnicalFailureReason.noUsableAudio.rawValue
        case .wrongSpeaker:
            TechnicalFailureReason.wrongSpeaker.rawValue
        case .onDeviceRecognitionUnavailable:
            TechnicalFailureReason.onDeviceRecognitionUnavailable.rawValue
        case .serviceUnavailable:
            TechnicalFailureReason.serviceUnavailable.rawValue
        case .timedOut:
            TechnicalFailureReason.timedOut.rawValue
        case .corruptedInput:
            TechnicalFailureReason.corruptedInput.rawValue
        }
    }

    private func correctionReasonCase(_ reason: AttemptCorrectionReason) -> String {
        switch reason {
        case .guardianOverride:
            "guardianOverride"
        case .recognitionReevaluation:
            "recognitionReevaluation"
        case .duplicateEvent:
            "duplicateEvent"
        case .other:
            "other"
        }
    }

    private func practiceSettingsValueCase(
        _ value: PracticeSettingsSyncValue
    ) -> String {
        switch value {
        case .read:
            PracticeSettingsSyncGroup.read.rawValue
        case .write:
            PracticeSettingsSyncGroup.write.rawValue
        case .audio:
            PracticeSettingsSyncGroup.audio.rawValue
        case .notifications:
            PracticeSettingsSyncGroup.notifications.rawValue
        case .interface:
            PracticeSettingsSyncGroup.interface.rawValue
        case .wordPolicy:
            PracticeSettingsSyncGroup.wordPolicy.rawValue
        }
    }

    private func flatten(
        _ value: Any,
        path: String,
        into shape: inout [String: Set<String>]
    ) {
        if let object = value as? [String: Any] {
            shape[path, default: []].insert(
                "object{" + object.keys.sorted().joined(separator: ",") + "}"
            )
            for key in object.keys.sorted() {
                guard let child = object[key] else { continue }
                flatten(child, path: "\(path).\(key)", into: &shape)
            }
            return
        }
        if let array = value as? [Any] {
            shape[path, default: []].insert("array")
            for child in array {
                flatten(child, path: "\(path)[]", into: &shape)
            }
            return
        }
        if value is NSNull {
            shape[path, default: []].insert("null")
            return
        }
        if let number = value as? NSNumber {
            let kind =
                CFGetTypeID(number) == CFBooleanGetTypeID()
                ? "boolean"
                : "number"
            shape[path, default: []].insert(kind)
            return
        }
        if value is String {
            shape[path, default: []].insert("string")
            return
        }
        XCTFail("Unsupported JSON node at \(path): \(type(of: value))")
    }

    private func render(
        _ shapes: [FamilySyncRecordKind: [String: Set<String>]]
    ) -> String {
        shapes.keys.sorted { $0.rawValue < $1.rawValue }.map { kind in
            let lines = (shapes[kind] ?? [:]).keys.sorted().map { path in
                let signatures = (shapes[kind]?[path] ?? []).sorted()
                    .joined(separator: " | ")
                return "    \"\(path)\": [\"\(signatures)\"],"
            }
            return "\(kind.rawValue): [\n\(lines.joined(separator: "\n"))\n]"
        }.joined(separator: "\n")
    }

    private var approvedShapes: [FamilySyncRecordKind: [String: Set<String>]] {
        [
            .profile: parseShape(
                """
                $\tobject{ageYears,avatar,createdAt,displayName,guardianUnlockedWorlds,id,schoolGrade,selectedCartoonIconAssetID,selectedWorld,starterWorld,updatedAt} | object{ageYears,avatar,createdAt,displayName,guardianUnlockedWorlds,id,schoolGrade,selectedTreasureAvatar,selectedWorld,starterWorld,updatedAt} | object{avatar,createdAt,displayName,guardianUnlockedWorlds,id,schoolGrade,selectedWorld,starterWorld,updatedAt}
                $.ageYears\tnumber
                $.avatar\tobject{cartoonAnimal} | object{photo} | object{treasure}
                $.avatar.cartoonAnimal\tobject{assetID}
                $.avatar.cartoonAnimal.assetID\tstring
                $.avatar.photo\tobject{assetID,source}
                $.avatar.photo.assetID\tstring
                $.avatar.photo.source\tstring
                $.avatar.treasure\tobject{iconAssetID,rewardItemID}
                $.avatar.treasure.iconAssetID\tstring
                $.avatar.treasure.rewardItemID\tstring
                $.createdAt\tnumber
                $.displayName\tstring
                $.guardianUnlockedWorlds\tarray
                $.guardianUnlockedWorlds[]\tstring
                $.id\tobject{rawValue}
                $.id.rawValue\tstring
                $.schoolGrade\tstring
                $.selectedCartoonIconAssetID\tstring
                $.selectedTreasureAvatar\tobject{iconAssetID,rewardItemID}
                $.selectedTreasureAvatar.iconAssetID\tstring
                $.selectedTreasureAvatar.rewardItemID\tstring
                $.selectedWorld\tstring
                $.starterWorld\tstring
                $.updatedAt\tnumber
                """
            ),
            .wordPoolEntry: parseShape(
                """
                $\tobject{addedAt,id,isActive,lastQueuedAt,legacyEntryIDs,legacyPromptIDs,logicalRevision,positionInLastBatch,profileID,prompt,source}
                $.addedAt\tnumber
                $.id\tobject{rawValue}
                $.id.rawValue\tstring
                $.isActive\tboolean
                $.lastQueuedAt\tnumber
                $.legacyEntryIDs\tarray
                $.legacyEntryIDs[]\tobject{rawValue}
                $.legacyEntryIDs[].rawValue\tstring
                $.legacyPromptIDs\tarray
                $.legacyPromptIDs[]\tobject{rawValue}
                $.legacyPromptIDs[].rawValue\tstring
                $.logicalRevision\tobject{counter,deviceID}
                $.logicalRevision.counter\tnumber
                $.logicalRevision.deviceID\tstring
                $.positionInLastBatch\tnumber
                $.profileID\tobject{rawValue}
                $.profileID.rawValue\tstring
                $.prompt\tobject{audioCue,displayText,id,learningMode,normalizedText}
                $.prompt.audioCue\tobject{pronunciationKey,spokenContext}
                $.prompt.audioCue.pronunciationKey\tstring
                $.prompt.audioCue.spokenContext\tstring
                $.prompt.displayText\tstring
                $.prompt.id\tobject{rawValue}
                $.prompt.id.rawValue\tstring
                $.prompt.learningMode\tstring
                $.prompt.normalizedText\tstring
                $.source\tstring
                """
            ),
            .practiceSettings: parseShape(
                """
                $\tobject{profileID,schemaVersion,value}
                $.profileID\tobject{rawValue}
                $.profileID.rawValue\tstring
                $.schemaVersion\tnumber
                $.value\tobject{group,value}
                $.value.group\tstring
                $.value.value\tobject{calmEmergencyEnabled,musicEnabled,reducedSoundEnabled,soundEffectsEnabled,voiceEnabled} | object{contentOrder,emergencyAfterSeconds,newWordLimit,reviewWordLimit} | object{dailyReminderEnabled,dailyReminderTime,poolLowEnabled,questCompletionEnabled,quietHours,syncFailureEnabled,weeklySummaryEnabled} | object{leftHandedLayoutEnabled,selectedHandwritingTool} | string
                $.value.value.calmEmergencyEnabled\tboolean
                $.value.value.contentOrder\tstring
                $.value.value.dailyReminderEnabled\tboolean
                $.value.value.dailyReminderTime\tobject{hour,minute}
                $.value.value.dailyReminderTime.hour\tnumber
                $.value.value.dailyReminderTime.minute\tnumber
                $.value.value.emergencyAfterSeconds\tnumber
                $.value.value.leftHandedLayoutEnabled\tboolean
                $.value.value.musicEnabled\tboolean
                $.value.value.newWordLimit\tnumber
                $.value.value.poolLowEnabled\tboolean
                $.value.value.questCompletionEnabled\tboolean
                $.value.value.quietHours\tobject{endsAt,startsAt}
                $.value.value.quietHours.endsAt\tobject{hour,minute}
                $.value.value.quietHours.endsAt.hour\tnumber
                $.value.value.quietHours.endsAt.minute\tnumber
                $.value.value.quietHours.startsAt\tobject{hour,minute}
                $.value.value.quietHours.startsAt.hour\tnumber
                $.value.value.quietHours.startsAt.minute\tnumber
                $.value.value.reducedSoundEnabled\tboolean
                $.value.value.reviewWordLimit\tnumber
                $.value.value.selectedHandwritingTool\tstring
                $.value.value.soundEffectsEnabled\tboolean
                $.value.value.syncFailureEnabled\tboolean
                $.value.value.voiceEnabled\tboolean
                $.value.value.weeklySummaryEnabled\tboolean
                """
            ),
            .attempt: parseShape(
                """
                $\tobject{evidence,id,learningMode,occurredAt,outcome,paceContext,profileID,questID,recognitionConfidence,replayCount,timing,wordPromptID}
                $.evidence\tstring
                $.id\tobject{rawValue}
                $.id.rawValue\tstring
                $.learningMode\tstring
                $.occurredAt\tnumber
                $.outcome\tobject{correct} | object{incorrect} | object{recognitionUncertain} | object{skipped} | object{technicalFailure}
                $.outcome.correct\tobject{}
                $.outcome.incorrect\tobject{}
                $.outcome.recognitionUncertain\tobject{}
                $.outcome.skipped\tobject{}
                $.outcome.technicalFailure\tobject{_0}
                $.outcome.technicalFailure._0\tstring
                $.paceContext\tobject{deviceClass,inputMethod,learningMode,wordLength}
                $.paceContext.deviceClass\tstring
                $.paceContext.inputMethod\tstring
                $.paceContext.learningMode\tstring
                $.paceContext.wordLength\tnumber
                $.profileID\tobject{rawValue}
                $.profileID.rawValue\tstring
                $.questID\tobject{rawValue}
                $.questID.rawValue\tstring
                $.recognitionConfidence\tobject{value}
                $.recognitionConfidence.value\tnumber
                $.replayCount\tnumber
                $.timing\tobject{activeStrokeTime,firstStrokeLatency,idleTime,replayPauseTime,speechOnsetLatency,totalResponseTime}
                $.timing.activeStrokeTime\tobject{seconds}
                $.timing.activeStrokeTime.seconds\tnumber
                $.timing.firstStrokeLatency\tobject{seconds}
                $.timing.firstStrokeLatency.seconds\tnumber
                $.timing.idleTime\tobject{seconds}
                $.timing.idleTime.seconds\tnumber
                $.timing.replayPauseTime\tobject{seconds}
                $.timing.replayPauseTime.seconds\tnumber
                $.timing.speechOnsetLatency\tobject{seconds}
                $.timing.speechOnsetLatency.seconds\tnumber
                $.timing.totalResponseTime\tobject{seconds}
                $.timing.totalResponseTime.seconds\tnumber
                $.wordPromptID\tobject{rawValue}
                $.wordPromptID.rawValue\tstring
                """
            ),
            .attemptCorrection: parseShape(
                """
                $\tobject{correctedAt,correctedOutcome,id,originalAttemptID,reason}
                $.correctedAt\tnumber
                $.correctedOutcome\tobject{correct} | object{incorrect} | object{recognitionUncertain} | object{skipped} | object{technicalFailure}
                $.correctedOutcome.correct\tobject{}
                $.correctedOutcome.incorrect\tobject{}
                $.correctedOutcome.recognitionUncertain\tobject{}
                $.correctedOutcome.skipped\tobject{}
                $.correctedOutcome.technicalFailure\tobject{_0}
                $.correctedOutcome.technicalFailure._0\tstring
                $.id\tobject{rawValue}
                $.id.rawValue\tstring
                $.originalAttemptID\tobject{rawValue}
                $.originalAttemptID.rawValue\tstring
                $.reason\tobject{duplicateEvent} | object{guardianOverride} | object{other} | object{recognitionReevaluation}
                $.reason.duplicateEvent\tobject{}
                $.reason.guardianOverride\tobject{}
                $.reason.other\tobject{_0}
                $.reason.other._0\tstring
                $.reason.recognitionReevaluation\tobject{modelVersion}
                $.reason.recognitionReevaluation.modelVersion\tstring
                """
            ),
            .dailyPlan: parseShape(
                """
                $\tobject{localDay,questPlan}
                $.localDay\tobject{day,month,year}
                $.localDay.day\tnumber
                $.localDay.month\tnumber
                $.localDay.year\tnumber
                $.questPlan\tobject{configuration,createdAt,deferredReviewWordIDs,id,newWordIDs,profileID,reviewWordIDs}
                $.questPlan.configuration\tobject{attentionBudget,contentOrder,learningMode,newWordLimit,reviewWordLimit}
                $.questPlan.configuration.attentionBudget\tnumber
                $.questPlan.configuration.contentOrder\tstring
                $.questPlan.configuration.learningMode\tstring
                $.questPlan.configuration.newWordLimit\tnumber
                $.questPlan.configuration.reviewWordLimit\tnumber
                $.questPlan.createdAt\tnumber
                $.questPlan.deferredReviewWordIDs\tarray
                $.questPlan.deferredReviewWordIDs[]\tobject{rawValue}
                $.questPlan.deferredReviewWordIDs[].rawValue\tstring
                $.questPlan.id\tobject{rawValue}
                $.questPlan.id.rawValue\tstring
                $.questPlan.newWordIDs\tarray
                $.questPlan.newWordIDs[]\tobject{rawValue}
                $.questPlan.newWordIDs[].rawValue\tstring
                $.questPlan.profileID\tobject{rawValue}
                $.questPlan.profileID.rawValue\tstring
                $.questPlan.reviewWordIDs\tarray
                $.questPlan.reviewWordIDs[]\tobject{rawValue}
                $.questPlan.reviewWordIDs[].rawValue\tstring
                """
            ),
            .dailyCompletion: parseShape(
                """
                $\tobject{completedAt,dailyPlanID,id,learningMode,localDay,points,profileID,runKind,runQuestID,stars}
                $.completedAt\tnumber
                $.dailyPlanID\tobject{rawValue}
                $.dailyPlanID.rawValue\tstring
                $.id\tobject{rawValue}
                $.id.rawValue\tstring
                $.learningMode\tstring
                $.localDay\tobject{day,month,year}
                $.localDay.day\tnumber
                $.localDay.month\tnumber
                $.localDay.year\tnumber
                $.points\tnumber
                $.profileID\tobject{rawValue}
                $.profileID.rawValue\tstring
                $.runKind\tstring
                $.runQuestID\tobject{rawValue}
                $.runQuestID.rawValue\tstring
                $.stars\tarray
                $.stars[]\tstring
                """
            ),
            .rewardGrant: parseShape(
                """
                $\tobject{completionID,dailyPlanID,grantedAt,id,item,key}
                $.completionID\tobject{rawValue}
                $.completionID.rawValue\tstring
                $.dailyPlanID\tobject{rawValue}
                $.dailyPlanID.rawValue\tstring
                $.grantedAt\tnumber
                $.id\tobject{rawValue}
                $.id.rawValue\tstring
                $.item\tobject{displayName,iconAssetID,id,requiredTodayQuestCount,tier,world}
                $.item.displayName\tstring
                $.item.iconAssetID\tstring
                $.item.id\tstring
                $.item.requiredTodayQuestCount\tnumber
                $.item.tier\tstring
                $.item.world\tstring
                $.key\tobject{learningMode,localDay,profileID,world}
                $.key.learningMode\tstring
                $.key.localDay\tobject{day,month,year}
                $.key.localDay.day\tnumber
                $.key.localDay.month\tnumber
                $.key.localDay.year\tnumber
                $.key.profileID\tobject{rawValue}
                $.key.profileID.rawValue\tstring
                $.key.world\tstring
                """
            ),
            .profileDeletion: parseShape(
                """
                $\tobject{deletedAt,profileID}
                $.deletedAt\tnumber
                $.profileID\tobject{rawValue}
                $.profileID.rawValue\tstring
                """
            ),
        ]
    }

    private func parseShape(_ source: String) -> [String: Set<String>] {
        Dictionary(
            uniqueKeysWithValues: source.split(separator: "\n").map { line in
                let parts = line.split(separator: "\t", maxSplits: 1)
                precondition(parts.count == 2, "Malformed wire-shape contract line")
                let signatures = parts[1].components(separatedBy: " | ")
                return (String(parts[0]), Set(signatures))
            }
        )
    }
}

private struct FamilySyncWireContractFixture {
    let directory: URL
    let profiles: LocalJSONKidProfileRepository
    let words: LocalJSONWordPoolRepository
    let settings: LocalJSONPracticeSettingsRepository
    let learning: LocalJSONLearningRecordRepository
    let daily: LocalJSONDailyQuestRepository
    let tombstones: LocalJSONProfileDeletionTombstoneRepository
    let now = Date(timeIntervalSince1970: 2_050_000_000)
    let mainProfileID = ProfileID()

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaWireContract-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        profiles = LocalJSONKidProfileRepository(
            snapshotURL: directory.appendingPathComponent("profiles.json")
        )
        words = LocalJSONWordPoolRepository(
            snapshotURL: directory.appendingPathComponent("words.json")
        )
        settings = LocalJSONPracticeSettingsRepository(
            snapshotURL: directory.appendingPathComponent("settings.json")
        )
        learning = LocalJSONLearningRecordRepository(
            snapshotURL: directory.appendingPathComponent("learning.json")
        )
        daily = LocalJSONDailyQuestRepository(
            snapshotURL: directory.appendingPathComponent("daily.json")
        )
        tombstones = LocalJSONProfileDeletionTombstoneRepository(
            snapshotURL: directory.appendingPathComponent("deletions.json")
        )
    }

    func exportedRecords() async throws -> [FamilySyncRecord] {
        let avatarProfiles = [
            KidProfile(
                id: mainProfileID,
                displayName: "Photo Reader",
                avatar: .embeddedPhoto(
                    data: Data([0xFF, 0xD8, 0xFF, 0xD9]),
                    source: .camera
                ),
                selectedWorld: .moonpetalKingdom,
                starterWorld: .pawsAndPines,
                guardianUnlockedWorlds: [.moonpetalKingdom, .pawsAndPines],
                selectedCartoonIconAssetID: "rainbow-unicorn",
                schoolGrade: .preK,
                ageYears: 4,
                voiceprintStatus: .enrolled(
                    modelVersion: "must-stay-local",
                    enrolledAt: now
                ),
                createdAt: now.addingTimeInterval(-100),
                updatedAt: now
            ),
            KidProfile(
                displayName: "Animal Reader",
                avatar: .cartoonAnimal(assetID: "smiling-fox"),
                selectedWorld: .pawsAndPines,
                selectedTreasureAvatar: TreasureAvatarSelection(
                    rewardItemID: RewardItemID(rawValue: "forest-star"),
                    iconAssetID: "star.fill"
                ),
                schoolGrade: .kindergarten,
                ageYears: 5,
                voiceprintStatus: .needsRefresh,
                createdAt: now.addingTimeInterval(-90)
            ),
            KidProfile(
                displayName: "Treasure Reader",
                avatar: .treasure(
                    rewardItemID: RewardItemID(rawValue: "rainbow-crown"),
                    iconAssetID: "crown.fill"
                ),
                selectedWorld: .moonpetalKingdom,
                createdAt: now.addingTimeInterval(-80)
            ),
        ]
        for profile in avatarProfiles {
            try await profiles.save(profile)
        }

        let prompt = try WordPrompt(
            learningMode: .read,
            text: "dog",
            audioCue: .contextual("I see a dog.", pronunciationKey: "dog")
        )
        let wordRevision = FamilySyncLogicalRevision(
            counter: 9,
            deviceID: "wire-contract-device"
        )
        try await words.mergeSynced(
            WordPoolEntry(
                profileID: mainProfileID,
                prompt: prompt,
                addedAt: now,
                source: .guardianManual,
                lastQueuedAt: now.addingTimeInterval(1),
                positionInLastBatch: 2,
                legacyEntryIDs: [WordPoolEntryID()],
                legacyPromptIDs: [WordPromptID()],
                logicalRevision: wordRevision
            ),
            logicalRevision: wordRevision
        )
        try await settings.save(
            ProfilePracticeSettings(
                profileID: mainProfileID,
                read: LearningRouteSettings(
                    newWordLimit: 5,
                    reviewWordLimit: 4,
                    contentOrder: .reviewThenNew,
                    emergencyAfterSeconds: 240
                ),
                write: LearningRouteSettings(
                    newWordLimit: 3,
                    reviewWordLimit: 2,
                    contentOrder: .newThenReview,
                    emergencyAfterSeconds: 300
                ),
                audio: AudioPreferences(
                    voiceEnabled: true,
                    musicEnabled: false,
                    soundEffectsEnabled: true,
                    reducedSoundEnabled: true,
                    calmEmergencyEnabled: true
                ),
                notifications: LearningNotificationPreferences(
                    dailyReminderEnabled: true,
                    poolLowEnabled: true,
                    questCompletionEnabled: true,
                    syncFailureEnabled: true,
                    weeklySummaryEnabled: true,
                    dailyReminderTime: LearningReminderTime(hour: 16, minute: 45),
                    quietHours: NotificationQuietHours(
                        startsAt: LearningReminderTime(hour: 20, minute: 15),
                        endsAt: LearningReminderTime(hour: 7, minute: 30)
                    )
                ),
                interface: PracticeInterfacePreferences(
                    leftHandedLayoutEnabled: true,
                    selectedHandwritingTool: .brush
                ),
                wordRecommendationMode: .manualOnly
            )
        )

        var outcomes: [AttemptOutcome] = [
            .correct,
            .incorrect,
            .recognitionUncertain,
            .skipped,
        ]
        outcomes += TechnicalFailureReason.allCases.map {
            .technicalFailure($0)
        }
        var attempts: [AttemptEvent] = []
        for (index, outcome) in outcomes.enumerated() {
            let attempt = AttemptEvent(
                questID: QuestID(),
                profileID: mainProfileID,
                wordPromptID: prompt.id,
                learningMode: .read,
                evidence: .firstIndependentAttempt,
                outcome: outcome,
                timing: AttemptTiming(
                    totalResponseTime: ElapsedTime(seconds: 2.1),
                    speechOnsetLatency: ElapsedTime(seconds: 0.2),
                    firstStrokeLatency: ElapsedTime(seconds: 0.3),
                    activeStrokeTime: ElapsedTime(seconds: 1.1),
                    idleTime: ElapsedTime(seconds: 0.4),
                    replayPauseTime: ElapsedTime(seconds: 0.5)
                ),
                occurredAt: now.addingTimeInterval(Double(index)),
                replayCount: 1,
                recognitionConfidence: RecognitionConfidence(0.75),
                paceContext: PaceContext(
                    learningMode: .read,
                    deviceClass: .tablet,
                    inputMethod: .speech,
                    wordLength: 3
                )
            )
            try await learning.append(attempt)
            attempts.append(attempt)
        }
        let reasons: [AttemptCorrectionReason] = [
            .guardianOverride,
            .recognitionReevaluation(modelVersion: "teacher-v1"),
            .duplicateEvent,
            .other("reviewed by parent"),
        ]
        for (index, outcome) in outcomes.enumerated() {
            try await learning.append(
                AttemptCorrectionEvent(
                    originalAttemptID: attempts[index].id,
                    correctedOutcome: outcome,
                    reason: reasons[index % reasons.count],
                    correctedAt: now.addingTimeInterval(Double(100 + index))
                )
            )
        }

        let localDay = try LocalDay(year: 2034, month: 12, day: 17)
        let plan = DailyQuestPlan(
            localDay: localDay,
            questPlan: QuestPlan(
                profileID: mainProfileID,
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
                createdAt: now
            )
        )
        let completion = DailyQuestCompletion(
            dailyPlanID: plan.id,
            runQuestID: QuestID(),
            profileID: mainProfileID,
            learningMode: .read,
            localDay: localDay,
            runKind: .today,
            points: 100,
            stars: QuestStars(earned: Set(QuestStar.allCases)),
            completedAt: now.addingTimeInterval(200)
        )
        let reward = RewardGrant(
            key: RewardGrantKey(
                profileID: mainProfileID,
                world: .moonpetalKingdom,
                localDay: localDay,
                learningMode: .read
            ),
            dailyPlanID: plan.id,
            completionID: completion.id,
            item: RewardCatalogItem(
                id: RewardItemID(rawValue: "rainbow-crown"),
                world: .moonpetalKingdom,
                displayName: "Rainbow Crown",
                iconAssetID: "crown.fill",
                tier: .milestone,
                requiredTodayQuestCount: 2
            ),
            grantedAt: now.addingTimeInterval(201)
        )
        _ = try await daily.mergeCanonical(
            DailyQuestCanonicalMergeBatch(
                plans: [plan],
                completions: [completion],
                rewardGrants: [reward]
            )
        )

        let deletedProfileID = ProfileID()
        try await tombstones.save(
            ProfileDeletionTombstone(
                profileID: deletedProfileID,
                deletedAt: now.addingTimeInterval(300)
            )
        )

        let store = RepositoryFamilySyncRecordStore(
            profileRepository: profiles,
            wordPoolRepository: words,
            practiceSettingsRepository: settings,
            learningRepository: learning,
            dailyQuestRepository: daily,
            tombstoneRepository: tombstones,
            deviceID: "wire-contract-device"
        )
        var records: [FamilySyncRecord] = []
        for profile in avatarProfiles {
            records += try await store.records(for: profile.id)
        }
        records += try await store.records(for: deletedProfileID)
        return records
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
