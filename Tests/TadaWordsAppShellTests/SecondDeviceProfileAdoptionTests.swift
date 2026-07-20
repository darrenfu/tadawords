import Foundation
import TadaWordsContent
import TadaWordsDomain
import TadaWordsFeatures
import TadaWordsGuardianFeatures
import XCTest

@testable import TadaWordsAppShell

final class SecondDeviceProfileAdoptionTests: XCTestCase {
    func testForegroundRearmWriteFailureKeepsAdoptAndCreateClosedAfterRecovery()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountAProfile = profile(id: UUID(), name: "Mia")
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Unused Seed"),
            transport: DiscoveryTransport(
                availability: [.available],
                remoteProfiles: [accountAProfile]
            )
        )
        _ = try await discovery(in: environment).discoverProfiles()
        let discoveredState =
            try await environment.firstRunOnboardingRepository.state()
        XCTAssertNil(discoveredState?.discoveryResetPhase)

        let failingOnboarding = FailingOnceOnboardingRepository(
            base: environment.firstRunOnboardingRepository,
            failure: .rearm
        )
        let admissionGate = FirstRunDiscoveryAdmissionGate()
        let failedGeneration = admissionGate.closeForAccountRevalidation()
        let firstRevalidationSucceeded =
            await FirstRunDiscoveryAdmissionRevalidator.revalidate(
                generation: failedGeneration,
                gate: admissionGate,
                onboardingRepository: failingOnboarding,
                familySyncCoordinator: environment.familySyncCoordinator
            )

        XCTAssertFalse(firstRevalidationSucceeded)
        XCTAssertTrue(admissionGate.admissionIsClosed())
        let failedRearmState =
            try await environment.firstRunOnboardingRepository.state()
        XCTAssertNil(
            failedRearmState?.discoveryResetPhase,
            "The injected write failure should leave the durable phase nil."
        )

        let coordinator = FirstRunOnboardingCoordinator(
            profileRepository: environment.profileRepository,
            childSessionRepository: environment.childSessionRepository,
            onboardingRepository: failingOnboarding,
            guardianStore: environment.guardianStore,
            discoveryAdmissionGate: admissionGate,
            clock: AdoptionClock(now: referenceDate)
        )
        let submissions = [
            FirstRunOnboardingSubmission(
                action: .adoptExistingProfile(accountAProfile.id)
            ),
            newKidSubmission,
        ]
        for submission in submissions {
            do {
                _ = try await coordinator.complete(
                    profileID: accountAProfile.id,
                    submission: submission
                )
                XCTFail("A failed foreground fence must block admission.")
            } catch {
                XCTAssertEqual(
                    error as? FirstRunOnboardingRepositoryError,
                    .discoveryResetRequired
                )
            }
        }

        // Storage has recovered, but admission reopens only after another
        // foreground pass durably installs the reset and quiesces sync.
        let retryGeneration = admissionGate.closeForAccountRevalidation()
        let retrySucceeded =
            await FirstRunDiscoveryAdmissionRevalidator.revalidate(
                generation: retryGeneration,
                gate: admissionGate,
                onboardingRepository: failingOnboarding,
                familySyncCoordinator: environment.familySyncCoordinator
            )
        XCTAssertTrue(retrySucceeded)
        XCTAssertFalse(admissionGate.admissionIsClosed())
        let rearmedState =
            try await environment.firstRunOnboardingRepository.state()
        XCTAssertEqual(
            rearmedState?.discoveryResetPhase,
            .required
        )

        // The process latch is open again, but the durable phase still blocks
        // both actions until Find purges account A and confirms the current
        // account generation.
        for submission in submissions {
            do {
                _ = try await coordinator.complete(
                    profileID: accountAProfile.id,
                    submission: submission
                )
                XCTFail("The durable reset must still block admission.")
            } catch {
                XCTAssertEqual(
                    error as? FirstRunOnboardingRepositoryError,
                    .discoveryResetRequired
                )
            }
        }
        let profilesAfterBlockedAdmissions =
            try await environment.profileRepository.profiles()
        XCTAssertEqual(profilesAfterBlockedAdmissions.map(\.id), [accountAProfile.id])
    }

    func testForegroundRevokesInFlightAdoptAndCreateBeforeCompletionCommit()
        async throws
    {
        func exercise(createNew: Bool) async throws {
            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let accountAProfile = profile(id: UUID(), name: "Mia")
            let environment = try await bootstrap(
                in: directory,
                defaultProfile: profile(id: UUID(), name: "Unused Seed"),
                transport: DiscoveryTransport(
                    availability: [.available],
                    remoteProfiles: [accountAProfile]
                )
            )
            _ = try await discovery(in: environment).discoverProfiles()

            let blockingOnboarding = FailingOnceOnboardingRepository(
                base: environment.firstRunOnboardingRepository,
                failure: .blockedCompletion
            )
            let admissionGate = FirstRunDiscoveryAdmissionGate()
            let coordinator = FirstRunOnboardingCoordinator(
                profileRepository: environment.profileRepository,
                childSessionRepository: environment.childSessionRepository,
                onboardingRepository: blockingOnboarding,
                guardianStore: environment.guardianStore,
                discoveryAdmissionGate: admissionGate,
                clock: AdoptionClock(now: referenceDate)
            )
            let submission =
                createNew
                ? newKidSubmission
                : FirstRunOnboardingSubmission(
                    action: .adoptExistingProfile(accountAProfile.id)
                )
            let completion = Task {
                try await coordinator.complete(
                    profileID: accountAProfile.id,
                    submission: submission
                )
            }

            await blockingOnboarding.waitUntilCompletionIsBlocked()
            _ = admissionGate.closeForAccountRevalidation()
            await blockingOnboarding.releaseBlockedCompletion()

            do {
                _ = try await completion.value
                XCTFail("Foreground revocation must win before completion.")
            } catch {
                XCTAssertEqual(
                    error as? FirstRunOnboardingRepositoryError,
                    .discoveryResetRequired
                )
            }
            let state =
                try await environment.firstRunOnboardingRepository.state()
            XCTAssertEqual(state?.status, .pending)
            XCTAssertNil(state?.completedAt)
            XCTAssertTrue(admissionGate.admissionIsClosed())
        }

        try await exercise(createNew: false)
        try await exercise(createNew: true)
    }

    func testInFlightCreateKeepsDiscoveryProvenanceThroughAccountRevalidation()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountAProfile = profile(id: UUID(), name: "Mia")
        let accountBProfile = profile(id: UUID(), name: "Noah")
        let transport = DiscoveryTransport(
            availability: [.available],
            remoteProfiles: [accountAProfile],
            switchedRemoteProfiles: [accountBProfile],
            confirmationChanges: [nil, .switchedAccounts]
        )
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Unused Seed"),
            transport: transport
        )
        _ = try await discovery(in: environment).discoverProfiles()

        let blockingOnboarding = FailingOnceOnboardingRepository(
            base: environment.firstRunOnboardingRepository,
            failure: .blockedCompletion
        )
        let admissionGate = FirstRunDiscoveryAdmissionGate()
        let coordinator = FirstRunOnboardingCoordinator(
            profileRepository: environment.profileRepository,
            childSessionRepository: environment.childSessionRepository,
            onboardingRepository: blockingOnboarding,
            guardianStore: environment.guardianStore,
            discoveryAdmissionGate: admissionGate,
            clock: AdoptionClock(now: referenceDate)
        )
        let createSubmission = newKidSubmission
        let staleCreate = Task {
            try await coordinator.complete(
                profileID: accountAProfile.id,
                submission: createSubmission
            )
        }
        await blockingOnboarding.waitUntilCompletionIsBlocked()

        let foregroundGeneration =
            admissionGate.closeForAccountRevalidation()
        let revalidationSucceeded =
            await FirstRunDiscoveryAdmissionRevalidator.revalidate(
                generation: foregroundGeneration,
                gate: admissionGate,
                onboardingRepository: blockingOnboarding,
                familySyncCoordinator: environment.familySyncCoordinator
            )
        XCTAssertTrue(revalidationSucceeded)
        XCTAssertFalse(admissionGate.admissionIsClosed())
        let rearmedState =
            try await environment.firstRunOnboardingRepository.state()
        let pendingCreatedProfileID = try XCTUnwrap(
            rearmedState?.pendingCreatedProfileID
        )
        XCTAssertEqual(rearmedState?.profileIntent, .createNew)
        XCTAssertEqual(rearmedState?.creationOriginatedFromDiscovery, true)
        XCTAssertEqual(rearmedState?.discoveryResetPhase, .required)

        await blockingOnboarding.releaseBlockedCompletion()
        do {
            _ = try await staleCreate.value
            XCTFail("The pre-switch Create must not commit.")
        } catch {
            XCTAssertEqual(
                error as? FirstRunOnboardingRepositoryError,
                .discoveryResetRequired
            )
        }
        do {
            _ = try await coordinator.complete(
                profileID: accountAProfile.id,
                submission: createSubmission
            )
            XCTFail("A retry must remain fenced until Find replaces the cache.")
        } catch {
            XCTAssertEqual(
                error as? FirstRunOnboardingRepositoryError,
                .discoveryResetRequired
            )
        }

        let discoveredAccountB = try await discovery(in: environment)
            .discoverProfiles()
        let remainingProfileIDs = Set(
            try await environment.profileRepository.profiles().map(\.id)
        )
        XCTAssertEqual(discoveredAccountB.map(\.id), [accountBProfile.id])
        XCTAssertEqual(remainingProfileIDs, [accountBProfile.id])
        XCTAssertFalse(remainingProfileIDs.contains(accountAProfile.id))
        XCTAssertFalse(remainingProfileIDs.contains(pendingCreatedProfileID))
    }

    func testSuccessfulFindRearmsOnRelaunchBeforeCreateCanMixAccounts()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountAProfile = profile(id: UUID(), name: "Mia")
        let accountBProfile = profile(id: UUID(), name: "Noah")
        let first = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Unused Seed"),
            transport: DiscoveryTransport(
                availability: [.available],
                remoteProfiles: [accountAProfile]
            )
        )
        let discoveredAccountA = try await discovery(in: first)
            .discoverProfiles()
        XCTAssertEqual(discoveredAccountA.map(\.id), [accountAProfile.id])

        let switchedTransport = DiscoveryTransport(
            availability: [.available],
            remoteProfiles: [accountAProfile],
            switchedRemoteProfiles: [accountBProfile],
            confirmationChanges: [.switchedAccounts]
        )
        let restarted = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Another Seed"),
            transport: switchedTransport
        )

        do {
            _ = try await onboarding(in: restarted).complete(
                profileID: nil,
                submission: newKidSubmission
            )
            XCTFail("Create must not mix a prior account cache after relaunch.")
        } catch {
            XCTAssertEqual(
                error as? FirstRunOnboardingRepositoryError,
                .discoveryResetRequired
            )
        }
        let retainedProfileIDs = Set(
            try await restarted.profileRepository.profiles().map(\.id)
        )
        let isEnabled = await restarted.familySyncCoordinator.isEnabled()
        let confirmationCalls = await switchedTransport.confirmationCallCount()
        XCTAssertEqual(retainedProfileIDs, [accountAProfile.id])
        XCTAssertFalse(isEnabled)
        XCTAssertEqual(
            confirmationCalls,
            0,
            "Bootstrap/Create must not touch account B before parent retries Find."
        )
    }

    func testLegacyFindRelaunchDisablesBackgroundSyncBeforeCallbacksCanRun()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = ApplicationDataPaths(applicationSupportDirectory: directory)
        try FileManager.default.createDirectory(
            at: paths.dataDirectory,
            withIntermediateDirectories: true
        )
        let legacy = FirstRunOnboardingState(
            schemaVersion: 2,
            status: .pending,
            startedAt: referenceDate,
            completedAt: nil,
            profileID: nil,
            consentVersion: nil,
            consentedAt: nil,
            purpose: .fullSetup,
            profileIntent: .discoverExisting
        )
        try JSONEncoder().encode(legacy).write(
            to: paths.firstRunOnboardingSnapshot
        )
        try await LocalJSONFamilySyncPreferenceRepository(
            snapshotURL: paths.familySyncPreferenceSnapshot
        ).setEnabled(true, updatedAt: referenceDate)
        let transport = DiscoveryTransport(
            availability: [.available],
            remoteProfiles: []
        )

        let environment = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Unused Seed"),
            transport: transport
        )
        let isEnabled = await environment.familySyncCoordinator.isEnabled()
        let suspensionCalls = await transport.suspensionCallCount()
        let initialConfirmationCalls = await transport.confirmationCallCount()
        let initialFetchCalls = await transport.fetchCallCount()
        XCTAssertFalse(isEnabled)
        XCTAssertEqual(suspensionCalls, 1)
        XCTAssertEqual(initialConfirmationCalls, 0)
        XCTAssertEqual(initialFetchCalls, 0)

        _ = await environment.familySyncCoordinator.synchronize(
            trigger: .remoteNotification
        )
        _ = await environment.familySyncCoordinator.synchronize(
            trigger: .connectivityRecovery
        )

        let finalConfirmationCalls = await transport.confirmationCallCount()
        let finalFetchCalls = await transport.fetchCallCount()
        let outboundProfileIDs = await transport.outboundProfileIDs()
        XCTAssertEqual(finalConfirmationCalls, 0)
        XCTAssertEqual(finalFetchCalls, 0)
        XCTAssertTrue(outboundProfileIDs.isEmpty)
    }

    func testFindErasesChildOnlyAccountAArtifactsWithoutAProfileRow()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountAProfileID = ProfileID()
        let accountBProfile = profile(id: UUID(), name: "Noah")
        let transport = DiscoveryTransport(
            availability: [.available],
            remoteProfiles: [accountBProfile]
        )
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Unused Seed"),
            transport: transport
        )
        _ = try await ManualWordPoolImporter(
            repository: environment.wordPoolRepository
        ).importBatch(
            "secret",
            profileID: accountAProfileID,
            learningMode: .read,
            addedAt: referenceDate
        )
        try await environment.practiceSettingsRepository.save(
            .defaults(for: accountAProfileID)
        )
        try await environment.childSessionRepository.saveLastSelectedProfileID(
            accountAProfileID
        )
        let childOnlyRecord = FamilySyncRecord(
            recordName: "word-account-a",
            profileID: accountAProfileID,
            kind: .wordPoolEntry,
            payload: Data("ACCOUNT_A_CHILD_BYTES".utf8),
            updatedAt: referenceDate,
            deviceID: "account-a",
            logicalRevision: FamilySyncLogicalRevision(
                counter: 1,
                deviceID: "account-a"
            )
        )
        try await environment.familySyncJournalRepository.recordAppliedRemote(
            records: [childOnlyRecord],
            deletions: [],
            at: referenceDate
        )
        let start = try await environment.familySyncApplyTransactionRepository
            .begin(
                profileID: accountAProfileID,
                records: [childOnlyRecord],
                at: referenceDate
            )
        guard case .pending(let transaction) = start else {
            return XCTFail("Expected a new child-only apply transaction.")
        }
        _ = try await environment.familySyncApplyTransactionRepository
            .markCommitted(
                transactionID: transaction.id,
                at: referenceDate
            )
        let accountAProfile = try await environment.profileRepository.profile(
            id: accountAProfileID
        )
        XCTAssertNil(accountAProfile)

        let discovered = try await discovery(in: environment).discoverProfiles()

        XCTAssertEqual(discovered.map(\.id), [accountBProfile.id])
        let accountAWords = try await environment.wordPoolRepository.entries(
            for: accountAProfileID,
            learningMode: .read,
            includingInactive: true
        )
        let accountASettings = try await environment.practiceSettingsRepository
            .settings(for: accountAProfileID)
        let selectedProfileID = try await environment.childSessionRepository
            .lastSelectedProfileID()
        let journalProfileIDs =
            try await environment.familySyncJournalRepository
            .unadoptedProfileIDs()
        let applyProfileIDs =
            try await environment.familySyncApplyTransactionRepository
            .unadoptedProfileIDs()
        let outboundProfileIDs = await transport.outboundProfileIDs()
        XCTAssertTrue(accountAWords.isEmpty)
        XCTAssertNil(accountASettings)
        XCTAssertNil(selectedProfileID)
        XCTAssertFalse(journalProfileIDs.contains(accountAProfileID))
        XCTAssertFalse(applyProfileIDs.contains(accountAProfileID))
        XCTAssertFalse(
            outboundProfileIDs.contains(accountAProfileID)
        )
    }

    func testRelaunchAfterProfileIdentityReservationResumesExactID()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = DiscoveryTransport(
            availability: [.temporarilyUnavailable],
            remoteProfiles: []
        )
        let first = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Unused Seed"),
            transport: transport
        )
        let reservedID = try await first.firstRunOnboardingRepository
            .beginProfileCreation(
                proposedProfileID: nil,
                startedAt: referenceDate
            )

        let restarted = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Another Seed"),
            transport: transport
        )
        let restartedState = try await restarted.firstRunOnboardingRepository
            .state()
        XCTAssertEqual(restartedState?.pendingCreatedProfileID, reservedID)
        XCTAssertTrue(restarted.profiles.isEmpty)

        let completion = try await onboarding(in: restarted).complete(
            profileID: nil,
            submission: newKidSubmission
        )
        XCTAssertEqual(completion.selectedProfileID, reservedID)
        XCTAssertEqual(completion.profiles.map(\.id), [reservedID])
    }

    func testRelaunchAfterDefaultSettingsWriteBeforeProfileWriteResumesExactID()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = DiscoveryTransport(
            availability: [.temporarilyUnavailable],
            remoteProfiles: []
        )
        let first = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Unused Seed"),
            transport: transport
        )
        let reservedID = try await first.firstRunOnboardingRepository
            .beginProfileCreation(
                proposedProfileID: nil,
                startedAt: referenceDate
            )
        try await first.practiceSettingsRepository.save(
            .defaults(for: reservedID)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: first.dataPaths.profilesSnapshot.path
            )
        )

        let restarted = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Another Seed"),
            transport: transport
        )
        let restartedState = try await restarted.firstRunOnboardingRepository
            .state()
        XCTAssertEqual(restartedState?.pendingCreatedProfileID, reservedID)
        XCTAssertTrue(restarted.profiles.isEmpty)
        let restartedSettings = try await restarted.practiceSettingsRepository
            .settings(for: reservedID)
        XCTAssertEqual(restartedSettings, .defaults(for: reservedID))

        let completion = try await onboarding(in: restarted).complete(
            profileID: nil,
            submission: newKidSubmission
        )
        XCTAssertEqual(completion.selectedProfileID, reservedID)
        XCTAssertEqual(completion.profiles.map(\.id), [reservedID])
    }

    func testRelaunchRejectsNonDefaultOrphanSettingsDespitePendingCreation()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = DiscoveryTransport(
            availability: [.temporarilyUnavailable],
            remoteProfiles: []
        )
        let first = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Unused Seed"),
            transport: transport
        )
        let reservedID = try await first.firstRunOnboardingRepository
            .beginProfileCreation(
                proposedProfileID: nil,
                startedAt: referenceDate
            )
        try await first.practiceSettingsRepository.save(
            ProfilePracticeSettings(
                profileID: reservedID,
                read: LearningRouteSettings(
                    newWordLimit: 9,
                    reviewWordLimit: 5,
                    contentOrder: .newThenReview,
                    emergencyAfterSeconds: 180
                )
            )
        )

        do {
            _ = try await bootstrap(
                in: directory,
                defaultProfile: profile(id: UUID(), name: "Another Seed"),
                transport: transport
            )
            XCTFail("Only exact first-run defaults may resume without a Profile.")
        } catch let error as ApplicationBootstrapError {
            XCTAssertEqual(error, .profileSnapshotMissingWithDependentData)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: first.dataPaths.profilesSnapshot.path
            )
        )
    }

    func testDiscoveryContainmentFenceResumesExactIDAcrossRelaunch()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("onboarding.json")
        let first = LocalFirstRunOnboardingRepository(snapshotURL: snapshotURL)
        try await first.markPending(
            startedAt: referenceDate,
            purpose: .fullSetup
        )
        let reservedID = try await first.beginProfileCreation(
            proposedProfileID: nil,
            startedAt: referenceDate
        )

        let fencedID = try await first.prepareForProfileDiscovery()
        XCTAssertEqual(fencedID, reservedID)
        let restarted = LocalFirstRunOnboardingRepository(
            snapshotURL: snapshotURL
        )
        let resumedID = try await restarted.prepareForProfileDiscovery()
        let fencedState = try await restarted.state()
        XCTAssertEqual(resumedID, reservedID)
        XCTAssertEqual(fencedState?.profileIntent, .discoverExisting)
        XCTAssertEqual(fencedState?.pendingCreatedProfileID, reservedID)

        try await restarted.finishPendingProfileContainment(
            profileID: reservedID
        )
        let committedRestart = LocalFirstRunOnboardingRepository(
            snapshotURL: snapshotURL
        )
        let committedPendingID =
            try await committedRestart
            .prepareForProfileDiscovery()
        XCTAssertNil(committedPendingID)
        let committedState = try await committedRestart.state()
        XCTAssertEqual(committedState?.profileIntent, .discoverExisting)
        XCTAssertNil(committedState?.pendingCreatedProfileID)
    }

    func testDiscoveryContainmentUsesCompleteProfileDataEraserBoundary()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Unused Seed"),
            transport: DiscoveryTransport(
                availability: [.available],
                remoteProfiles: []
            )
        )
        let pendingID = try await environment.firstRunOnboardingRepository
            .beginProfileCreation(
                proposedProfileID: nil,
                startedAt: referenceDate
            )
        try await environment.practiceSettingsRepository.save(
            .defaults(for: pendingID)
        )
        try await environment.profileRepository.save(
            profile(id: pendingID.rawValue, name: "Interrupted Child")
        )
        let eraser = RecordingProfileDataEraser(
            base: environment.profileDataEraser
        )

        let discovered = try await discovery(
            in: environment,
            profileDataEraser: eraser
        ).discoverProfiles()
        let erasedProfileIDs = await eraser.erasedProfileIDs()
        let retainedProfile = try await environment.profileRepository.profile(
            id: pendingID
        )
        let retainedSettings = try await environment.practiceSettingsRepository
            .settings(for: pendingID)

        XCTAssertTrue(discovered.isEmpty)
        XCTAssertEqual(erasedProfileIDs, [pendingID])
        XCTAssertNil(retainedProfile)
        XCTAssertNil(retainedSettings)
    }

    func testDiscoveryContainmentLeavesNoProfileScopedArtifactOrTombstone()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let voiceprints = AdoptionVoiceprintRepository()
        let handwriting = RecordingAdoptionHandwritingRemover()
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Unused Seed"),
            transport: DiscoveryTransport(
                availability: [.available],
                remoteProfiles: []
            ),
            voiceprintRepository: voiceprints,
            handwritingPreferenceRemover: handwriting
        )
        let pendingID = try await environment.firstRunOnboardingRepository
            .beginProfileCreation(
                proposedProfileID: nil,
                startedAt: referenceDate
            )
        let pendingProfile = profile(
            id: pendingID.rawValue,
            name: "Interrupted Child"
        )
        let prompt = try WordPrompt(learningMode: .read, text: "spark")
        try await environment.profileRepository.save(pendingProfile)
        try await environment.practiceSettingsRepository.save(
            .defaults(for: pendingID)
        )
        _ = try await environment.wordPoolRepository.upsert([
            WordPoolEntryDraft(
                profileID: pendingID,
                prompt: prompt,
                addedAt: referenceDate,
                source: .guardianManual,
                positionInBatch: 0
            )
        ])
        try await environment.learningRecordRepository.append(
            AttemptEvent(
                profileID: pendingID,
                wordPromptID: prompt.id,
                learningMode: .read,
                evidence: .firstIndependentAttempt,
                outcome: .correct,
                occurredAt: referenceDate
            )
        )
        let dailyCoordinator = DailyQuestCoordinator(
            repository: environment.dailyQuestRepository,
            timeZone: TimeZone(secondsFromGMT: 0) ?? .current
        )
        let questState = try await dailyCoordinator.loadOrCreateToday(
            candidate: QuestPlan(
                profileID: pendingID,
                configuration: QuestConfiguration(
                    learningMode: .read,
                    newWordLimit: 1,
                    reviewWordLimit: 0,
                    attentionBudget: 1,
                    contentOrder: .newThenReview
                ),
                reviewWordIDs: [],
                newWordIDs: [prompt.id],
                createdAt: referenceDate
            ),
            on: referenceDate
        )
        _ = try await dailyCoordinator.complete(
            try XCTUnwrap(dailyCoordinator.todayLaunch(from: questState)),
            score: QuestScore(
                points: 40,
                firstIndependentCorrectCount: 1,
                firstIndependentAttemptCount: 1,
                stars: QuestStars(earned: [.completion]),
                personalPaceAssessment: .unavailable
            ),
            world: pendingProfile.selectedWorld,
            completedAt: referenceDate
        )
        try await environment.childSessionRepository.saveLastSelectedProfileID(
            pendingID
        )
        try await voiceprints.save(
            DeviceVoiceprintTemplate(
                profileID: pendingID,
                embedding: try VoiceprintEmbedding(
                    modelIdentifier: "test-voice-v1",
                    vector: [1, 0]
                ),
                acceptedSegmentCount: 3,
                acceptedSpeechDuration: ElapsedTime(seconds: 12),
                enrolledAt: referenceDate
            )
        )

        _ = try await discovery(in: environment).discoverProfiles()

        let words = try await environment.wordPoolRepository.entries(
            for: pendingID,
            learningMode: .read,
            includingInactive: true
        )
        let attempts = try await environment.learningRecordRepository.attempts(
            for: pendingID,
            wordPromptID: nil
        )
        let progress = try await environment.learningRecordRepository.allProgress(
            for: pendingID
        )
        let plans = try await environment.dailyQuestRepository.allPlans(
            for: pendingID
        )
        let completions = try await environment.dailyQuestRepository.allCompletions(
            for: pendingID
        )
        let rewards = try await environment.dailyQuestRepository.rewardGrants(
            for: pendingID
        )
        let selectedProfileID = try await environment.childSessionRepository
            .lastSelectedProfileID()
        let voiceprint = try await voiceprints.template(for: pendingID)
        let tombstones = try await environment.tombstoneRepository.tombstones()
        let retainedProfile = try await environment.profileRepository.profile(
            id: pendingID
        )
        let retainedSettings = try await environment.practiceSettingsRepository
            .settings(for: pendingID)

        XCTAssertNil(retainedProfile)
        XCTAssertNil(retainedSettings)
        XCTAssertTrue(words.isEmpty)
        XCTAssertTrue(attempts.isEmpty)
        XCTAssertTrue(progress.isEmpty)
        XCTAssertTrue(plans.isEmpty)
        XCTAssertTrue(completions.isEmpty)
        XCTAssertTrue(rewards.isEmpty)
        XCTAssertNil(selectedProfileID)
        XCTAssertNil(voiceprint)
        XCTAssertEqual(handwriting.removedProfileIDs(), [pendingID])
        XCTAssertTrue(tombstones.isEmpty)
    }

    func testDiscoveryFirstBootstrapNeverPersistsRandomDefaultAcrossRelaunch()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localDefault = profile(id: UUID(), name: "My Kid")
        let transport = DiscoveryTransport(
            availability: [.temporarilyUnavailable],
            remoteProfiles: []
        )

        let first = try await bootstrap(
            in: directory,
            defaultProfile: localDefault,
            transport: transport
        )
        let restarted = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Another Seed"),
            transport: transport
        )

        XCTAssertTrue(first.profiles.isEmpty)
        XCTAssertTrue(restarted.profiles.isEmpty)
        XCTAssertTrue(first.requiresFirstRunOnboarding)
        XCTAssertEqual(first.firstRunOnboardingPurpose, .fullSetup)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: first.dataPaths.profilesSnapshot.path
            )
        )
    }

    func testCleanSecondDeviceDiscoversAndAdoptsExactRemoteUUID() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localDefault = profile(id: UUID(), name: "My Kid")
        let remote = profile(
            id: UUID(uuidString: "6F287B0A-0976-4BC9-92A3-77DDA93AEF30")!,
            name: "Mia",
            world: .frostlightWorld
        )
        let transport = DiscoveryTransport(
            availability: [.available],
            remoteProfiles: [remote]
        )
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: localDefault,
            transport: transport
        )

        let discovered = try await discovery(in: environment).discoverProfiles()
        let completion = try await onboarding(in: environment).complete(
            profileID: nil,
            submission: FirstRunOnboardingSubmission(
                action: .adoptExistingProfile(remote.id)
            )
        )
        let unexpectedSeed = try await environment.profileRepository.profile(
            id: localDefault.id
        )
        let selectedProfileID = try await environment.childSessionRepository
            .lastSelectedProfileID()
        let tombstones = try await environment.tombstoneRepository.tombstones()
        let onboardingState = try await environment.firstRunOnboardingRepository
            .state()

        XCTAssertEqual(discovered.map(\.id), [remote.id])
        XCTAssertEqual(completion.profiles, [remote])
        XCTAssertEqual(completion.selectedProfileID, remote.id)
        XCTAssertNil(unexpectedSeed)
        XCTAssertEqual(selectedProfileID, remote.id)
        XCTAssertTrue(tombstones.isEmpty)
        XCTAssertNil(onboardingState?.profileIntent)

        let restarted = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "New Random Seed"),
            transport: transport
        )
        XCTAssertFalse(restarted.requiresFirstRunOnboarding)
        XCTAssertEqual(restarted.profiles.map(\.id), [remote.id])
        XCTAssertEqual(restarted.lastSelectedProfileID, remote.id)
    }

    func testAdoptionFinalProfileReadFailureLeavesCompletionPendingForRetry()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = profile(id: UUID(), name: "Mia")
        let baseProfiles = InMemoryKidProfileRepository()
        try await baseProfiles.save(remote)
        let profiles = FailingOnceProfilesReadKidProfileRepository(
            base: baseProfiles
        )
        let session = InMemoryChildSessionRepository()
        let onboarding = try await pendingDiscoveryRepository(in: directory)
        let coordinator = creationCoordinator(
            profileRepository: profiles,
            settingsRepository: InMemoryPracticeSettingsRepository(),
            childSessionRepository: session,
            onboardingRepository: onboarding,
            existingProfiles: [remote]
        )
        let submission = FirstRunOnboardingSubmission(
            action: .adoptExistingProfile(remote.id)
        )

        await assertThrowsErrorAsync {
            _ = try await coordinator.complete(
                profileID: nil,
                submission: submission
            )
        }

        let pendingState = try await onboarding.state()
        let selectedAfterFailure = try await session.lastSelectedProfileID()
        XCTAssertEqual(pendingState?.status, .pending)
        XCTAssertEqual(selectedAfterFailure, remote.id)

        let completion = try await coordinator.complete(
            profileID: nil,
            submission: submission
        )
        XCTAssertEqual(completion.profiles.map(\.id), [remote.id])
        XCTAssertEqual(completion.selectedProfileID, remote.id)
        let completedState = try await onboarding.state()
        XCTAssertEqual(completedState?.status, .completed)
    }

    func testRelaunchAfterEnabledAccountChangesReconfirmsBeforeRediscovery()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountAProfile = profile(
            id: UUID(uuidString: "08933BE5-CE79-4C35-AE44-B41B0B0DBCE4")!,
            name: "Mia"
        )
        let accountBProfile = profile(
            id: UUID(uuidString: "57E30E9F-BA0C-4970-B00D-16AF4C0C2F5C")!,
            name: "Noah"
        )
        let accountAServer = DiscoveryRemoteServer(profiles: [accountAProfile])
        let firstTransport = DiscoveryTransport(
            availability: [.available],
            server: accountAServer
        )
        let localDefault = profile(id: UUID(), name: "My Kid")
        let first = try await bootstrap(
            in: directory,
            defaultProfile: localDefault,
            transport: firstTransport
        )

        let discoveredBeforeRelaunch = try await discovery(in: first)
            .discoverProfiles()
        XCTAssertEqual(discoveredBeforeRelaunch.map(\.id), [accountAProfile.id])

        let restartedTransport = DiscoveryTransport(
            availability: [.available],
            remoteProfiles: [accountBProfile],
            confirmationChanges: [.switchedAccounts]
        )
        let restarted = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Another Seed"),
            transport: restartedTransport
        )
        let presented = FirstRunOnboardingProfileSelection.profilesForPresentation(
            liveProfiles: restarted.profiles,
            bootstrappedProfilesWereEmpty: restarted.profiles.isEmpty,
            purpose: try XCTUnwrap(restarted.firstRunOnboardingPurpose),
            familySyncCapability: restartedTransport.capability,
            profileIntent: restarted.firstRunProfileIntent,
            pendingCreatedProfileID:
                restarted.firstRunPendingCreatedProfileID
        )
        let unexpectedSeed = try await restarted.profileRepository.profile(
            id: localDefault.id
        )

        XCTAssertEqual(restarted.profiles.map(\.id), [accountAProfile.id])
        XCTAssertNil(unexpectedSeed)
        XCTAssertEqual(restarted.firstRunProfileIntent, .discoverExisting)
        XCTAssertTrue(restarted.requiresFirstRunOnboarding)
        XCTAssertTrue(
            presented.isEmpty,
            "A discovered Profile must not become an editable new-kid seed."
        )

        let rediscovered = try await discovery(in: restarted).discoverProfiles()
        let firstConfirmationCalls = await firstTransport.confirmationCallCount()
        let restartedConfirmationCalls =
            await restartedTransport.confirmationCallCount()
        let restartedPushes = await restartedTransport.pushedProfileIDs()
        let restartedOutboundProfileIDs =
            await restartedTransport.outboundProfileIDs()
        let retainedAccountAProfile = try await restarted.profileRepository.profile(
            id: accountAProfile.id
        )
        XCTAssertEqual(rediscovered.map(\.id), [accountBProfile.id])
        XCTAssertNil(retainedAccountAProfile)
        XCTAssertEqual(firstConfirmationCalls, 1)
        XCTAssertEqual(
            restartedConfirmationCalls,
            1,
            "A pending onboarding retry must re-confirm the current account before reading its private database."
        )
        XCTAssertTrue(
            !restartedPushes.contains(accountAProfile.id),
            "Re-confirming a switched account must not upload a Profile discovered from the prior account."
        )
        XCTAssertFalse(restartedOutboundProfileIDs.contains(accountAProfile.id))
    }

    func testRetryAfterEnabledAccountChangesReconfirmsBeforeRediscovery()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountAProfile = profile(id: UUID(), name: "Mia")
        let accountBProfile = profile(id: UUID(), name: "Noah")
        let transport = DiscoveryTransport(
            availability: [.available],
            remoteProfiles: [accountAProfile],
            switchedRemoteProfiles: [accountBProfile],
            confirmationChanges: [nil, .switchedAccounts]
        )
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Unused Seed"),
            transport: transport
        )

        let first = try await discovery(in: environment).discoverProfiles()
        await transport.resetOutboundObservations()
        let retried = try await discovery(in: environment).discoverProfiles()
        let confirmationCalls = await transport.confirmationCallCount()
        let pushedProfileIDs = await transport.pushedProfileIDs()
        let outboundProfileIDs = await transport.outboundProfileIDs()

        XCTAssertEqual(first.map(\.id), [accountAProfile.id])
        XCTAssertEqual(retried.map(\.id), [accountBProfile.id])
        XCTAssertEqual(
            confirmationCalls,
            2,
            "Every parent-owned Find retry must re-confirm the active iCloud account."
        )
        XCTAssertTrue(
            !pushedProfileIDs.contains(accountAProfile.id),
            "Rediscovery must never move an unadopted Profile between iCloud accounts."
        )
        XCTAssertFalse(outboundProfileIDs.contains(accountAProfile.id))
    }

    func testSecondFindOnSameAccountRefetchesExactUUIDWithoutOutbound()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = profile(id: UUID(), name: "Mia")
        let transport = DiscoveryTransport(
            availability: [.available],
            remoteProfiles: [remote]
        )
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Unused Seed"),
            transport: transport
        )
        let first = try await discovery(in: environment).discoverProfiles()
        await transport.resetOutboundObservations()

        let second = try await discovery(in: environment).discoverProfiles()
        let profiles = try await environment.profileRepository.profiles()
        let outboundProfileIDs = await transport.outboundProfileIDs()
        let outboundDescriptions = await transport.outboundDescriptions()

        XCTAssertEqual(first.map(\.id), [remote.id])
        XCTAssertEqual(second.map(\.id), [remote.id])
        XCTAssertEqual(profiles.map(\.id), [remote.id])
        XCTAssertTrue(
            outboundProfileIDs.isEmpty,
            "Unexpected rediscovery outbound: \(outboundDescriptions)"
        )
    }

    func testRelaunchAfterCanonicalDiscoveryPurgeBeforeSyncStateDiscard()
        async throws
    {
        try await assertRelaunchAfterInterruptedDiscoveryReset(
            discardApplyStateBeforeRelaunch: false
        )
    }

    func testRelaunchAfterApplyStateDiscardBeforeJournalDiscard()
        async throws
    {
        try await assertRelaunchAfterInterruptedDiscoveryReset(
            discardApplyStateBeforeRelaunch: true
        )
    }

    func testRelaunchAfterUnadoptedPurgeFailsBeforeFinalProfileDelete()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountAProfile = profile(id: UUID(), name: "Mia")
        let accountBProfile = profile(id: UUID(), name: "Noah")
        let firstTransport = DiscoveryTransport(
            availability: [.available],
            remoteProfiles: [accountAProfile]
        )
        let first = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Unused Seed"),
            transport: firstTransport
        )
        _ = try await discovery(in: first).discoverProfiles()
        _ = try await ManualWordPoolImporter(
            repository: first.wordPoolRepository
        ).importBatch(
            "secret",
            profileID: accountAProfile.id,
            learningMode: .read,
            addedAt: referenceDate
        )
        let partialEraser = FailingBeforeProfileDeleteEraser(
            base: first.profileDataEraser,
            wordPoolRepository: first.wordPoolRepository
        )

        await assertThrowsErrorAsync {
            _ = try await self.discovery(
                in: first,
                profileDataEraser: partialEraser
            ).discoverProfiles()
        }
        let retainedProfile = try await first.profileRepository.profile(
            id: accountAProfile.id
        )
        let retainedWords = try await first.wordPoolRepository.entries(
            for: accountAProfile.id,
            learningMode: .read,
            includingInactive: true
        )
        let syncIsEnabled = await first.familySyncCoordinator.isEnabled()
        XCTAssertNotNil(retainedProfile)
        XCTAssertTrue(retainedWords.isEmpty)
        XCTAssertFalse(syncIsEnabled)
        let resetState = try await first.firstRunOnboardingRepository.state()
        XCTAssertEqual(resetState?.discoveryResetPhase, .required)
        do {
            _ = try await onboarding(in: first).complete(
                profileID: nil,
                submission: newKidSubmission
            )
            XCTFail("Create must remain blocked after a partial purge.")
        } catch {
            XCTAssertEqual(
                error as? FirstRunOnboardingRepositoryError,
                .discoveryResetRequired
            )
        }
        do {
            _ = try await onboarding(in: first).complete(
                profileID: nil,
                submission: FirstRunOnboardingSubmission(
                    action: .adoptExistingProfile(accountAProfile.id)
                )
            )
            XCTFail("Adoption must remain blocked after a partial purge.")
        } catch {
            XCTAssertEqual(
                error as? FirstRunOnboardingRepositoryError,
                .discoveryResetRequired
            )
        }

        let restartedTransport = DiscoveryTransport(
            availability: [.available],
            remoteProfiles: [accountBProfile],
            confirmationChanges: [.switchedAccounts]
        )
        let restarted = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Another Seed"),
            transport: restartedTransport
        )
        let discovered = try await discovery(in: restarted).discoverProfiles()
        let outboundProfileIDs = await restartedTransport.outboundProfileIDs()

        XCTAssertEqual(discovered.map(\.id), [accountBProfile.id])
        XCTAssertFalse(outboundProfileIDs.contains(accountAProfile.id))
    }

    func testRetryAfterAccountBConfirmationAndFetchFailureRemainsIsolated()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountAProfile = profile(id: UUID(), name: "Mia")
        let accountBProfile = profile(id: UUID(), name: "Noah")
        let transport = DiscoveryTransport(
            availability: [.available],
            remoteProfiles: [accountAProfile],
            switchedRemoteProfiles: [accountBProfile],
            confirmationChanges: [nil, .switchedAccounts]
        )
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Unused Seed"),
            transport: transport
        )
        // The first account-A fetch must succeed; inject the failure only for
        // the account-B confirmation boundary.
        await transport.setFetchFailures(0)
        _ = try await discovery(in: environment).discoverProfiles()
        await transport.resetOutboundObservations()
        await transport.setFetchFailures(1)

        await assertThrowsErrorAsync {
            _ = try await self.discovery(in: environment).discoverProfiles()
        }
        let profileAfterFailure = try await environment.profileRepository.profile(
            id: accountAProfile.id
        )
        XCTAssertNil(profileAfterFailure)
        do {
            _ = try await onboarding(in: environment).complete(
                profileID: nil,
                submission: newKidSubmission
            )
            XCTFail("Create must remain blocked after a partial account fetch.")
        } catch {
            XCTAssertEqual(
                error as? FirstRunOnboardingRepositoryError,
                .discoveryResetRequired
            )
        }

        let discovered = try await discovery(in: environment).discoverProfiles()
        let outboundProfileIDs = await transport.outboundProfileIDs()
        let confirmationCalls = await transport.confirmationCallCount()
        XCTAssertEqual(discovered.map(\.id), [accountBProfile.id])
        XCTAssertFalse(outboundProfileIDs.contains(accountAProfile.id))
        XCTAssertEqual(confirmationCalls, 3)
    }

    func testConsentRefreshFindNeverDiscardsAnAdmittedProfileOrWordPool()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = ApplicationDataPaths(applicationSupportDirectory: directory)
        let admitted = profile(id: UUID(), name: "Mia")
        try await LocalJSONKidProfileRepository(
            snapshotURL: paths.profilesSnapshot
        ).save(admitted)
        let words = LocalJSONWordPoolRepository(
            snapshotURL: paths.wordPoolSnapshot
        )
        _ = try await ManualWordPoolImporter(repository: words).importBatch(
            "family",
            profileID: admitted.id,
            learningMode: .read,
            addedAt: referenceDate
        )
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Unused Seed"),
            transport: DiscoveryTransport(
                availability: [.available],
                remoteProfiles: [admitted]
            )
        )
        XCTAssertEqual(environment.firstRunOnboardingPurpose, .consentRefresh)

        _ = try await discovery(in: environment).discoverProfiles()

        let retainedProfile = try await environment.profileRepository.profile(
            id: admitted.id
        )
        let retainedWords = try await environment.wordPoolRepository.entries(
            for: admitted.id,
            learningMode: .read,
            includingInactive: true
        )
        XCTAssertEqual(retainedProfile, admitted)
        XCTAssertEqual(retainedWords.map(\.prompt.normalizedText), ["family"])
    }

    func testTemporaryAccountConfirmationFailureIsReportedAsOffline()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = DiscoveryTransport(
            availability: [.available, .temporarilyUnavailable],
            remoteProfiles: [],
            confirmationFailures: 1
        )
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "My Kid"),
            transport: transport
        )

        do {
            _ = try await discovery(in: environment).discoverProfiles()
            XCTFail("A temporary confirmation failure must remain retryable.")
        } catch {
            XCTAssertEqual(error as? FirstRunProfileDiscoveryError, .offline)
        }

        let confirmationCalls = await transport.confirmationCallCount()
        let syncIsEnabled = await environment.familySyncCoordinator.isEnabled()
        let profiles = try await environment.profileRepository.profiles()
        XCTAssertEqual(confirmationCalls, 1)
        XCTAssertFalse(syncIsEnabled)
        XCTAssertTrue(profiles.isEmpty)
    }

    func testSameNicknameRemoteProfilesRemainDistinctAndSelectionUsesExactID()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = profile(
            id: UUID(uuidString: "2AC6D95E-6A04-4EA3-BD28-A6F75F94DC92")!,
            name: "Mia",
            world: .moonpetalKingdom
        )
        let second = profile(
            id: UUID(uuidString: "95E88702-2097-43DB-8869-919868994144")!,
            name: "Mia",
            world: .dinoDiscovery
        )
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Mia"),
            transport: DiscoveryTransport(
                availability: [.available],
                remoteProfiles: [second, first]
            )
        )

        let discovered = try await discovery(in: environment).discoverProfiles()
        let completion = try await onboarding(in: environment).complete(
            profileID: nil,
            submission: FirstRunOnboardingSubmission(
                action: .adoptExistingProfile(second.id)
            )
        )
        let selectedProfileID = try await environment.childSessionRepository
            .lastSelectedProfileID()

        XCTAssertEqual(Set(discovered.map(\.id)), [first.id, second.id])
        XCTAssertEqual(Set(completion.profiles.map(\.id)), [first.id, second.id])
        XCTAssertEqual(completion.selectedProfileID, second.id)
        XCTAssertEqual(selectedProfileID, second.id)
    }

    func testOfflineDiscoveryLeavesFamilyEmptyThenRetryAfterRelaunchSucceeds()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localDefault = profile(id: UUID(), name: "My Kid")
        let remote = profile(id: UUID(), name: "Mia")
        let transport = DiscoveryTransport(
            availability: [.temporarilyUnavailable, .available],
            remoteProfiles: [remote]
        )
        let first = try await bootstrap(
            in: directory,
            defaultProfile: localDefault,
            transport: transport
        )

        do {
            _ = try await discovery(in: first).discoverProfiles()
            XCTFail("Offline discovery should remain retryable.")
        } catch {
            XCTAssertEqual(error as? FirstRunProfileDiscoveryError, .offline)
        }
        let profilesAfterOfflineAttempt = try await first.profileRepository.profiles()
        XCTAssertTrue(profilesAfterOfflineAttempt.isEmpty)

        let restarted = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Another Seed"),
            transport: transport
        )
        let discovered = try await discovery(in: restarted).discoverProfiles()
        let unexpectedSeed = try await restarted.profileRepository.profile(
            id: localDefault.id
        )

        XCTAssertEqual(discovered.map(\.id), [remote.id])
        XCTAssertEqual(restarted.firstRunProfileIntent, .discoverExisting)
        XCTAssertNil(unexpectedSeed)
    }

    func testOfflineFindAfterAccountAThenExplicitCreateCannotCarryAIntoB()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountAProfile = profile(id: UUID(), name: "Mia")
        let transport = DiscoveryTransport(
            availability: [.available, .available],
            remoteProfiles: [accountAProfile],
            switchedRemoteProfiles: [],
            confirmationChanges: [nil, .switchedAccounts]
        )
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Unused Seed"),
            transport: transport
        )
        _ = try await discovery(in: environment).discoverProfiles()
        await transport.setAvailability([.temporarilyUnavailable])

        await assertThrowsErrorAsync {
            _ = try await self.discovery(in: environment).discoverProfiles()
        }
        let accountAAfterOfflineFind = try await environment.profileRepository
            .profile(id: accountAProfile.id)
        let syncEnabledAfterOfflineFind =
            await environment.familySyncCoordinator.isEnabled()
        XCTAssertNil(accountAAfterOfflineFind)
        XCTAssertFalse(syncEnabledAfterOfflineFind)

        let created = try await onboarding(in: environment).complete(
            profileID: nil,
            submission: newKidSubmission
        )
        let newProfileID = try XCTUnwrap(created.selectedProfileID)
        await transport.resetOutboundObservations()
        await transport.setAvailability([.available])
        _ = try await environment.familySyncCoordinator.setEnabled(true)
        let outboundProfileIDs = await transport.outboundProfileIDs()
        let tombstones = try await environment.tombstoneRepository.tombstones()

        XCTAssertNotEqual(newProfileID, accountAProfile.id)
        XCTAssertFalse(outboundProfileIDs.contains(accountAProfile.id))
        XCTAssertTrue(tombstones.isEmpty)
    }

    func testNoICloudAccountDoesNotCreatePlaceholder() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localDefault = profile(id: UUID(), name: "My Kid")
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: localDefault,
            transport: DiscoveryTransport(
                availability: [.noAccount],
                remoteProfiles: []
            )
        )

        do {
            _ = try await discovery(in: environment).discoverProfiles()
            XCTFail("A signed-out device should not report successful discovery.")
        } catch {
            XCTAssertEqual(
                error as? FirstRunProfileDiscoveryError,
                .iCloudUnavailable
            )
        }
        let profiles = try await environment.profileRepository.profiles()
        let selectedProfileID = try await environment.childSessionRepository
            .lastSelectedProfileID()
        let tombstones = try await environment.tombstoneRepository.tombstones()

        XCTAssertTrue(profiles.isEmpty)
        XCTAssertNil(selectedProfileID)
        XCTAssertTrue(tombstones.isEmpty)
    }

    func testExplicitOfflineNewKidCreatesFreshIdentityAndDefaultSettings()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localDefault = profile(id: UUID(), name: "My Kid")
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: localDefault,
            transport: DiscoveryTransport(
                availability: [.temporarilyUnavailable],
                remoteProfiles: []
            )
        )

        let completion = try await onboarding(in: environment).complete(
            profileID: nil,
            submission: FirstRunOnboardingSubmission(
                action: .createProfile(
                    GuardianProfileDraft(
                        displayName: "Coco",
                        avatarAssetID: "owl",
                        selectedWorld: .buildItBay,
                        schoolGrade: .preK,
                        ageYears: 4
                    )
                )
            )
        )
        let created = try XCTUnwrap(completion.profiles.first)
        let settings = try await environment.practiceSettingsRepository.settings(
            for: created.id
        )
        let isSyncEnabled = await environment.familySyncCoordinator.isEnabled()
        let tombstones = try await environment.tombstoneRepository.tombstones()
        let onboardingState = try await environment.firstRunOnboardingRepository
            .state()

        XCTAssertNotEqual(created.id, localDefault.id)
        XCTAssertEqual(created.displayName, "Coco")
        XCTAssertEqual(settings, .defaults(for: created.id))
        XCTAssertFalse(isSyncEnabled)
        XCTAssertTrue(tombstones.isEmpty)
        XCTAssertNil(onboardingState?.profileIntent)
    }

    func testExplicitNewKidCreationWorksWithoutAnICloudAccount() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "My Kid"),
            transport: DiscoveryTransport(
                availability: [.noAccount],
                remoteProfiles: []
            )
        )

        let completion = try await onboarding(in: environment).complete(
            profileID: nil,
            submission: FirstRunOnboardingSubmission(
                action: .createProfile(
                    GuardianProfileDraft(
                        displayName: "Coco",
                        avatarAssetID: "owl",
                        selectedWorld: .buildItBay,
                        schoolGrade: .preK,
                        ageYears: 4
                    )
                )
            )
        )
        let created = try XCTUnwrap(completion.profiles.first)
        let saved = try await environment.profileRepository.profile(id: created.id)
        let settings = try await environment.practiceSettingsRepository.settings(
            for: created.id
        )
        let onboardingState = try await environment.firstRunOnboardingRepository
            .state()

        XCTAssertEqual(saved?.displayName, "Coco")
        XCTAssertEqual(settings, .defaults(for: created.id))
        XCTAssertEqual(onboardingState?.status, .completed)
        XCTAssertNil(onboardingState?.profileIntent)
    }

    func testCreationIntentWriteFailureMutatesNoProfile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = profile(id: UUID(), name: "Mia")
        let profiles = InMemoryKidProfileRepository()
        try await profiles.save(remote)
        let settings = InMemoryPracticeSettingsRepository()
        let baseOnboarding = try await pendingDiscoveryRepository(in: directory)
        let onboarding = FailingOnceOnboardingRepository(
            base: baseOnboarding,
            failure: .beginCreation
        )
        let coordinator = creationCoordinator(
            profileRepository: profiles,
            settingsRepository: settings,
            childSessionRepository: InMemoryChildSessionRepository(),
            onboardingRepository: onboarding,
            existingProfiles: [remote]
        )

        await assertThrowsErrorAsync {
            _ = try await coordinator.complete(
                profileID: remote.id,
                submission: self.newKidSubmission
            )
        }

        let profilesAfterFailure = try await profiles.profiles()
        let remoteSettings = try await settings.settings(for: remote.id)
        XCTAssertEqual(profilesAfterFailure, [remote])
        XCTAssertNil(remoteSettings)
        let pending = try await baseOnboarding.state()
        XCTAssertEqual(pending?.profileIntent, .discoverExisting)
        XCTAssertNil(pending?.pendingCreatedProfileID)
    }

    func testSettingsFailureRetriesWithReservedIDWithoutTouchingRemote()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = profile(id: UUID(), name: "Mia")
        let profiles = InMemoryKidProfileRepository()
        try await profiles.save(remote)
        let settings = FailingOncePracticeSettingsRepository()
        let onboarding = try await pendingDiscoveryRepository(in: directory)
        let coordinator = creationCoordinator(
            profileRepository: profiles,
            settingsRepository: settings,
            childSessionRepository: InMemoryChildSessionRepository(),
            onboardingRepository: onboarding,
            existingProfiles: [remote]
        )

        await assertThrowsErrorAsync {
            _ = try await coordinator.complete(
                profileID: remote.id,
                submission: self.newKidSubmission
            )
        }
        let pendingState = try await onboarding.state()
        let pendingID = try XCTUnwrap(pendingState?.pendingCreatedProfileID)
        let profilesAfterFailure = try await profiles.profiles()
        XCTAssertNotEqual(pendingID, remote.id)
        XCTAssertEqual(profilesAfterFailure, [remote])

        let completion = try await coordinator.complete(
            profileID: remote.id,
            submission: newKidSubmission
        )
        XCTAssertEqual(completion.selectedProfileID, pendingID)
        XCTAssertEqual(Set(completion.profiles.map(\.id)), [remote.id, pendingID])
        let savedRemote = try await profiles.profile(id: remote.id)
        let savedSettings = try await settings.settings(for: pendingID)
        XCTAssertEqual(savedRemote, remote)
        XCTAssertEqual(
            savedSettings,
            .defaults(for: pendingID)
        )
    }

    func testProfileFailureRollsBackSettingsAndRetriesTheReservedID()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = profile(id: UUID(), name: "Mia")
        let profiles = FailingOnceKidProfileRepository(seed: [remote])
        let settings = InMemoryPracticeSettingsRepository()
        let onboarding = try await pendingDiscoveryRepository(in: directory)
        let coordinator = creationCoordinator(
            profileRepository: profiles,
            settingsRepository: settings,
            childSessionRepository: InMemoryChildSessionRepository(),
            onboardingRepository: onboarding,
            existingProfiles: [remote]
        )

        await assertThrowsErrorAsync {
            _ = try await coordinator.complete(
                profileID: remote.id,
                submission: self.newKidSubmission
            )
        }
        let pendingState = try await onboarding.state()
        let pendingID = try XCTUnwrap(pendingState?.pendingCreatedProfileID)
        let profilesAfterFailure = try await profiles.profiles()
        let rolledBackSettings = try await settings.settings(for: pendingID)
        XCTAssertNotEqual(pendingID, remote.id)
        XCTAssertEqual(profilesAfterFailure, [remote])
        XCTAssertNil(rolledBackSettings)

        let completion = try await coordinator.complete(
            profileID: remote.id,
            submission: newKidSubmission
        )
        XCTAssertEqual(completion.selectedProfileID, pendingID)
        XCTAssertEqual(Set(completion.profiles.map(\.id)), [remote.id, pendingID])
        let savedRemote = try await profiles.profile(id: remote.id)
        XCTAssertEqual(savedRemote, remote)
    }

    func testSessionFailureRetryCreatesAtMostOneNewIdentity() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = profile(id: UUID(), name: "Mia")
        let profiles = InMemoryKidProfileRepository()
        try await profiles.save(remote)
        let settings = InMemoryPracticeSettingsRepository()
        let session = FailingOnceChildSessionRepository()
        let onboarding = try await pendingDiscoveryRepository(in: directory)
        let coordinator = creationCoordinator(
            profileRepository: profiles,
            settingsRepository: settings,
            childSessionRepository: session,
            onboardingRepository: onboarding,
            existingProfiles: [remote]
        )

        await assertThrowsErrorAsync {
            _ = try await coordinator.complete(
                profileID: remote.id,
                submission: self.newKidSubmission
            )
        }
        let pendingState = try await onboarding.state()
        let pendingID = try XCTUnwrap(pendingState?.pendingCreatedProfileID)
        let profileIDsAfterFailure = Set(
            try await profiles.profiles().map(\.id)
        )
        XCTAssertEqual(
            profileIDsAfterFailure,
            [remote.id, pendingID]
        )

        let completion = try await coordinator.complete(
            profileID: remote.id,
            submission: newKidSubmission
        )
        XCTAssertEqual(completion.selectedProfileID, pendingID)
        XCTAssertEqual(Set(completion.profiles.map(\.id)), [remote.id, pendingID])
        let savedRemote = try await profiles.profile(id: remote.id)
        XCTAssertEqual(savedRemote, remote)
    }

    func testCompletionMarkerFailureRetryCreatesAtMostOneNewIdentity()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = profile(id: UUID(), name: "Mia")
        let profiles = InMemoryKidProfileRepository()
        try await profiles.save(remote)
        let settings = InMemoryPracticeSettingsRepository()
        let session = InMemoryChildSessionRepository()
        let baseOnboarding = try await pendingDiscoveryRepository(in: directory)
        let onboarding = FailingOnceOnboardingRepository(
            base: baseOnboarding,
            failure: .completion
        )
        let coordinator = creationCoordinator(
            profileRepository: profiles,
            settingsRepository: settings,
            childSessionRepository: session,
            onboardingRepository: onboarding,
            existingProfiles: [remote]
        )

        await assertThrowsErrorAsync {
            _ = try await coordinator.complete(
                profileID: remote.id,
                submission: self.newKidSubmission
            )
        }
        let pendingState = try await baseOnboarding.state()
        let pendingID = try XCTUnwrap(pendingState?.pendingCreatedProfileID)
        let selectedAfterFailure = try await session.lastSelectedProfileID()
        let profileIDsAfterFailure = Set(
            try await profiles.profiles().map(\.id)
        )
        XCTAssertEqual(selectedAfterFailure, pendingID)
        XCTAssertEqual(
            profileIDsAfterFailure,
            [remote.id, pendingID]
        )

        let completion = try await coordinator.complete(
            profileID: remote.id,
            submission: newKidSubmission
        )
        XCTAssertEqual(completion.selectedProfileID, pendingID)
        XCTAssertEqual(Set(completion.profiles.map(\.id)), [remote.id, pendingID])
        let completedState = try await baseOnboarding.state()
        let savedRemote = try await profiles.profile(id: remote.id)
        XCTAssertNil(completedState?.pendingCreatedProfileID)
        XCTAssertEqual(savedRemote, remote)
    }

    func testCreationFinalProfileReadFailureRetriesReservedIdentity()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = profile(id: UUID(), name: "Mia")
        let baseProfiles = InMemoryKidProfileRepository()
        try await baseProfiles.save(remote)
        let profiles = FailingOnceProfilesReadKidProfileRepository(
            base: baseProfiles
        )
        let onboarding = try await pendingDiscoveryRepository(in: directory)
        let coordinator = creationCoordinator(
            profileRepository: profiles,
            settingsRepository: InMemoryPracticeSettingsRepository(),
            childSessionRepository: InMemoryChildSessionRepository(),
            onboardingRepository: onboarding,
            existingProfiles: [remote]
        )

        await assertThrowsErrorAsync {
            _ = try await coordinator.complete(
                profileID: remote.id,
                submission: self.newKidSubmission
            )
        }

        let pendingState = try await onboarding.state()
        let pendingID = try XCTUnwrap(pendingState?.pendingCreatedProfileID)
        let profileIDsAfterFailure = Set(
            try await baseProfiles.profiles().map(\.id)
        )
        XCTAssertEqual(pendingState?.status, .pending)
        XCTAssertNotEqual(pendingID, remote.id)
        XCTAssertEqual(profileIDsAfterFailure, [remote.id, pendingID])

        let completion = try await coordinator.complete(
            profileID: remote.id,
            submission: newKidSubmission
        )
        XCTAssertEqual(completion.selectedProfileID, pendingID)
        XCTAssertEqual(
            Set(completion.profiles.map(\.id)),
            [remote.id, pendingID]
        )
        let finalProfileIDs = Set(try await baseProfiles.profiles().map(\.id))
        let completedState = try await onboarding.state()
        XCTAssertEqual(finalProfileIDs, [remote.id, pendingID])
        XCTAssertEqual(completedState?.status, .completed)
    }

    func testSessionFailureThenFindContainsPendingProfileBeforeSync()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = profile(id: UUID(), name: "Mia")
        let transport = DiscoveryTransport(
            availability: [.available],
            remoteProfiles: [remote]
        )
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Unused Seed"),
            transport: transport
        )
        let initiallyDiscovered = try await discovery(in: environment)
            .discoverProfiles()
        XCTAssertEqual(initiallyDiscovered.map(\.id), [remote.id])
        let failingCoordinator = creationCoordinator(
            profileRepository: environment.profileRepository,
            settingsRepository: environment.practiceSettingsRepository,
            childSessionRepository: FailingOnceChildSessionRepository(),
            onboardingRepository: environment.firstRunOnboardingRepository,
            existingProfiles: [remote]
        )

        await assertThrowsErrorAsync {
            _ = try await failingCoordinator.complete(
                profileID: remote.id,
                submission: self.newKidSubmission
            )
        }
        let failedState = try await environment.firstRunOnboardingRepository
            .state()
        let pendingID = try XCTUnwrap(failedState?.pendingCreatedProfileID)
        let pendingProfileBeforeFind = try await environment.profileRepository
            .profile(id: pendingID)
        let pendingSettingsBeforeFind =
            try await environment
            .practiceSettingsRepository.settings(for: pendingID)
        XCTAssertNotNil(pendingProfileBeforeFind)
        XCTAssertEqual(
            pendingSettingsBeforeFind,
            .defaults(for: pendingID)
        )
        _ = await environment.familySyncCoordinator.synchronize(
            trigger: .remoteNotification
        )
        let pushesBeforeFind = await transport.pushedProfileIDs()
        let journalBeforeFind = try familySyncJournal(in: environment)
        XCTAssertFalse(pushesBeforeFind.contains(pendingID))
        XCTAssertFalse(
            journalBeforeFind.localManifest.contains {
                $0.key.profileID == pendingID
            }
        )
        XCTAssertFalse(
            journalBeforeFind.outbox.contains {
                $0.key.profileID == pendingID
            }
        )

        let rediscovered = try await discovery(in: environment)
            .discoverProfiles()
        let discoveryState = try await environment.firstRunOnboardingRepository
            .state()
        XCTAssertEqual(rediscovered.map(\.id), [remote.id])
        XCTAssertEqual(discoveryState?.profileIntent, .discoverExisting)
        XCTAssertNil(discoveryState?.pendingCreatedProfileID)
        let completion = try await onboarding(in: environment).complete(
            profileID: remote.id,
            submission: FirstRunOnboardingSubmission(
                action: .adoptExistingProfile(remote.id)
            )
        )

        XCTAssertEqual(completion.profiles.map(\.id), [remote.id])
        let containedProfile = try await environment.profileRepository.profile(
            id: pendingID
        )
        let containedSettings = try await environment.practiceSettingsRepository
            .settings(for: pendingID)
        let tombstones = try await environment.tombstoneRepository.tombstones()
        let allPushes = await transport.pushedProfileIDs()
        XCTAssertNil(containedProfile)
        XCTAssertNil(containedSettings)
        XCTAssertTrue(tombstones.isEmpty)
        XCTAssertFalse(allPushes.contains(pendingID))
    }

    func testCompletionFailureThenFindContainsPendingProfileBeforeSync()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = profile(id: UUID(), name: "Mia")
        let transport = DiscoveryTransport(
            availability: [.available],
            remoteProfiles: [remote]
        )
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Unused Seed"),
            transport: transport
        )
        let initiallyDiscovered = try await discovery(in: environment)
            .discoverProfiles()
        XCTAssertEqual(initiallyDiscovered.map(\.id), [remote.id])
        let failingOnboarding = FailingOnceOnboardingRepository(
            base: environment.firstRunOnboardingRepository,
            failure: .completion
        )
        let failingCoordinator = creationCoordinator(
            profileRepository: environment.profileRepository,
            settingsRepository: environment.practiceSettingsRepository,
            childSessionRepository: environment.childSessionRepository,
            onboardingRepository: failingOnboarding,
            existingProfiles: [remote]
        )

        await assertThrowsErrorAsync {
            _ = try await failingCoordinator.complete(
                profileID: remote.id,
                submission: self.newKidSubmission
            )
        }
        let failedState = try await environment.firstRunOnboardingRepository
            .state()
        let pendingID = try XCTUnwrap(failedState?.pendingCreatedProfileID)
        let pendingProfileBeforeFind = try await environment.profileRepository
            .profile(id: pendingID)
        let pendingSettingsBeforeFind =
            try await environment
            .practiceSettingsRepository.settings(for: pendingID)
        let selectedAfterFailure = try await environment.childSessionRepository
            .lastSelectedProfileID()
        XCTAssertNotNil(pendingProfileBeforeFind)
        XCTAssertEqual(
            pendingSettingsBeforeFind,
            .defaults(for: pendingID)
        )
        XCTAssertEqual(selectedAfterFailure, pendingID)
        _ = await environment.familySyncCoordinator.synchronize(
            trigger: .connectivityRecovery
        )
        let pushesBeforeFind = await transport.pushedProfileIDs()
        let journalBeforeFind = try familySyncJournal(in: environment)
        XCTAssertFalse(pushesBeforeFind.contains(pendingID))
        XCTAssertFalse(
            journalBeforeFind.localManifest.contains {
                $0.key.profileID == pendingID
            }
        )
        XCTAssertFalse(
            journalBeforeFind.outbox.contains {
                $0.key.profileID == pendingID
            }
        )

        let rediscovered = try await discovery(in: environment)
            .discoverProfiles()
        let discoveryState = try await environment.firstRunOnboardingRepository
            .state()
        XCTAssertEqual(rediscovered.map(\.id), [remote.id])
        XCTAssertEqual(discoveryState?.profileIntent, .discoverExisting)
        XCTAssertNil(discoveryState?.pendingCreatedProfileID)
        let completion = try await onboarding(in: environment).complete(
            profileID: remote.id,
            submission: FirstRunOnboardingSubmission(
                action: .adoptExistingProfile(remote.id)
            )
        )

        XCTAssertEqual(completion.profiles.map(\.id), [remote.id])
        let selectedAfterAdoption = try await environment.childSessionRepository
            .lastSelectedProfileID()
        let containedProfile = try await environment.profileRepository.profile(
            id: pendingID
        )
        let containedSettings = try await environment.practiceSettingsRepository
            .settings(for: pendingID)
        let tombstones = try await environment.tombstoneRepository.tombstones()
        let allPushes = await transport.pushedProfileIDs()
        XCTAssertEqual(selectedAfterAdoption, remote.id)
        XCTAssertNil(containedProfile)
        XCTAssertNil(containedSettings)
        XCTAssertTrue(tombstones.isEmpty)
        XCTAssertFalse(allPushes.contains(pendingID))
    }

    private var newKidSubmission: FirstRunOnboardingSubmission {
        FirstRunOnboardingSubmission(
            action: .createProfile(
                GuardianProfileDraft(
                    displayName: "Coco",
                    avatarAssetID: "owl",
                    selectedWorld: .buildItBay,
                    schoolGrade: .preK,
                    ageYears: 4
                )
            )
        )
    }

    private func pendingDiscoveryRepository(
        in directory: URL
    ) async throws -> LocalFirstRunOnboardingRepository {
        let repository = LocalFirstRunOnboardingRepository(
            snapshotURL: directory.appendingPathComponent("onboarding.json")
        )
        try await repository.markPending(
            startedAt: referenceDate,
            purpose: .fullSetup
        )
        try await repository.markDiscoveryIntent()
        // These creation-interruption tests start from the state after a
        // successful Find. The production discovery coordinator clears this
        // gate only after canonical and sync-owned state are verified empty.
        try await repository.finishDiscoveryReset()
        try await repository.beginAccountBoundDiscovery()
        try await repository.finishProfileDiscovery()
        return repository
    }

    private func creationCoordinator(
        profileRepository: any KidProfileRepository,
        settingsRepository: any PracticeSettingsRepository,
        childSessionRepository: any ChildSessionRepository,
        onboardingRepository: any FirstRunOnboardingPersisting,
        existingProfiles: [KidProfile]
    ) -> FirstRunOnboardingCoordinator {
        let guardianStore = RepositoryGuardianFamilyStore(
            profiles: existingProfiles,
            profileRepository: profileRepository,
            wordPoolRepository: InMemoryWordPoolRepository(),
            practiceSettingsRepository: settingsRepository,
            clock: AdoptionClock(now: referenceDate),
            timeZone: TimeZone(secondsFromGMT: 0) ?? .current
        )
        return FirstRunOnboardingCoordinator(
            profileRepository: profileRepository,
            childSessionRepository: childSessionRepository,
            onboardingRepository: onboardingRepository,
            guardianStore: guardianStore,
            clock: AdoptionClock(now: referenceDate)
        )
    }

    private func discovery(
        in environment: ProductionApplicationEnvironment,
        profileDataEraser: (any ProfileDataErasing)? = nil
    ) -> FirstRunProfileDiscoveryCoordinator {
        FirstRunProfileDiscoveryCoordinator(
            familySyncCoordinator: environment.familySyncCoordinator,
            familySyncTransport: environment.familySyncTransport,
            profileRepository: environment.profileRepository,
            practiceSettingsRepository: environment.practiceSettingsRepository,
            childSessionRepository: environment.childSessionRepository,
            onboardingRepository: environment.firstRunOnboardingRepository,
            profileDataEraser: profileDataEraser ?? environment.profileDataEraser,
            familySyncJournalRepository:
                environment.familySyncJournalRepository,
            familySyncApplyTransactionRepository:
                environment.familySyncApplyTransactionRepository
        )
    }

    private func onboarding(
        in environment: ProductionApplicationEnvironment
    ) -> FirstRunOnboardingCoordinator {
        FirstRunOnboardingCoordinator(
            profileRepository: environment.profileRepository,
            childSessionRepository: environment.childSessionRepository,
            onboardingRepository: environment.firstRunOnboardingRepository,
            guardianStore: environment.guardianStore,
            clock: AdoptionClock(now: referenceDate)
        )
    }

    private func bootstrap(
        in directory: URL,
        defaultProfile: KidProfile,
        transport: any FamilySyncTransport,
        voiceprintRepository: (any DeviceVoiceprintRepository)? = nil,
        handwritingPreferenceRemover: any HandwritingPreferenceRemoving =
            HandwritingPreferenceStore()
    ) async throws -> ProductionApplicationEnvironment {
        try await ProductionApplicationBootstrapper(
            applicationSupportDirectory: { directory },
            defaultProfile: defaultProfile,
            clock: AdoptionClock(now: referenceDate),
            timeZone: TimeZone(secondsFromGMT: 0) ?? .current,
            familySyncTransport: transport,
            voiceprintRepository: voiceprintRepository,
            handwritingPreferenceRemover: handwritingPreferenceRemover
        ).bootstrap()
    }

    private func profile(
        id: UUID,
        name: String,
        world: WorldTheme = .moonpetalKingdom
    ) -> KidProfile {
        KidProfile(
            id: ProfileID(rawValue: id),
            displayName: name,
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: world,
            starterWorld: world,
            schoolGrade: .preK,
            ageYears: 4,
            createdAt: referenceDate.addingTimeInterval(-86_400),
            updatedAt: referenceDate
        )
    }

    private func familySyncJournal(
        in environment: ProductionApplicationEnvironment
    ) throws -> FamilySyncJournalSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(
            FamilySyncJournalSnapshot.self,
            from: Data(
                contentsOf: environment.dataPaths.familySyncJournalSnapshot
            )
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaWordsSecondDevice-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func assertRelaunchAfterInterruptedDiscoveryReset(
        discardApplyStateBeforeRelaunch: Bool
    ) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountAProfile = profile(id: UUID(), name: "Mia")
        let accountBProfile = profile(id: UUID(), name: "Noah")
        let firstTransport = DiscoveryTransport(
            availability: [.available],
            remoteProfiles: [accountAProfile]
        )
        let first = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Unused Seed"),
            transport: firstTransport
        )
        _ = try await discovery(in: first).discoverProfiles()

        _ = try await first.firstRunOnboardingRepository
            .prepareForProfileDiscovery()
        _ = try await first.familySyncCoordinator.disableAndAwaitQuiescence()
        try await first.profileDataEraser.eraseUnadoptedProfileData(
            for: accountAProfile.id
        )
        if discardApplyStateBeforeRelaunch {
            try await first.familySyncApplyTransactionRepository
                .discardUnadoptedProfileState()
        }
        let interruptedJournal = try familySyncJournal(in: first)
        XCTAssertTrue(
            interruptedJournal.localManifest.contains {
                $0.key.profileID == accountAProfile.id
            }
        )
        let interruptedState = try await first.firstRunOnboardingRepository
            .state()
        XCTAssertEqual(interruptedState?.discoveryResetPhase, .required)
        do {
            _ = try await onboarding(in: first).complete(
                profileID: nil,
                submission: newKidSubmission
            )
            XCTFail("Create must remain blocked across reset interruption.")
        } catch {
            XCTAssertEqual(
                error as? FirstRunOnboardingRepositoryError,
                .discoveryResetRequired
            )
        }

        let restartedTransport = DiscoveryTransport(
            availability: [.available],
            remoteProfiles: [accountBProfile],
            confirmationChanges: [.switchedAccounts]
        )
        let restarted = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Another Seed"),
            transport: restartedTransport
        )
        let discovered = try await discovery(in: restarted).discoverProfiles()
        let outboundProfileIDs = await restartedTransport.outboundProfileIDs()
        let retainedAccountAProfile = try await restarted.profileRepository.profile(
            id: accountAProfile.id
        )
        let tombstones = try await restarted.tombstoneRepository.tombstones()

        XCTAssertEqual(discovered.map(\.id), [accountBProfile.id])
        XCTAssertNil(retainedAccountAProfile)
        XCTAssertFalse(outboundProfileIDs.contains(accountAProfile.id))
        XCTAssertTrue(tombstones.isEmpty)
    }

    private var referenceDate: Date {
        Date(timeIntervalSince1970: 1_768_464_000)
    }
}

