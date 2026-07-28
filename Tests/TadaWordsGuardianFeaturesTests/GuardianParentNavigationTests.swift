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

    @MainActor
    func testDashboardProfileEditReturnsDirectlyToDashboard() async throws {
        let store = DemoGuardianFamilyStore()
        let family = try await store.familySnapshot()
        let profile = try XCTUnwrap(family.profiles.first)
        let model = GuardianDashboardViewModel(
            store: store,
            audioPromptService: NavigationTestAudioPromptService()
        )

        model.showEditProfileFromDashboard(profile)
        XCTAssertEqual(model.transitionKey, "profile-editor-\(profile.id)")

        XCTAssertFalse(model.returnFromProfileEditor())
        XCTAssertEqual(model.transitionKey, "dashboard")
    }

    func testAllParentPagesUseTheSameTopLeftInsets() {
        XCTAssertEqual(
            GuardianParentPageLayout.horizontalInset,
            GuardianPrimitiveTokens.Spacing.medium
        )
        XCTAssertEqual(
            GuardianParentPageLayout.verticalInset,
            GuardianPrimitiveTokens.Spacing.medium
        )
    }

    func testAppAndFamilyPreservesEveryFeatureEntryAndFullName() {
        XCTAssertEqual(
            GuardianAppAndFamilyFeature.allCases,
            [
                .soundAndAccessibility,
                .notifications,
                .speechAndMicrophone,
                .familySync,
                .thirdPartyNotices,
            ]
        )
        XCTAssertEqual(
            GuardianAppAndFamilyFeature.allCases.map(\.title),
            [
                "Sound & Accessibility",
                "Notifications",
                "Speech & Microphone",
                "Family Sync",
                "Credits",
            ]
        )
        XCTAssertEqual(
            Set(GuardianAppAndFamilyFeature.allCases.map(\.accessibilityIdentifier))
                .count,
            GuardianAppAndFamilyFeature.allCases.count
        )
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
            GuardianDestination.speechPermissions.parentSectionForBack,
            .appAndFamily
        )
        XCTAssertEqual(
            GuardianDestination.familySync.parentSectionForBack,
            .appAndFamily
        )
        XCTAssertEqual(
            GuardianDestination.thirdPartyNotices.parentSectionForBack,
            .appAndFamily
        )
    }

    func testParentResourcesUseOnlyExpectedPawgooHTTPSDestinations() {
        XCTAssertEqual(
            GuardianParentResource.allCases,
            [.privacyPolicy, .support]
        )
        XCTAssertEqual(
            GuardianParentResource.privacyPolicy.destination.absoluteString,
            "https://pawgoo.app/en/tadawords/privacy"
        )
        XCTAssertEqual(
            GuardianParentResource.support.destination.absoluteString,
            "https://pawgoo.app/en/support"
        )

        for resource in GuardianParentResource.allCases {
            XCTAssertEqual(resource.destination.scheme, "https")
            XCTAssertEqual(resource.destination.host, "pawgoo.app")
            XCTAssertNil(resource.destination.query)
            XCTAssertNil(resource.destination.fragment)
            XCTAssertFalse(resource.accessibilityIdentifier.isEmpty)
        }
    }

    func testThirdPartyNoticeMatchesBundledTwemojiAttribution() {
        XCTAssertEqual(
            GuardianThirdPartyNoticesContent.title,
            "Credits"
        )
        XCTAssertEqual(
            GuardianThirdPartyNoticesContent.attribution,
            "Twemoji graphics © X Corp. and other contributors."
        )
        XCTAssertEqual(
            GuardianThirdPartyNoticesContent.sourceDescription,
            "Tada Words includes 74 unmodified graphics from jdecked/twemoji 17.0.3."
        )
        XCTAssertEqual(
            GuardianThirdPartyNoticesContent.licenseDescription,
            "The graphics are licensed under the Creative Commons Attribution 4.0 International license."
        )
        XCTAssertEqual(
            GuardianThirdPartyNoticesContent.offlineDescription,
            "This notice and the picture-hint graphics are built into Tada Words and remain available offline."
        )
        XCTAssertEqual(
            GuardianThirdPartyNoticesContent.sourceURL.absoluteString,
            "https://github.com/jdecked/twemoji"
        )
        XCTAssertEqual(
            GuardianThirdPartyNoticesContent.licenseURL.absoluteString,
            "https://creativecommons.org/licenses/by/4.0/"
        )
        XCTAssertTrue(
            GuardianThirdPartyNoticesContent.wordCatalogAttribution
                .contains("Robyn Speer")
        )
        XCTAssertTrue(
            GuardianThirdPartyNoticesContent.wordCatalogDescription
                .contains("wordfreq 3.1.1")
        )
        XCTAssertEqual(
            GuardianThirdPartyNoticesContent.wordCatalogLicenseURL.absoluteString,
            "https://creativecommons.org/licenses/by-sa/4.0/"
        )
    }

    func testOnlyAppAndFamilyConfigPagesAutoSave() {
        XCTAssertFalse(GuardianSettingsSection.practicePlan.usesAutoSave)
        XCTAssertTrue(GuardianSettingsSection.soundAndAccessibility.usesAutoSave)
        XCTAssertTrue(GuardianSettingsSection.notifications.usesAutoSave)
    }

    @MainActor
    func testAppAndFamilyAutoSavePersistsLatestChangeWithoutLeavingPage() async throws {
        let store = DemoGuardianFamilyStore()
        let model = GuardianDashboardViewModel(
            store: store,
            audioPromptService: NavigationTestAudioPromptService()
        )
        await model.refreshAfterExternalSyncAndWait()
        let original = try XCTUnwrap(model.snapshot?.practiceSettings)
        model.showSettings(.soundAndAccessibility)

        let first = ProfilePracticeSettings(
            profileID: original.profileID,
            read: original.read,
            write: original.write,
            audio: AudioPreferences(musicEnabled: false),
            notifications: original.notifications,
            interface: original.interface
        )
        let latest = ProfilePracticeSettings(
            profileID: original.profileID,
            read: original.read,
            write: original.write,
            audio: AudioPreferences(
                voiceEnabled: false,
                musicEnabled: false,
                soundEffectsEnabled: false,
                reducedSoundEnabled: true,
                calmEmergencyEnabled: true
            ),
            notifications: original.notifications,
            interface: PracticeInterfacePreferences(
                leftHandedLayoutEnabled: true,
                selectedHandwritingTool: original.interface.selectedHandwritingTool
            )
        )

        model.autoSavePracticeSettings(first, section: .soundAndAccessibility)
        model.autoSavePracticeSettings(latest, section: .soundAndAccessibility)

        let deadline = ContinuousClock.now + .seconds(2)
        var saved = original
        while ContinuousClock.now < deadline {
            saved = try await store.dashboardSnapshot().practiceSettings
            if saved.audio == latest.audio, saved.interface == latest.interface {
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(saved.audio, latest.audio)
        XCTAssertEqual(saved.interface, latest.interface)
        XCTAssertEqual(
            model.transitionKey,
            "settings-soundAndAccessibility",
            "Auto-save must not close the settings page."
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

        model.showSpeechPermissions()
        XCTAssertEqual(model.transitionKey, "speech-permissions")
        model.returnToParentSection()
        XCTAssertEqual(model.transitionKey, "parent-section-appAndFamily")

        model.showThirdPartyNotices()
        XCTAssertEqual(model.transitionKey, "third-party-notices")
        model.returnToParentSection()
        XCTAssertEqual(model.transitionKey, "parent-section-appAndFamily")
    }

    @MainActor
    func testAppStoreOnePointZeroVoiceprintRoutesFailClosed() async throws {
        let store = DemoGuardianFamilyStore()
        let family = try await store.familySnapshot()
        let profile = try XCTUnwrap(family.profiles.first)
        let model = GuardianDashboardViewModel(
            store: store,
            audioPromptService: NavigationTestAudioPromptService()
        )

        XCTAssertEqual(model.transitionKey, "parent-gate")
        model.showVoiceprint(profile)
        XCTAssertEqual(model.transitionKey, "parent-gate")

        model.beginVoiceprint(for: profile)
        XCTAssertEqual(
            model.errorMessage,
            "Voice setup is not included in this release."
        )
    }

    @MainActor
    func testEditingProfileAutoSavesLatestDraftWithoutLeavingEditor() async throws {
        let store = DemoGuardianFamilyStore()
        let initialFamily = try await store.familySnapshot()
        let original = try XCTUnwrap(initialFamily.profiles.first)
        let model = GuardianDashboardViewModel(
            store: store,
            audioPromptService: NavigationTestAudioPromptService()
        )
        model.showEditProfile(original)

        let firstDraft = GuardianProfileDraft(
            displayName: "Mia First",
            avatar: .cartoonAnimal(assetID: "rat"),
            selectedWorld: .moonpetalKingdom,
            schoolGrade: .preK,
            ageYears: 5
        )
        let latestDraft = GuardianProfileDraft(
            displayName: "Mia Latest",
            avatar: .cartoonAnimal(assetID: "tiger"),
            selectedWorld: .buildItBay,
            schoolGrade: .kindergarten,
            ageYears: 6,
            guardianUnlockedWorlds: [.buildItBay]
        )

        model.saveProfile(existingProfile: original, draft: firstDraft)
        model.saveProfile(existingProfile: original, draft: latestDraft)

        let deadline = ContinuousClock.now + .seconds(2)
        var savedProfile = original
        while ContinuousClock.now < deadline {
            let currentFamily = try await store.familySnapshot()
            savedProfile = try XCTUnwrap(
                currentFamily.profiles.first(where: { $0.id == original.id })
            )
            if savedProfile.displayName == latestDraft.displayName { break }
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertEqual(savedProfile.displayName, latestDraft.displayName)
        XCTAssertEqual(savedProfile.avatar, latestDraft.avatar)
        XCTAssertEqual(savedProfile.selectedWorld, latestDraft.selectedWorld)
        XCTAssertEqual(savedProfile.schoolGrade, latestDraft.schoolGrade)
        XCTAssertEqual(savedProfile.ageYears, latestDraft.ageYears)
        XCTAssertEqual(
            savedProfile.guardianUnlockedWorlds,
            latestDraft.guardianUnlockedWorlds
        )
        XCTAssertEqual(
            model.transitionKey,
            "profile-editor-\(original.id)",
            "Auto-save must not close the editor"
        )
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
