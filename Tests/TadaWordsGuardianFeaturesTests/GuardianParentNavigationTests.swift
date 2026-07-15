import TadaWordsDomain
import XCTest

@testable import TadaWordsGuardianFeatures

final class GuardianParentNavigationTests: XCTestCase {
    @MainActor
    func testHomeHasExactlyThreeTopLevelCategories() {
        XCTAssertEqual(
            GuardianParentSection.allCases,
            [
                .wordsAndPractice,
                .progressAndPerformance,
                .appAndFamily,
            ]
        )
    }

    @MainActor
    func testCategoryRoutesHaveStableDistinctTransitionKeys() {
        let model = makeModel()

        model.showWordsAndPractice()
        XCTAssertEqual(model.transitionKey, "parent-section-wordsAndPractice")

        model.showProgressAndPerformance()
        XCTAssertEqual(model.transitionKey, "parent-section-progressAndPerformance")

        model.showAppAndFamily()
        XCTAssertEqual(model.transitionKey, "parent-section-appAndFamily")
    }

    func testFeaturePagesReturnToTheirOwningCategory() {
        XCTAssertEqual(
            GuardianDestination.quickAdd.parentSectionForBack,
            .wordsAndPractice
        )
        XCTAssertEqual(
            GuardianDestination.presetWords.parentSectionForBack,
            .wordsAndPractice
        )
        XCTAssertEqual(
            GuardianDestination.pool(.write).parentSectionForBack,
            .wordsAndPractice
        )
        XCTAssertEqual(
            GuardianDestination.reports.parentSectionForBack,
            .progressAndPerformance
        )
        XCTAssertEqual(
            GuardianDestination.settings(.practicePlan).parentSectionForBack,
            .wordsAndPractice
        )
        XCTAssertEqual(
            GuardianDestination.settings(.soundAndAccessibility).parentSectionForBack,
            .appAndFamily
        )
        XCTAssertEqual(
            GuardianDestination.settings(.notifications).parentSectionForBack,
            .appAndFamily
        )
        XCTAssertEqual(
            GuardianDestination.familySync.parentSectionForBack,
            .appAndFamily
        )
    }

    func testPracticePlanMergePreservesHiddenAppAndFamilySettings() throws {
        let settings = makeDistinctSettings()
        let merged = try XCTUnwrap(
            GuardianSettingsMergePolicy.merging(
                edited: settings.edited,
                section: .practicePlan,
                into: settings.current
            )
        )

        XCTAssertEqual(merged.read, settings.edited.read)
        XCTAssertEqual(merged.write, settings.edited.write)
        XCTAssertEqual(merged.audio, settings.current.audio)
        XCTAssertEqual(merged.notifications, settings.current.notifications)
        XCTAssertEqual(merged.interface, settings.current.interface)
    }

    func testAppAndFamilyMergesPreserveHiddenPracticePlan() throws {
        let settings = makeDistinctSettings()
        let sound = try XCTUnwrap(
            GuardianSettingsMergePolicy.merging(
                edited: settings.edited,
                section: .soundAndAccessibility,
                into: settings.current
            )
        )
        let notifications = try XCTUnwrap(
            GuardianSettingsMergePolicy.merging(
                edited: settings.edited,
                section: .notifications,
                into: settings.current
            )
        )

        XCTAssertEqual(sound.read, settings.current.read)
        XCTAssertEqual(sound.write, settings.current.write)
        XCTAssertEqual(sound.audio, settings.edited.audio)
        XCTAssertEqual(sound.interface, settings.edited.interface)
        XCTAssertEqual(sound.notifications, settings.current.notifications)

        XCTAssertEqual(notifications.read, settings.current.read)
        XCTAssertEqual(notifications.write, settings.current.write)
        XCTAssertEqual(notifications.audio, settings.current.audio)
        XCTAssertEqual(notifications.interface, settings.current.interface)
        XCTAssertEqual(notifications.notifications, settings.edited.notifications)
    }

    func testSettingsMergeRejectsAnotherKidProfile() {
        let settings = makeDistinctSettings()
        let anotherKid = ProfilePracticeSettings.defaults(for: ProfileID())

        XCTAssertNil(
            GuardianSettingsMergePolicy.merging(
                edited: anotherKid,
                section: .practicePlan,
                into: settings.current
            )
        )
    }

    @MainActor
    func testReturnToParentSectionUsesCurrentFeatureOwnership() {
        let model = makeModel()

        model.showQuickAdd()
        model.returnToParentSection()
        XCTAssertEqual(model.transitionKey, "parent-section-wordsAndPractice")

        model.showSettings(.notifications)
        model.returnToParentSection()
        XCTAssertEqual(model.transitionKey, "parent-section-appAndFamily")
    }

    @MainActor
    private func makeModel() -> GuardianDashboardViewModel {
        GuardianDashboardViewModel(
            store: DemoGuardianFamilyStore(),
            audioPromptService: NavigationTestAudioPromptService()
        )
    }

    private func makeDistinctSettings() -> (
        current: ProfilePracticeSettings,
        edited: ProfilePracticeSettings
    ) {
        let profileID = ProfileID()
        let current = ProfilePracticeSettings(
            profileID: profileID,
            read: LearningRouteSettings(
                newWordLimit: 2,
                reviewWordLimit: 3,
                contentOrder: .newThenReview,
                emergencyAfterSeconds: 120
            ),
            write: LearningRouteSettings(
                newWordLimit: 4,
                reviewWordLimit: 5,
                contentOrder: .newThenReview,
                emergencyAfterSeconds: 180
            ),
            audio: AudioPreferences(
                voiceEnabled: false,
                musicEnabled: false,
                soundEffectsEnabled: false
            ),
            notifications: .disabled,
            interface: .default
        )
        let edited = ProfilePracticeSettings(
            profileID: profileID,
            read: LearningRouteSettings(
                newWordLimit: 6,
                reviewWordLimit: 7,
                contentOrder: .reviewThenNew,
                emergencyAfterSeconds: 240
            ),
            write: LearningRouteSettings(
                newWordLimit: 8,
                reviewWordLimit: 9,
                contentOrder: .reviewThenNew,
                emergencyAfterSeconds: 300
            ),
            audio: .default,
            notifications: LearningNotificationPreferences(
                dailyReminderEnabled: true,
                weeklySummaryEnabled: true
            ),
            interface: PracticeInterfacePreferences(
                leftHandedLayoutEnabled: true
            )
        )
        return (current, edited)
    }
}

private struct NavigationTestAudioPromptService: AudioPromptService {
    func play(_ prompt: WordPrompt, for profileID: ProfileID) async throws {
        _ = prompt
        _ = profileID
    }
}