private struct AdoptionClock: AppClock {
    let now: Date
}

private actor RecordingProfileDataEraser: ProfileDataErasing {
    private let base: any ProfileDataErasing
    private var profileIDs: [ProfileID] = []

    init(base: any ProfileDataErasing) {
        self.base = base
    }

    func eraseProfileData(for profileID: ProfileID) async throws {
        profileIDs.append(profileID)
        try await base.eraseProfileData(for: profileID)
    }

    func eraseUnadoptedProfileData(for profileID: ProfileID) async throws {
        profileIDs.append(profileID)
        try await base.eraseUnadoptedProfileData(for: profileID)
    }

    func erasedProfileIDs() -> [ProfileID] {
        profileIDs
    }
}

private actor FailingBeforeProfileDeleteEraser: ProfileDataErasing {
    private let base: any ProfileDataErasing
    private let wordPoolRepository: any WordPoolRepository
    private var hasFailed = false

    init(
        base: any ProfileDataErasing,
        wordPoolRepository: any WordPoolRepository
    ) {
        self.base = base
        self.wordPoolRepository = wordPoolRepository
    }

    func eraseProfileData(for profileID: ProfileID) async throws {
        try await base.eraseProfileData(for: profileID)
    }

    func eraseUnadoptedProfileData(for profileID: ProfileID) async throws {
        guard !hasFailed else {
            return try await base.eraseUnadoptedProfileData(for: profileID)
        }
        hasFailed = true
        try await wordPoolRepository.deleteAll(for: profileID)
        throw CreationInterruption.injected
    }
}

