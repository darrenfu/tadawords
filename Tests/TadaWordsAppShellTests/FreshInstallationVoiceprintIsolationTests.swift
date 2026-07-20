import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

@testable import TadaWordsAppShell

@MainActor
final class FreshInstallationVoiceprintIsolationTests: XCTestCase {
    func testFreshInstallPurgesRetainedKeychainLikeTemplateBeforeSeeding()
        async throws
    {
        let supportDirectory = try temporarySupportDirectory()
        defer { try? FileManager.default.removeItem(at: supportDirectory) }
        let profile = makeProfile()
        let retainedRepository = RetainedVoiceprintRepository()
        try await retainedRepository.save(makeTemplate(for: profile.id))

        let environment = try await bootstrap(
            supportDirectory: supportDirectory,
            profile: profile,
            voiceprints: retainedRepository
        )

        let resetCount = await retainedRepository.resetCount()
        let retainedTemplate = try await retainedRepository.template(for: profile.id)
        XCTAssertEqual(resetCount, 1)
        XCTAssertNil(retainedTemplate)
        XCTAssertEqual(environment.profiles, [profile])
    }

    func testExistingInstallPreservesDeviceVoiceprintAcrossBootstrap() async throws {
        let supportDirectory = try temporarySupportDirectory()
        defer { try? FileManager.default.removeItem(at: supportDirectory) }
        let profile = makeProfile()
        let retainedRepository = RetainedVoiceprintRepository()

        _ = try await bootstrap(
            supportDirectory: supportDirectory,
            profile: profile,
            voiceprints: retainedRepository
        )
        let enrolledTemplate = try makeTemplate(for: profile.id)
        try await retainedRepository.save(enrolledTemplate)
        await retainedRepository.rejectReset()

        _ = try await bootstrap(
            supportDirectory: supportDirectory,
            profile: profile,
            voiceprints: retainedRepository
        )

        let resetCount = await retainedRepository.resetCount()
        let retainedTemplate = try await retainedRepository.template(for: profile.id)
        XCTAssertEqual(resetCount, 1)
        XCTAssertEqual(retainedTemplate, enrolledTemplate)
    }

