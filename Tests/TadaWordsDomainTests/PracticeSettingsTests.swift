import Foundation
import TadaWordsDomain
import XCTest

final class PracticeSettingsTests: XCTestCase {
    func testLegacyProfileSettingsDefaultNotificationsToDisabled() throws {
        let profileID = ProfileID()
        let encoded = try JSONEncoder().encode(
            ProfilePracticeSettings(profileID: profileID)
        )
        var legacy = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacy.removeValue(forKey: "notifications")

        let settings = try JSONDecoder().decode(
            ProfilePracticeSettings.self,
            from: try JSONSerialization.data(withJSONObject: legacy)
        )

        XCTAssertEqual(settings.notifications, .disabled)
    }

    func testAudioPreferencesRoundTripAndLegacySettingsDefaultSafely() throws {
        let profileID = ProfileID()
        let settings = ProfilePracticeSettings(
            profileID: profileID,
            audio: AudioPreferences(
                voiceEnabled: false,
                musicEnabled: true,
                soundEffectsEnabled: false,
                reducedSoundEnabled: true,
                calmEmergencyEnabled: true
            )
        )

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(
            ProfilePracticeSettings.self,
            from: encoded
        )
        XCTAssertEqual(decoded.audio, settings.audio)

        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "audio")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacy = try JSONDecoder().decode(
            ProfilePracticeSettings.self,
            from: legacyData
        )
        XCTAssertEqual(legacy.audio, .default)
    }
    func testDefaultsMapExactlyToReadAndWriteConfigurations() {
        let settings = ProfilePracticeSettings.defaults(for: Self.profileID)

        XCTAssertEqual(settings.read, .defaultRead)
        XCTAssertEqual(settings.write, .defaultWrite)
        XCTAssertEqual(
            settings.configuration(for: .read),
            PracticeModeConfiguration(
                questConfiguration: .defaultRead,
                emergencyAfterSeconds: 180
            )
        )
        XCTAssertEqual(
            settings.configuration(for: .write),
            PracticeModeConfiguration(
                questConfiguration: .defaultWrite,
                emergencyAfterSeconds: 300
            )
        )
    }

    func testCustomRoutesMapLimitsOrderBudgetAndThresholdByMode() {
        let read = LearningRouteSettings(
            newWordLimit: 7,
            reviewWordLimit: 4,
            contentOrder: .reviewThenNew,
            emergencyAfterSeconds: 90
        )
        let write = LearningRouteSettings(
            newWordLimit: 2,
            reviewWordLimit: 8,
            contentOrder: .newThenReview,
            emergencyAfterSeconds: 420
        )
        let settings = ProfilePracticeSettings(
            profileID: Self.profileID,
            read: read,
            write: write
        )

        XCTAssertEqual(settings.route(for: .read), read)
        XCTAssertEqual(
            settings.configuration(for: .read),
            PracticeModeConfiguration(
                questConfiguration: QuestConfiguration(
                    learningMode: .read,
                    newWordLimit: 7,
                    reviewWordLimit: 4,
                    attentionBudget: 11,
                    contentOrder: .reviewThenNew
                ),
                emergencyAfterSeconds: 90
            )
        )
        XCTAssertEqual(settings.route(for: .write), write)
        XCTAssertEqual(
            settings.configuration(for: .write),
            PracticeModeConfiguration(
                questConfiguration: QuestConfiguration(
                    learningMode: .write,
                    newWordLimit: 2,
                    reviewWordLimit: 8,
                    attentionBudget: 10,
                    contentOrder: .newThenReview
                ),
                emergencyAfterSeconds: 420
            )
        )
    }

    func testInitializationAndDecodingClampUnsafeValues() throws {
        XCTAssertEqual(LearningRouteSettings.wordLimitRange, 0...20)
        XCTAssertEqual(
            LearningRouteSettings.emergencyAfterSecondsRange,
            60...3_600
        )

        let initialized = LearningRouteSettings(
            newWordLimit: -5,
            reviewWordLimit: -2,
            contentOrder: .reviewThenNew,
            emergencyAfterSeconds: -60
        )
        XCTAssertEqual(initialized.newWordLimit, 0)
        XCTAssertEqual(initialized.reviewWordLimit, 0)
        XCTAssertEqual(initialized.emergencyAfterSeconds, 60)

        let invalidJSON = Data(
            """
            {
              "newWordLimit": -10,
              "reviewWordLimit": -20,
              "contentOrder": "newThenReview",
              "emergencyAfterSeconds": -30
            }
            """.utf8
        )
        let decoded = try JSONDecoder().decode(
            LearningRouteSettings.self,
            from: invalidJSON
        )
        XCTAssertEqual(
            decoded,
            LearningRouteSettings(
                newWordLimit: 0,
                reviewWordLimit: 0,
                contentOrder: .newThenReview,
                emergencyAfterSeconds: 60
            )
        )

        let saturated = LearningRouteSettings(
            newWordLimit: Int.max,
            reviewWordLimit: Int.max,
            contentOrder: .newThenReview,
            emergencyAfterSeconds: Int.max
        )
        let configuration = ProfilePracticeSettings(
            profileID: Self.profileID,
            read: saturated
        ).configuration(for: .read)
        XCTAssertEqual(saturated.newWordLimit, 20)
        XCTAssertEqual(saturated.reviewWordLimit, 20)
        XCTAssertEqual(saturated.emergencyAfterSeconds, 3_600)
        XCTAssertEqual(configuration.questConfiguration.attentionBudget, 40)
        XCTAssertEqual(configuration.emergencyAfterSeconds, 3_600)
    }

    func testProfileSettingsCodableRoundTripPreservesIdentityAndRoutes()
        throws
    {
        let settings = ProfilePracticeSettings(
            profileID: Self.profileID,
            read: LearningRouteSettings(
                newWordLimit: 6,
                reviewWordLimit: 9,
                contentOrder: .reviewThenNew,
                emergencyAfterSeconds: 240
            )
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(
            ProfilePracticeSettings.self,
            from: data
        )

        XCTAssertEqual(decoded, settings)
    }

    private static let profileID = ProfileID(
        rawValue: UUID(uuidString: "91000000-0000-0000-0000-000000000001")!
    )
}