private actor AdoptionVoiceprintRepository:
    DeviceVoiceprintRepository,
    FreshInstallationVoiceprintResetting
{
    private var templates: [ProfileID: DeviceVoiceprintTemplate] = [:]

    func template(
        for profileID: ProfileID
    ) async throws -> DeviceVoiceprintTemplate? {
        templates[profileID]
    }

    func save(_ template: DeviceVoiceprintTemplate) async throws {
        templates[template.profileID] = template
    }

    func delete(for profileID: ProfileID) async throws {
        templates[profileID] = nil
    }

    func resetVoiceprintsForFreshInstallation() async throws {
        templates.removeAll()
    }
}

private final class RecordingAdoptionHandwritingRemover:
    HandwritingPreferenceRemoving,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var profileIDs: [ProfileID] = []

    func remove(for profileID: ProfileID) {
        lock.lock()
        profileIDs.append(profileID)
        lock.unlock()
    }

    func removedProfileIDs() -> [ProfileID] {
        lock.lock()
        defer { lock.unlock() }
        return profileIDs
    }
}

private enum CreationInterruption: Error {
    case injected
}

private actor FailingOnceProfilesReadKidProfileRepository:
    KidProfileRepository
{
    private let base: any KidProfileRepository
    private var shouldFailProfilesRead = true

    init(base: any KidProfileRepository) {
        self.base = base
    }

    func profiles() async throws -> [KidProfile] {
        if shouldFailProfilesRead {
            shouldFailProfilesRead = false
            throw CreationInterruption.injected
        }
        return try await base.profiles()
    }

    func profile(id: ProfileID) async throws -> KidProfile? {
        try await base.profile(id: id)
    }

    func save(_ profile: KidProfile) async throws {
        try await base.save(profile)
    }

    func delete(id: ProfileID) async throws {
        try await base.delete(id: id)
    }
}

