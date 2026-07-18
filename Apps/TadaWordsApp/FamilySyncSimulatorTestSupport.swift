#if DEBUG && targetEnvironment(simulator) && !LOCAL_DEVICE_QA
    import Foundation
    import TadaWordsContent
    import TadaWordsDomain

    /// Process-isolated, deterministic Family Sync server used only by
    /// simulator UI tests. The production coordinator, repositories, journal,
    /// apply transaction, receipt stream, and SwiftUI navigation remain real.
    enum FamilySyncSimulatorTestSupport {
        private static let enableFlag = "--family-sync-e2e"
        private static let resetFlag = "--family-sync-reset"
        fileprivate static let referenceDate = Date(
            timeIntervalSince1970: 1_768_464_000
        )

        static func clock(
            arguments: [String] = ProcessInfo.processInfo.arguments
        ) -> (any AppClock)? {
            guard configuration(arguments: arguments) != nil else { return nil }
            return FamilySyncSimulatorClock(now: referenceDate)
        }

        static func timeZone(
            arguments: [String] = ProcessInfo.processInfo.arguments
        ) -> TimeZone? {
            guard configuration(arguments: arguments) != nil else { return nil }
            return TimeZone(secondsFromGMT: 0)
        }

        static func transport(
            profileID: ProfileID,
            arguments: [String] = ProcessInfo.processInfo.arguments
        ) -> (any FamilySyncTransport)? {
            guard let configuration = configuration(arguments: arguments) else {
                return nil
            }
            do {
                return try FamilySyncSimulatorTestTransport(
                    scenario: configuration.scenario,
                    profileID: profileID,
                    deletionDelaySeconds: configuration.deletionDelaySeconds
                )
            } catch {
                preconditionFailure(
                    "Family Sync UI-test fixture is invalid: \(error)"
                )
            }
        }

        static func prepareApplicationSupportDirectory(
            systemDirectory: URL,
            profileID: ProfileID,
            arguments: [String] = ProcessInfo.processInfo.arguments
        ) throws -> URL? {
            guard let configuration = configuration(arguments: arguments) else {
                return nil
            }
            let root =
                systemDirectory
                .appendingPathComponent(
                    "TadaWordsFamilySyncUITests",
                    isDirectory: true
                )
                .appendingPathComponent(configuration.suite, isDirectory: true)
            if configuration.resetsStorage,
                FileManager.default.fileExists(atPath: root.path)
            {
                try FileManager.default.removeItem(at: root)
            }
            let dataDirectory = root.appendingPathComponent(
                "TadaWords",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: dataDirectory,
                withIntermediateDirectories: true
            )
            try seedCompletedFirstRun(
                at: dataDirectory.appendingPathComponent(
                    "first-run-onboarding.json"
                ),
                profileID: profileID
            )
            try seedEnabledPreference(
                at: dataDirectory.appendingPathComponent(
                    "family-sync-preference.json"
                )
            )
            return root
        }

        private static func configuration(
            arguments: [String]
        ) -> Configuration? {
            guard arguments.contains("--ui-testing"),
                arguments.contains(enableFlag),
                let suite = value(after: "--family-sync-suite=", in: arguments),
                let scenarioValue = value(
                    after: "--family-sync-scenario=",
                    in: arguments
                ),
                let scenario = Scenario(rawValue: scenarioValue)
            else {
                return nil
            }
            let suiteIsSafe =
                (1...96).contains(suite.utf8.count)
                && suite.allSatisfy {
                    $0.isASCII
                        && ($0.isLetter || $0.isNumber || $0 == "-")
                }
            guard suiteIsSafe else { return nil }
            let deletionDelaySeconds: Int
            if let rawDelay = value(
                after: "--family-sync-deletion-delay=",
                in: arguments
            ) {
                guard let parsedDelay = Int(rawDelay),
                    (1...60).contains(parsedDelay)
                else { return nil }
                deletionDelaySeconds = parsedDelay
            } else {
                deletionDelaySeconds = 10
            }
            return Configuration(
                suite: suite,
                scenario: scenario,
                resetsStorage: arguments.contains(resetFlag),
                deletionDelaySeconds: deletionDelaySeconds
            )
        }

        private static func value(
            after prefix: String,
            in arguments: [String]
        ) -> String? {
            arguments.first(where: { $0.hasPrefix(prefix) }).map {
                String($0.dropFirst(prefix.count))
            }
        }

        private static func seedCompletedFirstRun(
            at url: URL,
            profileID: ProfileID
        ) throws {
            let referenceDate = Date(timeIntervalSince1970: 1_735_689_600)
            let snapshot = CompletedFirstRunSnapshot(
                schemaVersion: 1,
                status: "completed",
                startedAt: referenceDate,
                completedAt: referenceDate,
                profileID: profileID,
                consentVersion: 1,
                consentedAt: referenceDate,
                purpose: "fullSetup"
            )
            try encode(snapshot).write(to: url, options: .atomic)
        }

        private static func seedEnabledPreference(at url: URL) throws {
            let referenceDate = Date(timeIntervalSince1970: 1_735_689_600)
            let snapshot = FamilySyncPreferenceSnapshot(
                isEnabled: true,
                disclosureVersion:
                    FamilySyncPreferenceSnapshot.currentDisclosureVersion,
                consentedAt: referenceDate,
                updatedAt: referenceDate
            )
            try encode(snapshot).write(to: url, options: .atomic)
        }

        private static func encode<Value: Encodable>(
            _ value: Value
        ) throws -> Data {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(value)
        }

        fileprivate enum Scenario: String, Sendable {
            case remoteBundle = "remote-bundle"
            case offline
            case online
            case quarantine
            case signedOut = "signed-out"
            case restricted
            case delayedDeletion = "delayed-deletion"
        }

        private struct Configuration: Sendable {
            let suite: String
            let scenario: Scenario
            let resetsStorage: Bool
            let deletionDelaySeconds: Int
        }

        private struct CompletedFirstRunSnapshot: Encodable {
            let schemaVersion: Int
            let status: String
            let startedAt: Date
            let completedAt: Date
            let profileID: ProfileID
            let consentVersion: Int
            let consentedAt: Date
            let purpose: String
        }
    }

    private struct FamilySyncSimulatorClock: AppClock {
        let now: Date
    }

    private actor FamilySyncSimulatorTestTransport: FamilySyncTransport {
        nonisolated let capability = FamilySyncCapability.iCloud

        private let scenario: FamilySyncSimulatorTestSupport.Scenario
        private let profileID: ProfileID
        private let remoteBundle: [FamilySyncRecord]
        private let deletionRecord: FamilySyncRecord
        private let deletionDelaySeconds: Int
        private var deliveredRemoteBundle = false
        private var deliveredDeletion = false
        private var quarantined = false

        init(
            scenario: FamilySyncSimulatorTestSupport.Scenario,
            profileID: ProfileID,
            deletionDelaySeconds: Int
        ) throws {
            self.scenario = scenario
            self.profileID = profileID
            self.deletionDelaySeconds = deletionDelaySeconds
            remoteBundle = try Self.makeRemoteBundle(profileID: profileID)
            deletionRecord = try Self.makeDeletionRecord(profileID: profileID)
        }

        func availability() async -> FamilySyncAvailability {
            switch scenario {
            case .offline:
                .temporarilyUnavailable
            case .signedOut:
                .noAccount
            case .restricted:
                .restricted
            case .remoteBundle, .online, .quarantine, .delayedDeletion:
                .available
            }
        }

        func prepareProfileZone(_ profileID: ProfileID) async throws {
            _ = profileID
        }

        func fetchRecords(
            for profileID: ProfileID
        ) async throws -> [FamilySyncRecord] {
            guard profileID == self.profileID else { return [] }
            return try await fetchChanges(for: [profileID]).records
        }

        func push(
            _ records: [FamilySyncRecord],
            for profileID: ProfileID
        ) async throws {
            _ = records
            _ = profileID
        }

        func fetchChanges(
            for profileIDs: [ProfileID]
        ) async throws -> FamilySyncTransportResult {
            guard profileIDs.contains(profileID) else {
                return FamilySyncTransportResult()
            }
            switch scenario {
            case .remoteBundle:
                guard !deliveredRemoteBundle else {
                    return FamilySyncTransportResult()
                }
                deliveredRemoteBundle = true
                return result(records: remoteBundle)
            case .quarantine:
                if quarantined {
                    return FamilySyncTransportResult(
                        quarantinedRecordCount: 1
                    )
                }
                return result(records: [Self.makeCorruptRecord(profileID: profileID)])
            case .delayedDeletion:
                guard !deliveredDeletion else {
                    return FamilySyncTransportResult()
                }
                deliveredDeletion = true
                // The deterministic delay gives XCUITest time to establish the
                // child/editor route precondition. The actual recovery remains
                // driven by a real remote deletion receipt, never a test tap.
                try await Task.sleep(for: .seconds(deletionDelaySeconds))
                return result(records: [deletionRecord])
            case .offline, .online, .signedOut, .restricted:
                return FamilySyncTransportResult()
            }
        }

        func sendChanges(
            _ changes: [FamilySyncPendingOperation]
        ) async throws -> FamilySyncTransportResult {
            FamilySyncTransportResult(
                acknowledged: Set(
                    changes.map(FamilySyncChangeAcknowledgement.init)
                )
            )
        }

        func acknowledgeFetchedChanges(
            receiptIDs: Set<UUID>
        ) async throws {
            _ = receiptIDs
        }

        func quarantineFetchedChanges(
            receiptIDs: Set<UUID>,
            category: FamilySyncPrivacySafeErrorCategory
        ) async throws {
            _ = receiptIDs
            _ = category
            quarantined = true
        }

        func confirmCurrentAccount() async throws {}

        func suspend() async {}

        func createShare(for profileID: ProfileID) async throws -> URL {
            URL(string: "https://example.invalid/tadawords-family")!
        }

        func acceptShare(at url: URL) async throws -> ProfileID {
            _ = url
            return profileID
        }

        private func result(
            records: [FamilySyncRecord]
        ) -> FamilySyncTransportResult {
            let receipts = records.enumerated().map { index, record in
                FamilySyncFetchedReceipt(
                    id: Self.receiptID(index: index, record: record),
                    key: FamilySyncChangeKey(
                        profileID: record.profileID,
                        recordName: record.recordName
                    ),
                    operation: .save,
                    revision: record.logicalRevision
                )
            }
            return FamilySyncTransportResult(
                records: records,
                receipts: receipts
            )
        }

        private static func makeRemoteBundle(
            profileID: ProfileID
        ) throws -> [FamilySyncRecord] {
            // A fixed instant keeps identical logical revisions byte-identical
            // across process death and relaunch. Changing payload bytes under a
            // fixed revision would correctly be treated as a conflict.
            let now = referenceDate
            let remoteDevice = "family-sync-ui-remote"
            let readPrompt = try WordPrompt(
                id: WordPromptID(
                    rawValue: fixedUUID("10000000-0000-0000-0000-000000000001")
                ),
                learningMode: .read,
                text: "spark"
            )
            let writePrompt = try WordPrompt(
                id: WordPromptID(
                    rawValue: fixedUUID("10000000-0000-0000-0000-000000000002")
                ),
                learningMode: .write,
                text: "shine"
            )
            let profile = KidProfile(
                id: profileID,
                displayName: "Remote Mia",
                avatar: .cartoonAnimal(assetID: "unicorn"),
                selectedWorld: .moonpetalKingdom,
                schoolGrade: .preK,
                ageYears: 4,
                // This is the same durable Profile identity as the bundled
                // seed, so its immutable creation instant must also match.
                createdAt: Date(timeIntervalSince1970: 1_735_689_600),
                updatedAt: now
            )
            let readEntry = WordPoolEntry(
                id: WordPoolEntryID(
                    rawValue: fixedUUID("20000000-0000-0000-0000-000000000001")
                ),
                profileID: profileID,
                prompt: readPrompt,
                addedAt: now.addingTimeInterval(-14_400),
                source: .guardianManual,
                logicalRevision: revision(102, deviceID: remoteDevice)
            )
            let writeEntry = WordPoolEntry(
                id: WordPoolEntryID(
                    rawValue: fixedUUID("20000000-0000-0000-0000-000000000002")
                ),
                profileID: profileID,
                prompt: writePrompt,
                addedAt: now.addingTimeInterval(-14_300),
                source: .guardianManual,
                logicalRevision: revision(103, deviceID: remoteDevice)
            )
            let settings = ProfilePracticeSettings(
                profileID: profileID,
                read: LearningRouteSettings(
                    newWordLimit: 7,
                    reviewWordLimit: 2,
                    contentOrder: .reviewThenNew,
                    emergencyAfterSeconds: 240
                ),
                write: LearningRouteSettings(
                    newWordLimit: 6,
                    reviewWordLimit: 3,
                    contentOrder: .newThenReview,
                    emergencyAfterSeconds: 360
                )
            )
            let attempt = AttemptEvent(
                id: AttemptID(
                    rawValue: fixedUUID("30000000-0000-0000-0000-000000000001")
                ),
                profileID: profileID,
                wordPromptID: readPrompt.id,
                learningMode: .read,
                evidence: .firstIndependentAttempt,
                outcome: .incorrect,
                timing: AttemptTiming(
                    totalResponseTime: ElapsedTime(seconds: 8)
                ),
                occurredAt: now.addingTimeInterval(-10_800),
                recognitionConfidence: RecognitionConfidence(0.7)
            )
            let localDay = LocalDay(
                date: now,
                timeZone: TimeZone(secondsFromGMT: 0)!
            )
            let planID = QuestID(
                rawValue: fixedUUID("40000000-0000-0000-0000-000000000001")
            )
            let completionID = DailyQuestCompletionID(
                rawValue: fixedUUID("50000000-0000-0000-0000-000000000001")
            )
            let plan = DailyQuestPlan(
                localDay: localDay,
                questPlan: QuestPlan(
                    id: planID,
                    profileID: profileID,
                    configuration: .defaultRead,
                    reviewWordIDs: [],
                    newWordIDs: [readPrompt.id],
                    createdAt: now.addingTimeInterval(-180)
                )
            )
            let completion = DailyQuestCompletion(
                id: completionID,
                dailyPlanID: planID,
                runQuestID: planID,
                profileID: profileID,
                learningMode: .read,
                localDay: localDay,
                runKind: .today,
                points: 100,
                stars: QuestStars(earned: Set(QuestStar.allCases)),
                completedAt: now.addingTimeInterval(-60)
            )
            let reward = RewardGrant(
                id: RewardGrantID(
                    rawValue: fixedUUID("60000000-0000-0000-0000-000000000001")
                ),
                key: RewardGrantKey(
                    profileID: profileID,
                    world: .moonpetalKingdom,
                    localDay: localDay,
                    learningMode: .read
                ),
                dailyPlanID: planID,
                completionID: completionID,
                item: RewardCatalogItem(
                    id: RewardItemID(
                        rawValue: "moonpetalKingdom.starlight-tiara"
                    ),
                    world: .moonpetalKingdom,
                    displayName: "Starlight Tiara"
                ),
                grantedAt: now.addingTimeInterval(-60)
            )

            var records: [FamilySyncRecord] = []
            records.append(
                try record(
                    name: "profile-\(profileID)",
                    profileID: profileID,
                    kind: .profile,
                    value: profile,
                    updatedAt: now,
                    counter: 101,
                    deviceID: remoteDevice
                )
            )
            records.append(
                try record(
                    name: "word-entry-\(readEntry.id)",
                    profileID: profileID,
                    kind: .wordPoolEntry,
                    value: readEntry,
                    updatedAt: readEntry.lastQueuedAt,
                    counter: 102,
                    deviceID: remoteDevice
                )
            )
            records.append(
                try record(
                    name: "word-entry-\(writeEntry.id)",
                    profileID: profileID,
                    kind: .wordPoolEntry,
                    value: writeEntry,
                    updatedAt: writeEntry.lastQueuedAt,
                    counter: 103,
                    deviceID: remoteDevice
                )
            )
            for (offset, group) in [
                PracticeSettingsSyncGroup.read,
                PracticeSettingsSyncGroup.write,
            ].enumerated() {
                records.append(
                    try record(
                        name: group.recordName(for: profileID),
                        profileID: profileID,
                        kind: .practiceSettings,
                        value: PracticeSettingsSyncPayload(
                            settings: settings,
                            group: group
                        ),
                        updatedAt: now,
                        counter: UInt64(104 + offset),
                        deviceID: remoteDevice
                    )
                )
            }
            records.append(
                try record(
                    name: "attempt-\(attempt.id)",
                    profileID: profileID,
                    kind: .attempt,
                    value: attempt,
                    updatedAt: attempt.occurredAt,
                    counter: 106,
                    deviceID: remoteDevice
                )
            )
            records.append(
                try record(
                    name: "daily-plan-\(profileID)-read-\(localDay)",
                    profileID: profileID,
                    kind: .dailyPlan,
                    value: plan,
                    updatedAt: now,
                    counter: 107,
                    deviceID: remoteDevice
                )
            )
            records.append(
                try record(
                    name: "daily-completion-\(profileID)-read-\(localDay)",
                    profileID: profileID,
                    kind: .dailyCompletion,
                    value: completion,
                    updatedAt: completion.completedAt,
                    counter: 108,
                    deviceID: remoteDevice
                )
            )
            records.append(
                try record(
                    name: "reward-grant-\(profileID)-read-\(localDay)",
                    profileID: profileID,
                    kind: .rewardGrant,
                    value: reward,
                    updatedAt: reward.grantedAt,
                    counter: 109,
                    deviceID: remoteDevice
                )
            )
            return records
        }

        private static func makeDeletionRecord(
            profileID: ProfileID
        ) throws -> FamilySyncRecord {
            let deletedAt = referenceDate.addingTimeInterval(7_200)
            return try record(
                name: "profile-\(profileID)",
                profileID: profileID,
                kind: .profileDeletion,
                value: ProfileDeletionTombstone(
                    profileID: profileID,
                    deletedAt: deletedAt
                ),
                updatedAt: deletedAt,
                counter: 1_000,
                deviceID: "family-sync-ui-owner",
                isDeleted: true
            )
        }

        private static func makeCorruptRecord(
            profileID: ProfileID
        ) -> FamilySyncRecord {
            FamilySyncRecord(
                recordName: "profile-\(profileID)",
                profileID: profileID,
                kind: .profile,
                payload: Data([0xFF, 0x00, 0xFE]),
                updatedAt: referenceDate.addingTimeInterval(3_600),
                deviceID: "family-sync-ui-corrupt",
                logicalRevision: revision(
                    900,
                    deviceID: "family-sync-ui-corrupt"
                )
            )
        }

        private static func record<Value: Encodable>(
            name: String,
            profileID: ProfileID,
            kind: FamilySyncRecordKind,
            value: Value,
            updatedAt: Date,
            counter: UInt64,
            deviceID: String,
            isDeleted: Bool = false
        ) throws -> FamilySyncRecord {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            encoder.outputFormatting = [.sortedKeys]
            return FamilySyncRecord(
                recordName: name,
                profileID: profileID,
                kind: kind,
                payload: try encoder.encode(value),
                updatedAt: updatedAt,
                deviceID: deviceID,
                isDeleted: isDeleted,
                logicalRevision: revision(counter, deviceID: deviceID)
            )
        }

        private static func revision(
            _ counter: UInt64,
            deviceID: String
        ) -> FamilySyncLogicalRevision {
            FamilySyncLogicalRevision(counter: counter, deviceID: deviceID)
        }

        private static func fixedUUID(_ value: String) -> UUID {
            guard let uuid = UUID(uuidString: value) else {
                preconditionFailure("Invalid UI-test UUID: \(value)")
            }
            return uuid
        }

        private static func receiptID(
            index: Int,
            record: FamilySyncRecord
        ) -> UUID {
            var bytes = Array(
                FamilySyncRecord.checksum(
                    for: Data("\(index)-\(record.recordName)".utf8)
                ).utf8.prefix(32)
            )
            while bytes.count < 32 { bytes.append(UInt8(ascii: "0")) }
            let hex = String(decoding: bytes, as: UTF8.self)
            let formatted =
                "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
            return UUID(uuidString: formatted) ?? UUID()
        }

        private static let referenceDate =
            FamilySyncSimulatorTestSupport.referenceDate
    }
#endif
