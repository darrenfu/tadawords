import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

@MainActor
final class AudioExperienceIntegrationTests: XCTestCase {
    func testRememberedProfileDoesNotActivateAmbientAudioBeforeChildTaps() async {
        let profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .pawsAndPines,
            createdAt: Date(timeIntervalSince1970: 1_735_689_600)
        )
        let audio = AudioExperienceSpy()
        let model = TadaWordsAppModel(
            profiles: [profile],
            audioExperienceService: audio,
            initialProfileID: profile.id
        )

        for _ in 0..<20 { await Task.yield() }

        let activationBeforeTap = await audio.latestActivation()
        XCTAssertNil(model.selectedProfile)
        XCTAssertEqual(model.lastPlayedProfileID, profile.id)
        XCTAssertNil(activationBeforeTap)

        model.selectProfile(profile)
        await waitForAudioActivation(audio)
        let activationAfterTap = await audio.latestActivation()
        XCTAssertEqual(activationAfterTap?.world, .pawsAndPines)
    }

    func testSelectingProfileAppliesItsPersistedWorldAndAudioPreferences() async throws {
        let profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .pawsAndPines,
            createdAt: Date(timeIntervalSince1970: 1_735_689_600)
        )
        let preferences = AudioPreferences(
            voiceEnabled: false,
            musicEnabled: true,
            soundEffectsEnabled: false
        )
        let repository = InMemoryPracticeSettingsRepository()
        try await repository.save(
            ProfilePracticeSettings(
                profileID: profile.id,
                audio: preferences
            )
        )
        let audio = AudioExperienceSpy()
        let model = TadaWordsAppModel(
            profiles: [profile],
            audioExperienceService: audio,
            practiceSettingsRepository: repository
        )

        model.selectProfile(profile)

        await waitForAudioActivation(audio)
        let activation = await audio.latestActivation()
        XCTAssertEqual(activation?.world, .pawsAndPines)
        XCTAssertEqual(activation?.preferences, preferences)
    }

    func testLeavingChildWorldStopsAmbientAudio() async {
        let audio = AudioExperienceSpy()
        let model = TadaWordsAppModel(audioExperienceService: audio)

        model.showProfiles()

        for _ in 0..<20 {
            if await audio.stopCount() > 0 { break }
            await Task.yield()
        }
        let stopCount = await audio.stopCount()
        XCTAssertEqual(stopCount, 1)
    }

    func testDuplicateScenePhaseDoesNotRestartAudioExperience() async {
        let audio = AudioExperienceSpy()
        let model = TadaWordsAppModel(audioExperienceService: audio)

        model.setApplicationActive(true)
        model.setApplicationActive(false)
        model.setApplicationActive(false)
        model.setApplicationActive(true)
        model.setApplicationActive(true)

        for _ in 0..<40 {
            if await audio.applicationStates().count == 2 { break }
            await Task.yield()
        }
        let states = await audio.applicationStates()
        XCTAssertEqual(states, [false, true])
    }

    private func waitForAudioActivation(_ audio: AudioExperienceSpy) async {
        for _ in 0..<40 {
            if await audio.latestActivation() != nil { return }
            await Task.yield()
        }
    }
}

private actor AudioExperienceSpy: AudioExperienceService {
    struct Activation: Sendable {
        let world: WorldTheme
        let preferences: AudioPreferences
    }

    private var activation: Activation?
    private var ambientStopCount = 0
    private var receivedApplicationStates: [Bool] = []

    func latestActivation() -> Activation? { activation }
    func stopCount() -> Int { ambientStopCount }
    func applicationStates() -> [Bool] { receivedApplicationStates }

    func playLaunchSignature() async {}

    func activate(world: WorldTheme, preferences: AudioPreferences) async {
        activation = Activation(world: world, preferences: preferences)
    }

    func stopAmbientAudio() async {
        ambientStopCount += 1
    }

    func play(_ cue: FunctionalAudioCue) async { _ = cue }
    func prepareForVoicePrompt() async -> Bool { true }
    func finishVoicePrompt() async {}
    func prepareForRecording() async {}
    func finishRecording() async {}
    func setApplicationActive(_ isActive: Bool) async {
        receivedApplicationStates.append(isActive)
    }
}