private actor FailingOnceKidProfileRepository: KidProfileRepository {
    private var profilesByID: [ProfileID: KidProfile]
    private var shouldFailSave = true

    init(seed: [KidProfile]) {
        profilesByID = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
    }

    func profiles() async throws -> [KidProfile] {
        profilesByID.values.sorted { $0.id.description < $1.id.description }
    }

    func profile(id: ProfileID) async throws -> KidProfile? {
        profilesByID[id]
    }

    func save(_ profile: KidProfile) async throws {
        if shouldFailSave {
            shouldFailSave = false
            throw CreationInterruption.injected
        }
        profilesByID[profile.id] = profile
    }

    func delete(id: ProfileID) async throws {
        profilesByID[id] = nil
    }
}

private actor FailingOncePracticeSettingsRepository:
    PracticeSettingsRepository
{
    private var settingsByProfileID: [ProfileID: ProfilePracticeSettings] = [:]
    private var shouldFailSave = true

    func settings(
        for profileID: ProfileID
    ) async throws -> ProfilePracticeSettings? {
        settingsByProfileID[profileID]
    }

    func save(_ settings: ProfilePracticeSettings) async throws {
        if shouldFailSave {
            shouldFailSave = false
            throw CreationInterruption.injected
        }
        settingsByProfileID[settings.profileID] = settings
    }

    func delete(for profileID: ProfileID) async throws {
        settingsByProfileID[profileID] = nil
    }
}