    func testFreshInstallFailsClosedWhenRepositoryCannotReset() async throws {
        let supportDirectory = try temporarySupportDirectory()
        defer { try? FileManager.default.removeItem(at: supportDirectory) }
        let profile = makeProfile()
        let retainedRepository = NonResettingVoiceprintRepository()
        try await retainedRepository.save(makeTemplate(for: profile.id))
        let mutationGate = ProfileScopedMutationGate()
        let gatedVoiceprints = ProfileMutationGatedDeviceVoiceprintRepository(
            base: retainedRepository,
            mutationGate: mutationGate
        )

        do {
            _ = try await ProductionApplicationBootstrapper(
                applicationSupportDirectory: { supportDirectory },
                defaultProfile: profile,
                clock: FreshInstallTestClock(now: testDate),
                timeZone: TimeZone(secondsFromGMT: 0) ?? .current,
                voiceprintRepository: gatedVoiceprints,
                profileMutationGate: mutationGate
            ).bootstrap()
            XCTFail("A repository without a scoped reset must not bootstrap")
        } catch ProfileMutationGatedDeviceVoiceprintRepositoryError
            .freshInstallationResetUnsupported
        {
            // Expected. A production composition must provide the reset capability.
        }

        let dataDirectory = supportDirectory.appendingPathComponent(
            ApplicationDataPaths.dataDirectoryName,
            isDirectory: true
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: dataDirectory.path))
        let retainedTemplate = try await retainedRepository.template(for: profile.id)
        XCTAssertNotNil(retainedTemplate)
    }

    func testFailedFreshInstallResetLeavesNoInitializationMarkerAndRetries()
        async throws
    {
        let supportDirectory = try temporarySupportDirectory()
        defer { try? FileManager.default.removeItem(at: supportDirectory) }
        let profile = makeProfile()
        let retainedRepository = RetainedVoiceprintRepository(shouldFailReset: true)
        try await retainedRepository.save(makeTemplate(for: profile.id))

        do {
            _ = try await bootstrap(
                supportDirectory: supportDirectory,
                profile: profile,
                voiceprints: retainedRepository
            )
            XCTFail("A failed voiceprint reset must fail bootstrap")
        } catch RetainedVoiceprintError.injectedResetFailure {
            // Expected. The absence of the data directory remains the retry marker.
        }

        let dataDirectory = supportDirectory.appendingPathComponent(
            ApplicationDataPaths.dataDirectoryName,
            isDirectory: true
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: dataDirectory.path))
        let templateAfterFailure = try await retainedRepository.template(for: profile.id)
        XCTAssertNotNil(templateAfterFailure)

        await retainedRepository.allowReset()
        _ = try await bootstrap(
            supportDirectory: supportDirectory,
            profile: profile,
            voiceprints: retainedRepository
        )

        let resetCount = await retainedRepository.resetCount()
        let templateAfterRetry = try await retainedRepository.template(for: profile.id)
        XCTAssertEqual(resetCount, 2)
        XCTAssertNil(templateAfterRetry)
    }

    private func bootstrap(
        supportDirectory: URL,
        profile: KidProfile,
        voiceprints: RetainedVoiceprintRepository
    ) async throws -> ProductionApplicationEnvironment {
        let mutationGate = ProfileScopedMutationGate()
        let gatedVoiceprints = ProfileMutationGatedDeviceVoiceprintRepository(
            base: voiceprints,
            mutationGate: mutationGate
        )
        return try await ProductionApplicationBootstrapper(
            applicationSupportDirectory: { supportDirectory },
            defaultProfile: profile,
            clock: FreshInstallTestClock(now: testDate),
            timeZone: TimeZone(secondsFromGMT: 0) ?? .current,
            voiceprintRepository: gatedVoiceprints,
            profileMutationGate: mutationGate
        ).bootstrap()
    }

    private func temporarySupportDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaWordsFreshVoiceprint-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func makeProfile() -> KidProfile {
        KidProfile(
            id: ProfileID(
                rawValue: UUID(
                    uuidString: "79000000-0000-0000-0000-000000000001"
                )!
            ),
            displayName: "Fresh Kid",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: testDate
        )
    }

    private func makeTemplate(
        for profileID: ProfileID
    ) throws -> DeviceVoiceprintTemplate {
        DeviceVoiceprintTemplate(
            profileID: profileID,
            embedding: try VoiceprintEmbedding(
                modelIdentifier: "retained-keychain-fixture",
                vector: [1, 0]
            ),
            acceptedSegmentCount: 6,
            acceptedSpeechDuration: ElapsedTime(seconds: 20),
            enrolledAt: testDate
        )
    }

    private var testDate: Date {
        Date(timeIntervalSince1970: 2_100_000_000)
    }
}

private enum RetainedVoiceprintError: Error {
    case injectedResetFailure
}

private actor RetainedVoiceprintRepository:
    DeviceVoiceprintRepository,
    FreshInstallationVoiceprintResetting
{
    private var templates: [ProfileID: DeviceVoiceprintTemplate] = [:]
    private var freshInstallResetCount = 0
    private var shouldFailReset: Bool

    init(shouldFailReset: Bool = false) {
        self.shouldFailReset = shouldFailReset
    }

    func template(
        for profileID: ProfileID
    ) async throws -> DeviceVoiceprintTemplate? {
        templates[profileID]
    }

    func save(_ template: DeviceVoiceprintTemplate) async throws {
        templates[template.profileID] = template
    }

    func delete(for profileID: ProfileID) async throws {
        templates.removeValue(forKey: profileID)
    }

    func resetVoiceprintsForFreshInstallation() async throws {
        freshInstallResetCount += 1
        guard !shouldFailReset else {
            throw RetainedVoiceprintError.injectedResetFailure
        }
        templates.removeAll()
    }

    func resetCount() -> Int {
        freshInstallResetCount
    }

    func allowReset() {
        shouldFailReset = false
    }

    func rejectReset() {
        shouldFailReset = true
    }
}

private actor NonResettingVoiceprintRepository: DeviceVoiceprintRepository {
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
        templates.removeValue(forKey: profileID)
    }
}

private struct FreshInstallTestClock: AppClock {
    let now: Date
}
