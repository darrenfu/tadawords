import XCTest

/// Simulator E2E coverage for the real local-first Family Sync composition.
/// Only the remote server is deterministic; repositories, the durable journal,
/// apply transactions, receipt refresh, Parent pages, and Kid navigation are
/// the same objects used by production.
@MainActor
final class TadaWordsFamilySyncUITests: XCTestCase {
    private static let defaultProfileID =
        "3B20FEF0-7E43-4B70-8F89-D37AD55454A1"
    private static let adoptedProfileID =
        "A4E3A3AF-11BE-44F2-9E35-9F563808452A"

    private var app: XCUIApplication!
    private var suite: String!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        suite = "sync-\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
        suite = nil
    }

    func testFirstRunNewProfileShowsCanonicalZodiacAvatarChoices() throws {
        launch(scenario: "second-device-adoption", reset: true)

        let createNew = app.buttons["first-run.create-new"]
        XCTAssertTrue(createNew.waitForExistence(timeout: 10))
        createNew.tap()

        let expectedAnimals = [
            "Rat", "Ox", "Tiger", "Rabbit", "Dragon", "Snake",
            "Horse", "Goat", "Monkey", "Rooster", "Dog", "Pig",
        ]
        XCTAssertTrue(app.buttons["Rat"].isSelected)

        let topScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        topScreenshot.name = "First-run zodiac Profile avatar picker - top"
        topScreenshot.lifetime = .keepAlways
        add(topScreenshot)

        for animal in expectedAnimals {
            var remainingScrollAttempts = 4
            while !app.buttons[animal].exists, remainingScrollAttempts > 0 {
                app.swipeUp()
                remainingScrollAttempts -= 1
            }
            XCTAssertTrue(
                app.buttons[animal].waitForExistence(timeout: 5),
                "Missing zodiac Profile choice: \(animal)"
            )
        }

        let bottomScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        bottomScreenshot.name = "First-run zodiac Profile avatar picker - bottom"
        bottomScreenshot.lifetime = .keepAlways
        add(bottomScreenshot)
    }

    func testCleanSecondDeviceAdoptsIndependentRemoteProfileWithoutLocalSeed()
        throws
    {
        launch(scenario: "second-device-adoption", reset: true)

        let consent = app.switches["first-run.privacy-consent"]
        XCTAssertTrue(consent.waitForExistence(timeout: 10))
        consent.tap()

        let findExisting = app.buttons["first-run.find-existing"]
        XCTAssertTrue(findExisting.waitForExistence(timeout: 5))
        findExisting.tap()

        let remote = app.buttons[
            "first-run.discovery.profile.\(Self.adoptedProfileID)"
        ]
        XCTAssertTrue(
            remote.waitForExistence(timeout: 18),
            "A clean device should discover the independent remote UUID."
        )
        XCTAssertFalse(app.buttons["My Kid"].exists)

        let finish = app.buttons["first-run.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()
        assertOnlyAdoptedKidIsVisible()

        launch(scenario: "second-device-adoption", reset: false)
        assertOnlyAdoptedKidIsVisible()
    }

    func testDiscoveredProfileRemainsAnAdoptionCandidateAcrossRelaunch() throws {
        launch(scenario: "second-device-adoption", reset: true)
        acceptPrivacyAndFindExistingProfile()
        XCTAssertTrue(adoptionCandidate.waitForExistence(timeout: 18))
        XCTAssertFalse(app.buttons["My Kid"].exists)

        // Discovery imports the candidate durably before adoption. Relaunch in
        // that window and prove it remains an exact-ID candidate rather than
        // becoming an editable local new-kid seed.
        launch(scenario: "second-device-adoption", reset: false)
        acceptPrivacyAndFindExistingProfile()
        XCTAssertTrue(adoptionCandidate.waitForExistence(timeout: 18))
        XCTAssertFalse(app.buttons["My Kid"].exists)
    }

    func testRemoteBundleRefreshesKidAndParentSurfaces() throws {
        launch(scenario: "remote-bundle", reset: true)

        let remoteProfile = app.buttons["Remote Mia"]
        tapCenterWhenHittable(
            remoteProfile,
            timeout: 18,
            failureMessage:
                "A committed remote Profile receipt should refresh the Kid chooser."
        )

        let badge = app.buttons["child-lobby.badge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 8))
        badge.tap()
        let reward = app.descendants(matching: .any)["Starlight Tiara"]
        let collectionScrollView = app.scrollViews.firstMatch
        for _ in 0..<5 where !reward.exists {
            collectionScrollView.swipeUp()
        }
        XCTAssertTrue(
            reward.waitForExistence(timeout: 5),
            "The remote reward grant should appear in the real Kid collection."
        )
        app.buttons["Close"].tap()

        let kids = app.buttons["child-lobby.kids"]
        XCTAssertTrue(kids.waitForExistence(timeout: 5))
        kids.tap()
        unlockParentArea()

        let selectedKid = app.buttons["guardian.home.selected-kid"]
        XCTAssertTrue(selectedKid.waitForExistence(timeout: 10))
        XCTAssertTrue(selectedKid.label.contains("Remote Mia"))

        let progress = app.buttons["guardian.home.progress-and-performance"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertTrue(
            progress.label.contains("1 to review"),
            "A remote immutable attempt should rebuild visible progress."
        )
        XCTAssertTrue(
            progress.label.contains("1 quest"),
            "A remote daily completion should refresh the visible quest count."
        )

        let wordsAndPractice = app.buttons["guardian.home.words-and-practice"]
        wordsAndPractice.tap()
        let manageWords = app.buttons["guardian.words.manage"]
        XCTAssertTrue(manageWords.waitForExistence(timeout: 5))
        XCTAssertTrue(manageWords.label.contains("1 Read"))
        XCTAssertTrue(manageWords.label.contains("1 Write"))

        let practicePlan = app.buttons["guardian.words.practice-plan"]
        XCTAssertTrue(practicePlan.waitForExistence(timeout: 5))
        XCTAssertTrue(practicePlan.label.contains("Read 7 new"))
        XCTAssertTrue(practicePlan.label.contains("Write 6 new"))

        app.buttons["Back"].firstMatch.tap()
        openFamilySyncPage()
        assertSyncStatus("Up to date", timeout: 12)
    }

    func testOfflinePendingSurvivesTerminationAndClearsAfterOnlineAck() throws {
        launch(scenario: "offline", reset: true)
        unlockParentArea()
        openFamilySyncPage()
        assertSyncStatus("Waiting for a connection", timeout: 12)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "safe on this device")
            ).firstMatch.exists
        )

        launch(scenario: "online", reset: false)
        unlockParentArea()
        openFamilySyncPage()
        assertSyncStatus("Up to date", timeout: 15)
    }

    func testCorruptRemoteRecordIsQuarantinedAndShownToParent() throws {
        launch(scenario: "quarantine", reset: true)
        unlockParentArea()
        openFamilySyncPage()
        assertSyncStatus("Sync needs attention", timeout: 15)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "kept aside"
                )
            ).firstMatch.waitForExistence(timeout: 5)
        )
    }

    func testSignedOutAndRestrictedStatesRemainParentVisible() throws {
        launch(scenario: "signed-out", reset: true)
        unlockParentArea()
        openFamilySyncPage()
        assertSyncStatus("iCloud is unavailable", timeout: 12)
        XCTAssertTrue(app.staticTexts["Sign in to iCloud to sync Tada Words."].exists)

        suite = "sync-\(UUID().uuidString)"
        launch(scenario: "restricted", reset: true)
        unlockParentArea()
        openFamilySyncPage()
        assertSyncStatus("iCloud is unavailable", timeout: 12)
        XCTAssertTrue(
            app.staticTexts["iCloud sync is restricted on this device."].exists
        )
    }

    func testRemoteDeletionAbandonsActiveKidAndReturnsToChooser() throws {
        seedRemoteProfileAndRememberSelection()

        launch(
            scenario: "delayed-deletion",
            reset: false,
            deletionDelaySeconds: 10
        )
        openRememberedRemoteProfile()
        XCTAssertTrue(app.buttons["child-lobby.kids"].waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.staticTexts["Who’s playing?"].waitForExistence(timeout: 18),
            "Deleting the active Profile remotely must abandon the child route."
        )
        XCTAssertFalse(
            app.buttons["Remote Mia"].exists
        )
    }

    func testRemoteDeletionRecoversParentEditorToAddChild() throws {
        seedRemoteProfileAndRememberSelection()

        launch(
            scenario: "delayed-deletion",
            reset: false,
            deletionDelaySeconds: 25
        )
        openRememberedRemoteProfile()
        let kids = app.buttons["child-lobby.kids"]
        XCTAssertTrue(kids.waitForExistence(timeout: 8))
        kids.tap()
        unlockParentArea()

        let selectedKid = app.buttons["guardian.home.selected-kid"]
        XCTAssertTrue(selectedKid.waitForExistence(timeout: 6))
        selectedKid.tap()

        let edit = app.buttons[
            "guardian.profile.\(Self.defaultProfileID).edit"
        ]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.staticTexts["Edit profile"].waitForExistence(timeout: 5))

        XCTAssertTrue(
            app.staticTexts["Add a child"].waitForExistence(timeout: 18),
            "A remotely deleted Profile must not leave Parents on a stale editor."
        )
        XCTAssertFalse(app.staticTexts["Edit profile"].exists)
    }

    private func seedRemoteProfileAndRememberSelection() {
        launch(scenario: "remote-bundle", reset: true)
        let remoteProfile = app.buttons["Remote Mia"]
        tapCenterWhenHittable(
            remoteProfile,
            timeout: 18,
            failureMessage: "The seeded remote Profile should become interactive."
        )
        XCTAssertTrue(app.buttons["child-lobby.kids"].waitForExistence(timeout: 8))
    }

    private func assertOnlyAdoptedKidIsVisible() {
        let remoteProfile = app.buttons["Remote Mia"]
        if remoteProfile.waitForExistence(timeout: 8) {
            XCTAssertFalse(
                app.buttons["My Kid"].exists,
                "The random simulator seed must never become a second child."
            )
            tapCenterWhenHittable(
                remoteProfile,
                timeout: 12,
                failureMessage: "The adopted remote Profile should become interactive."
            )
            XCTAssertTrue(
                app.buttons["child-lobby.kids"].waitForExistence(timeout: 8)
            )
            return
        }

        let kids = app.buttons["child-lobby.kids"]
        XCTAssertTrue(kids.waitForExistence(timeout: 12))
        kids.tap()
        XCTAssertTrue(remoteProfile.waitForExistence(timeout: 8))
        XCTAssertFalse(
            app.buttons["My Kid"].exists,
            "The random simulator seed must never become a second child."
        )
    }

    private var adoptionCandidate: XCUIElement {
        app.buttons["first-run.discovery.profile.\(Self.adoptedProfileID)"]
    }

    private func acceptPrivacyAndFindExistingProfile() {
        let consent = app.switches["first-run.privacy-consent"]
        XCTAssertTrue(consent.waitForExistence(timeout: 10))
        consent.tap()
        let findExisting = app.buttons["first-run.find-existing"]
        XCTAssertTrue(findExisting.waitForExistence(timeout: 5))
        findExisting.tap()
    }

    private func openRememberedRemoteProfile() {
        let remoteProfile = app.buttons["Remote Mia"]
        tapCenterWhenHittable(
            remoteProfile,
            timeout: 12,
            failureMessage:
                "The remembered remote Profile should become interactive after relaunch."
        )
    }

    private func launch(
        scenario: String,
        reset: Bool,
        deletionDelaySeconds: Int? = nil
    ) {
        app.terminate()
        app.launchArguments = [
            "--ui-testing",
            "--family-sync-e2e",
            "--family-sync-suite=\(suite!)",
            "--family-sync-scenario=\(scenario)",
        ]
        if reset {
            app.launchArguments.append("--family-sync-reset")
        }
        if let deletionDelaySeconds {
            app.launchArguments.append(
                "--family-sync-deletion-delay=\(deletionDelaySeconds)"
            )
        }
        app.launch()
    }

    private func unlockParentArea() {
        let parents = app.buttons["profile-chooser.grown-ups"]
        tapCenterWhenHittable(
            parents,
            timeout: 12,
            failureMessage:
                "The profile chooser Parents button should become tappable after launch."
        )

        let question = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "What is ")
        ).firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        let factors = question.label
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
        guard factors.count == 2 else {
            XCTFail("Unexpected parent challenge: \(question.label)")
            return
        }
        let answer = app.textFields["Answer"]
        XCTAssertTrue(answer.waitForExistence(timeout: 3))
        answer.tap()
        answer.typeText(String(factors[0] * factors[1]))
        XCTAssertTrue(
            app.buttons["guardian.home.selected-kid"].waitForExistence(timeout: 10)
        )
    }

    private func openFamilySyncPage() {
        let appAndFamily = app.buttons["guardian.home.app-and-family"]
        XCTAssertTrue(appAndFamily.waitForExistence(timeout: 8))
        appAndFamily.tap()
        let familySync = app.buttons["guardian.app.sync"]
        XCTAssertTrue(familySync.waitForExistence(timeout: 8))
        familySync.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["guardian.sync.page"]
                .waitForExistence(timeout: 8)
        )
    }

    private func assertSyncStatus(
        _ expected: String,
        timeout: TimeInterval
    ) {
        let status = app.descendants(matching: .any)["guardian.sync.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitUntil(timeout: timeout) { status.label == expected },
            "Expected sync status '\(expected)', got '\(status.label)'."
        )
    }

    private func tapCenterWhenHittable(
        _ element: XCUIElement,
        timeout: TimeInterval,
        failureMessage: String
    ) {
        let becameHittable = waitUntil(timeout: timeout) {
            element.exists && element.isHittable
        }
        guard becameHittable else {
            XCTFail(failureMessage)
            return
        }

        element.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).tap()
    }

    @discardableResult
    private func waitUntil(
        timeout: TimeInterval,
        pollInterval: TimeInterval = 0.1,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        } while Date() < deadline
        return condition()
    }
}