private actor FailingOnceChildSessionRepository: ChildSessionRepository {
    private var selectedProfileID: ProfileID?
    private var shouldFailSave = true

    func lastSelectedProfileID() async throws -> ProfileID? {
        selectedProfileID
    }

    func saveLastSelectedProfileID(_ profileID: ProfileID) async throws {
        if shouldFailSave {
            shouldFailSave = false
            throw CreationInterruption.injected
        }
        selectedProfileID = profileID
    }

    func clearLastSelectedProfileID() async throws {
        selectedProfileID = nil
    }
}

private actor FailingOnceOnboardingRepository: FirstRunOnboardingPersisting {
    enum Failure {
        case rearm
        case beginCreation
        case completion
        case blockedCompletion
    }

    private let base: LocalFirstRunOnboardingRepository
    private let failure: Failure
    private var hasFailed = false
    private var completionDidBlock = false
    private var completionBlockWaiters: [CheckedContinuation<Void, Never>] = []
    private var completionReleaseContinuation: CheckedContinuation<Void, Never>?

    init(
        base: LocalFirstRunOnboardingRepository,
        failure: Failure
    ) {
        self.base = base
        self.failure = failure
    }

    func markDiscoveryIntent() async throws {
        try await base.markDiscoveryIntent()
    }

    func prepareForProfileDiscovery() async throws -> ProfileID? {
        try await base.prepareForProfileDiscovery()
    }

    func canDiscardUnadoptedDiscoveryState() async throws -> Bool {
        try await base.canDiscardUnadoptedDiscoveryState()
    }

    func rearmPendingDiscoveryReset() async throws -> Bool {
        if failure == .rearm, !hasFailed {
            hasFailed = true
            throw CreationInterruption.injected
        }
        return try await base.rearmPendingDiscoveryReset()
    }

    func hasPendingDiscoveryIntent() async throws -> Bool {
        try await base.hasPendingDiscoveryIntent()
    }

    func waitUntilCompletionIsBlocked() async {
        guard !completionDidBlock else { return }
        await withCheckedContinuation { continuation in
            completionBlockWaiters.append(continuation)
        }
    }

    func releaseBlockedCompletion() {
        completionReleaseContinuation?.resume()
        completionReleaseContinuation = nil
    }

    func finishDiscoveryReset() async throws {
        try await base.finishDiscoveryReset()
    }

    func beginAccountBoundDiscovery() async throws {
        try await base.beginAccountBoundDiscovery()
    }

    func finishProfileDiscovery() async throws {
        try await base.finishProfileDiscovery()
    }

    func requireProfileCreationAllowed() async throws {
        try await base.requireProfileCreationAllowed()
    }

    func requireDiscoveryResetCompleted() async throws {
        try await base.requireDiscoveryResetCompleted()
    }

    func finishPendingProfileContainment(
        profileID: ProfileID
    ) async throws {
        try await base.finishPendingProfileContainment(profileID: profileID)
    }

    func beginProfileCreation(
        proposedProfileID: ProfileID?,
        startedAt: Date
    ) async throws -> ProfileID {
        if failure == .beginCreation, !hasFailed {
            hasFailed = true
            throw CreationInterruption.injected
        }
        return try await base.beginProfileCreation(
            proposedProfileID: proposedProfileID,
            startedAt: startedAt
        )
    }

    func markCompleted(
        profileID: ProfileID,
        completedAt: Date,
        consentVersion: Int?,
        admissionGate: FirstRunDiscoveryAdmissionGate,
        admissionLease: FirstRunDiscoveryAdmissionGate.Generation
    ) async throws {
        if failure == .blockedCompletion, !hasFailed {
            hasFailed = true
            completionDidBlock = true
            let waiters = completionBlockWaiters
            completionBlockWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            await withCheckedContinuation { continuation in
                completionReleaseContinuation = continuation
            }
        }
        if failure == .completion, !hasFailed {
            hasFailed = true
            throw CreationInterruption.injected
        }
        try await base.markCompleted(
            profileID: profileID,
            completedAt: completedAt,
            consentVersion: consentVersion,
            admissionGate: admissionGate,
            admissionLease: admissionLease
        )
    }
}

