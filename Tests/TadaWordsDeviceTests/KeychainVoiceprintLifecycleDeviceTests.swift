import Security
import TadaWordsApplePlatform
import TadaWordsDomain
import XCTest

/// Physical-device coverage for the production Keychain repository.
///
/// The test uses UUID-scoped service names, never the production
/// `com.tadawords.device-voiceprints` service. It models the reinstall boundary
/// by constructing a new repository while leaving the Keychain item intact,
/// then invokes the same scoped reset used by production bootstrap.
final class KeychainVoiceprintLifecycleDeviceTests: XCTestCase {
    func testRetainedItemsSurviveRepositoryRecreationUntilFreshInstallReset()
        async throws
    {
        #if targetEnvironment(simulator)
            throw XCTSkip("Run TadaWordsDeviceTests on a physical iPhone or iPad.")
        #endif

        let service = testService(suffix: "retained")
        let neighboringService = testService(suffix: "neighbor")
        defer {
            deleteAllItems(service: service)
            deleteAllItems(service: neighboringService)
        }

        let firstProfile = ProfileID()
        let secondProfile = ProfileID()
        let neighboringProfile = ProfileID()
        let firstTemplate = try makeTemplate(for: firstProfile, marker: 1)
        let secondTemplate = try makeTemplate(for: secondProfile, marker: 2)
        let neighboringTemplate = try makeTemplate(
            for: neighboringProfile,
            marker: 3
        )

        let beforeRemoval = KeychainDeviceVoiceprintRepository(service: service)
        try await beforeRemoval.save(firstTemplate)
        try await beforeRemoval.save(secondTemplate)
        try await KeychainDeviceVoiceprintRepository(
            service: neighboringService
        ).save(neighboringTemplate)

        // A new repository instance models the app process after the container
        // has been removed and recreated while the OS-level Keychain item
        // remains available.
        let afterReinstall = KeychainDeviceVoiceprintRepository(service: service)
        let retainedFirst = try await afterReinstall.template(for: firstProfile)
        let retainedSecond = try await afterReinstall.template(for: secondProfile)
        XCTAssertEqual(retainedFirst, firstTemplate)
        XCTAssertEqual(retainedSecond, secondTemplate)
        try assertThisDeviceOnlyAndNonSynchronizing(
            service: service,
            profileID: firstProfile
        )

        try await afterReinstall.resetVoiceprintsForFreshInstallation()

        let resetFirst = try await afterReinstall.template(for: firstProfile)
        let resetSecond = try await afterReinstall.template(for: secondProfile)
        let retainedNeighbor = try await KeychainDeviceVoiceprintRepository(
            service: neighboringService
        ).template(for: neighboringProfile)
        XCTAssertNil(resetFirst)
        XCTAssertNil(resetSecond)
        XCTAssertEqual(
            retainedNeighbor,
            neighboringTemplate,
            "The fresh-install reset must not delete another Keychain service."
        )
    }

    func testScopedFreshInstallResetIsIdempotentOnAnEmptyService() async throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("Run TadaWordsDeviceTests on a physical iPhone or iPad.")
        #endif

        let service = testService(suffix: "empty")
        defer { deleteAllItems(service: service) }

        let repository = KeychainDeviceVoiceprintRepository(service: service)
        try await repository.resetVoiceprintsForFreshInstallation()
        try await repository.resetVoiceprintsForFreshInstallation()
    }

    private func makeTemplate(
        for profileID: ProfileID,
        marker: Float
    ) throws -> DeviceVoiceprintTemplate {
        DeviceVoiceprintTemplate(
            profileID: profileID,
            embedding: try VoiceprintEmbedding(
                modelIdentifier: "signed-device-lifecycle-proof",
                vector: [marker, marker + 0.5]
            ),
            acceptedSegmentCount: 6,
            acceptedSpeechDuration: ElapsedTime(seconds: 20),
            enrolledAt: Date(timeIntervalSince1970: 2_100_000_000)
        )
    }

    private func testService(suffix: String) -> String {
        "com.tadawords.device-voiceprints.device-proof."
            + "\(suffix).\(UUID().uuidString)"
    }

    private func deleteAllItems(service: String) {
        SecItemDelete(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            ] as CFDictionary
        )
    }

    private func assertThisDeviceOnlyAndNonSynchronizing(
        service: String,
        profileID: ProfileID
    ) throws {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: profileID.rawValue.uuidString,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
                kSecReturnAttributes as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ] as CFDictionary,
            &item
        )
        XCTAssertEqual(status, errSecSuccess)
        let attributes = try XCTUnwrap(item as? [String: Any])
        XCTAssertEqual(
            attributes[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
        XCTAssertEqual(
            attributes[kSecAttrSynchronizable as String] as? Bool,
            false
        )
    }
}
