import TadaWordsContent
import TadaWordsDomain
import XCTest

final class ProfileMutationGatedDeviceVoiceprintRepositoryTests: XCTestCase {
    func testQueuedEnrollmentSaveCannotRestoreVoiceprintAfterDeletionSeal()
        async throws
    {
        let profileID = ProfileID()
        let gate = ProfileScopedMutationGate()
        let base = InMemoryVoiceprintRepository()
        let repository = ProfileMutationGatedDeviceVoiceprintRepository(
            base: base,
            mutationGate: gate
        )
        let template = try makeTemplate(profileID: profileID)

        try await gate.acquire(profileID)
        let staleEnrollment = Task {
            try await repository.save(template)
        }
        await Task.yield()

        await gate.seal(profileID)
        await gate.release(profileID)

        do {
            try await staleEnrollment.value
            XCTFail("A sealed Profile must reject a queued voiceprint save")
        } catch let error as ProfileScopedMutationGateError {
            XCTAssertEqual(error, .terminalProfile(profileID))
        }
        let rawTemplate = await base.template(for: profileID)
        let visibleTemplate = try await repository.template(for: profileID)
        XCTAssertNil(rawTemplate)
        XCTAssertNil(visibleTemplate)
    }

    func testDeletionAfterEnrollmentSaveRemovesTemplateBeforeCommit()
        async throws
    {
        let profileID = ProfileID()
        let gate = ProfileScopedMutationGate()
        let base = InMemoryVoiceprintRepository()
        let repository = ProfileMutationGatedDeviceVoiceprintRepository(
            base: base,
            mutationGate: gate
        )

        try await repository.save(try makeTemplate(profileID: profileID))
        try await withProfileScopedMutationLease(
            gate,
            for: profileID,
            allowingTerminal: true,
            isolation: gate
        ) {
            await gate.seal(profileID)
            try await repository.delete(for: profileID)
        }

        let rawTemplate = await base.template(for: profileID)
        let visibleTemplate = try await repository.template(for: profileID)
        XCTAssertNil(rawTemplate)
        XCTAssertNil(visibleTemplate)
    }

    private func makeTemplate(
        profileID: ProfileID
    ) throws -> DeviceVoiceprintTemplate {
        DeviceVoiceprintTemplate(
            profileID: profileID,
            embedding: try VoiceprintEmbedding(
                modelIdentifier: "test-model",
                vector: [1, 0]
            ),
            acceptedSegmentCount: 3,
            acceptedSpeechDuration: ElapsedTime(seconds: 12),
            enrolledAt: Date(timeIntervalSince1970: 2_177_000_000)
        )
    }
}

private actor InMemoryVoiceprintRepository: DeviceVoiceprintRepository {
    private var templates: [ProfileID: DeviceVoiceprintTemplate] = [:]

    func template(
        for profileID: ProfileID
    ) -> DeviceVoiceprintTemplate? {
        templates[profileID]
    }

    func save(_ template: DeviceVoiceprintTemplate) {
        templates[template.profileID] = template
    }

    func delete(for profileID: ProfileID) {
        templates.removeValue(forKey: profileID)
    }
}