private func assertThrowsErrorAsync<T>(
    _ expression: () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error to be thrown.", file: file, line: line)
    } catch {}
}

private actor DiscoveryTransport: FamilySyncTransport {
    nonisolated let capability = FamilySyncCapability.iCloud
    nonisolated let initialProfilePolicy =
        FamilySyncInitialProfilePolicy.discoverBeforeCreating

    private var availabilityValues: [FamilySyncAvailability]
    private var server: DiscoveryRemoteServer
    private let switchedServer: DiscoveryRemoteServer?
    private var confirmationFailuresRemaining: Int
    private var fetchFailuresRemaining: Int
    private var confirmationChanges: [FamilySyncAccountChange?]
    private var confirmationCalls = 0
    private var fetchCalls = 0
    private var suspensionCalls = 0
    private var pushedProfiles: [ProfileID] = []
    private var outboundOperations: [FamilySyncPendingOperation] = []

    init(
        availability: [FamilySyncAvailability],
        remoteProfiles: [KidProfile],
        confirmationFailures: Int = 0,
        switchedRemoteProfiles: [KidProfile]? = nil,
        confirmationChanges: [FamilySyncAccountChange?] = [],
        fetchFailures: Int = 0
    ) {
        self.init(
            availability: availability,
            server: DiscoveryRemoteServer(profiles: remoteProfiles),
            confirmationFailures: confirmationFailures,
            switchedServer: switchedRemoteProfiles.map(
                DiscoveryRemoteServer.init(profiles:)
            ),
            confirmationChanges: confirmationChanges,
            fetchFailures: fetchFailures
        )
    }

    init(
        availability: [FamilySyncAvailability],
        server: DiscoveryRemoteServer,
        confirmationFailures: Int = 0,
        switchedServer: DiscoveryRemoteServer? = nil,
        confirmationChanges: [FamilySyncAccountChange?] = [],
        fetchFailures: Int = 0
    ) {
        precondition(!availability.isEmpty)
        availabilityValues = availability
        self.server = server
        self.switchedServer = switchedServer
        confirmationFailuresRemaining = confirmationFailures
        fetchFailuresRemaining = fetchFailures
        self.confirmationChanges = confirmationChanges
    }

    func availability() async -> FamilySyncAvailability {
        guard availabilityValues.count > 1 else {
            return availabilityValues[0]
        }
        return availabilityValues.removeFirst()
    }

    func prepareProfileZone(_ profileID: ProfileID) async throws {
        _ = profileID
    }

    func fetchRecords(
        for profileID: ProfileID
    ) async throws -> [FamilySyncRecord] {
        await server.records(for: profileID)
    }

    func fetchChanges(
        for profileIDs: [ProfileID]
    ) async throws -> FamilySyncTransportResult {
        _ = profileIDs
        fetchCalls += 1
        if fetchFailuresRemaining > 0 {
            fetchFailuresRemaining -= 1
            throw DiscoveryTransportFailure.fetch
        }
        return await server.fetchChanges()
    }

    func push(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        _ = records
        pushedProfiles.append(profileID)
    }

    func sendChanges(
        _ changes: [FamilySyncPendingOperation]
    ) async throws -> FamilySyncTransportResult {
        outboundOperations += changes
        var acknowledged: Set<FamilySyncChangeAcknowledgement> = []
        var failures: [FamilySyncTransportFailure] = []
        for operation in changes {
            switch operation {
            case .save(let record):
                pushedProfiles.append(record.profileID)
                acknowledged.insert(
                    FamilySyncChangeAcknowledgement(operation: operation)
                )
            case .delete(let key, _):
                failures.append(
                    FamilySyncTransportFailure(
                        key: key,
                        category: .unknown
                    )
                )
            }
        }
        return FamilySyncTransportResult(
            acknowledged: acknowledged,
            failures: failures
        )
    }

    func acknowledgeFetchedChanges(receiptIDs: Set<UUID>) async throws {
        await server.acknowledge(receiptIDs)
    }

    func confirmCurrentAccount() async throws -> FamilySyncAccountChange? {
        confirmationCalls += 1
        if confirmationFailuresRemaining > 0 {
            confirmationFailuresRemaining -= 1
            throw DiscoveryTransportFailure.accountConfirmation
        }
        let change =
            confirmationChanges.isEmpty
            ? nil
            : confirmationChanges.removeFirst()
        if change == .switchedAccounts, let switchedServer {
            server = switchedServer
        }
        await server.resetAcknowledgements()
        return change
    }

    func confirmationCallCount() -> Int {
        confirmationCalls
    }

    func fetchCallCount() -> Int {
        fetchCalls
    }

    func suspend() async {
        suspensionCalls += 1
    }

    func suspensionCallCount() -> Int {
        suspensionCalls
    }

    func pushedProfileIDs() -> [ProfileID] {
        pushedProfiles
    }

    func outboundProfileIDs() -> Set<ProfileID> {
        Set(outboundOperations.map(\.key.profileID))
    }

    func outboundDescriptions() -> [String] {
        outboundOperations.map { operation in
            switch operation {
            case .save(let record):
                return "save:\(record.kind.rawValue):\(record.recordName)"
            case .delete(let key, _):
                return "delete:\(key.recordName)"
            }
        }
    }

    func resetOutboundObservations() {
        pushedProfiles.removeAll()
        outboundOperations.removeAll()
    }

    func setFetchFailures(_ count: Int) {
        fetchFailuresRemaining = count
    }

    func setAvailability(_ values: [FamilySyncAvailability]) {
        precondition(!values.isEmpty)
        availabilityValues = values
    }

    func createShare(for profileID: ProfileID) async throws -> URL {
        _ = profileID
        return URL(string: "https://example.invalid/family")!
    }

    func acceptShare(at url: URL) async throws -> ProfileID {
        _ = url
        return ProfileID()
    }

    fileprivate nonisolated static func record(
        for profile: KidProfile
    ) -> FamilySyncRecord {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        let payload = try! encoder.encode(FamilySyncProfilePayload(profile: profile))
        return FamilySyncRecord(
            recordName: "profile-\(profile.id)",
            profileID: profile.id,
            kind: .profile,
            payload: payload,
            updatedAt: profile.updatedAt,
            deviceID: "remote-family-device",
            logicalRevision: FamilySyncLogicalRevision(
                counter: 10,
                deviceID: "remote-family-device"
            )
        )
    }
}

