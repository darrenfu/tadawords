import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class PracticeSettingsSyncGroupsTests: XCTestCase {
    func testEachGroupHasAStableIndependentRecordName() {
        let profileID = ProfileID(
            rawValue: UUID(uuidString: "10101010-2020-3030-4040-505050505050")!
        )

        let names = PracticeSettingsSyncGroup.allCases.map {
            $0.recordName(for: profileID)
        }

        XCTAssertEqual(Set(names).count, PracticeSettingsSyncGroup.allCases.count)
        XCTAssertTrue(names.allSatisfy { $0.contains(profileID.description) })
    }

    func testApplyingEveryPermutationPreservesUnrelatedGroups() throws {
        let profileID = ProfileID()
        let baseline = ProfilePracticeSettings.defaults(for: profileID)
        let changed = distinctSettings(profileID: profileID)

        for groups in permutations(of: PracticeSettingsSyncGroup.allCases) {
            let result = try groups.reduce(baseline) { current, group in
                try PracticeSettingsSyncPayload(
                    settings: changed,
                    group: group
                ).applying(to: current)
            }
            XCTAssertEqual(result, changed)
        }
    }

    func testPayloadRoundTripsWithInspectableJSON() throws {
        let settings = distinctSettings(profileID: ProfileID())

        for group in PracticeSettingsSyncGroup.allCases {
            let payload = PracticeSettingsSyncPayload(
                settings: settings,
                group: group
            )
            let data = try JSONEncoder().encode(payload)
            let decoded = try JSONDecoder().decode(
                PracticeSettingsSyncPayload.self,
                from: data
            )
            XCTAssertEqual(decoded, payload)
            XCTAssertEqual(decoded.group, group)
        }
    }

    func testPayloadRejectsCrossProfileApply() throws {
        let source = distinctSettings(profileID: ProfileID())
        let destination = ProfilePracticeSettings.defaults(for: ProfileID())
        let payload = PracticeSettingsSyncPayload(
            settings: source,
            group: .audio
        )

        XCTAssertThrowsError(try payload.applying(to: destination)) { error in
            XCTAssertEqual(
                error as? PracticeSettingsSyncPayloadError,
                .profileMismatch
            )
        }
    }

    private func distinctSettings(
        profileID: ProfileID
    ) -> ProfilePracticeSettings {
        ProfilePracticeSettings(
            profileID: profileID,
            read: LearningRouteSettings(
                newWordLimit: 2,
                reviewWordLimit: 3,
                contentOrder: .reviewThenNew,
                emergencyAfterSeconds: 121,
                incorrectAttemptLimit: 1
            ),
            write: LearningRouteSettings(
                newWordLimit: 7,
                reviewWordLimit: 8,
                contentOrder: .newThenReview,
                emergencyAfterSeconds: 321,
                incorrectAttemptLimit: 5
            ),
            audio: AudioPreferences(
                voiceEnabled: false,
                musicEnabled: false,
                soundEffectsEnabled: true,
                reducedSoundEnabled: true,
                calmEmergencyEnabled: false
            ),
            notifications: LearningNotificationPreferences(
                dailyReminderEnabled: true,
                weeklySummaryEnabled: true
            ),
            interface: PracticeInterfacePreferences(
                leftHandedLayoutEnabled: true,
                selectedHandwritingTool: .brush
            ),
            wordRecommendationMode: .manualOnly
        )
    }

    private func permutations<Element>(of values: [Element]) -> [[Element]] {
        guard let first = values.first else { return [[]] }
        return permutations(of: Array(values.dropFirst())).flatMap { suffix in
            (0...suffix.count).map { index in
                var result = suffix
                result.insert(first, at: index)
                return result
            }
        }
    }
}