private enum DiscoveryTransportFailure: Error {
    case accountConfirmation
    case fetch
}

private struct DiscoveryRemoteEntry: Sendable {
    let record: FamilySyncRecord
    let receipt: FamilySyncFetchedReceipt
}

private actor DiscoveryRemoteServer {
    private let entries: [DiscoveryRemoteEntry]
    private var acknowledgedReceiptIDs: Set<UUID> = []

    init(profiles: [KidProfile]) {
        entries = profiles.enumerated().map { index, profile in
            let record = DiscoveryTransport.record(for: profile)
            return DiscoveryRemoteEntry(
                record: record,
                receipt: FamilySyncFetchedReceipt(
                    id: Self.receiptID(index: index, profileID: profile.id),
                    key: FamilySyncChangeKey(
                        profileID: record.profileID,
                        recordName: record.recordName
                    ),
                    operation: .save,
                    revision: record.logicalRevision
                )
            )
        }
    }

    func records(for profileID: ProfileID) -> [FamilySyncRecord] {
        entries.map(\.record).filter { $0.profileID == profileID }
    }

    func fetchChanges() -> FamilySyncTransportResult {
        let pending = entries.filter {
            !acknowledgedReceiptIDs.contains($0.receipt.id)
        }
        return FamilySyncTransportResult(
            records: pending.map(\.record),
            receipts: pending.map(\.receipt)
        )
    }

    func acknowledge(_ receiptIDs: Set<UUID>) {
        acknowledgedReceiptIDs.formUnion(receiptIDs)
    }

    func resetAcknowledgements() {
        acknowledgedReceiptIDs.removeAll()
    }

    private nonisolated static func receiptID(
        index: Int,
        profileID: ProfileID
    ) -> UUID {
        var bytes = Array(profileID.rawValue.uuidString.utf8)
        bytes.append(UInt8(index & 0xFF))
        let checksum = FamilySyncRecord.checksum(for: Data(bytes))
        let hex = String(checksum.prefix(32))
        let value =
            "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-4\(hex.dropFirst(13).prefix(3))-a\(hex.dropFirst(17).prefix(3))-\(hex.dropFirst(20).prefix(12))"
        return UUID(uuidString: value) ?? UUID()
    }
}
