import XCTest

@MainActor
final class TadaWordsCriticalFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    /// Regression coverage for the P0 where the success layer remained over
    /// the quest forever. The demo recognizer deterministically accepts any
    /// non-empty stroke, so this exercises the real Write view twice without
    /// depending on Vision handwriting recognition.
    func testWriteCompletionFeedbackDismissesAcrossTwoWords() throws {
        launchDemo(startingAt: "moonpetal-write")

        XCTAssertTrue(
            element(label: "Handwriting area").waitForExistence(timeout: 8),
            "The demo launch route should open Write Practice."
        )

        completeCurrentWriteWord()
        assertWriteSuccessDismissesAndAdvances(toItem: 2)

        completeCurrentWriteWord()
        assertWriteSuccessDismissesAndAdvances(toItem: 3)
    }

    /// Covers the child-facing Write fork end to end. The spelling surface is
    /// a theme-matched in-app control, never a system text-entry keyboard.
    func testLobbyWriteSpellWithLettersUsesCustomKeyboardAndAdvances() throws {
        launchDemo(startingAt: "moonpetal")

        let writeQuest = app.buttons["Write, Hear it. Write it."]
        XCTAssertTrue(writeQuest.waitForExistence(timeout: 8))
        writeQuest.tap()

        let spellWithLetters = app.descendants(matching: .any)[
            "write-method.letterKeyboard"
        ]
        XCTAssertTrue(spellWithLetters.waitForExistence(timeout: 5))
        spellWithLetters.tap()

        XCTAssertTrue(app.buttons["spell.key.A"].waitForExistence(timeout: 8))
        XCTAssertEqual(
            app.keyboards.count,
            0,
            "The in-app letter board must not present a native iOS keyboard."
        )
        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            let key = app.buttons["spell.key.\(letter)"]
            XCTAssertTrue(key.exists, "Missing custom letter key \(letter).")
        }

        // DemoQuestContentProvider deterministically presents `look` first.
        for letter in "LOOK" {
            let key = app.buttons["spell.key.\(letter)"]
            XCTAssertTrue(key.isHittable)
            key.tap()
        }
        let done = app.buttons["spell.done"]
        XCTAssertTrue(waitUntil(timeout: 3) { done.isEnabled && done.isHittable })
        done.tap()

        let progress = element(label: "Quest progress")
        XCTAssertTrue(
            waitUntil(timeout: 4) {
                (progress.value as? String)?.hasPrefix("Item 2 of ") == true
            },
            "Correct custom-keyboard spelling should advance to item 2."
        )
    }

    /// The same completion lifecycle powers Read Practice. This uses the
    /// deterministic demo speech recognizer and verifies two asynchronous
    /// recognition completions cannot leave "You got it!" over the next word.
    func testReadCompletionFeedbackDismissesAcrossTwoWords() throws {
        launchDemo(startingAt: "moonpetal-read")

        XCTAssertTrue(startListeningButton.waitForExistence(timeout: 8))
        startListeningButton.tap()
        assertReadSuccessDismissesAndAdvances(toItem: 2)

        XCTAssertTrue(startListeningButton.waitForExistence(timeout: 5))
        startListeningButton.tap()
        assertReadSuccessDismissesAndAdvances(toItem: 3)
    }

    /// Covers the parent-session delete contract: only the first deletion asks
    /// for confirmation, every deletion exposes Undo, and sorting remains
    /// interactive after the list mutates.
    func testParentSequentialDeletesKeepUndoAndSortInteractive() throws {
        launchParentWordManager()

        let firstDelete = app.buttons["Remove the"]
        XCTAssertTrue(firstDelete.waitForExistence(timeout: 5))
        firstDelete.tap()

        let confirmation = app.alerts["Remove this word?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.buttons["Remove"].tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5))

        let secondDelete = app.buttons["Remove and"]
        XCTAssertTrue(secondDelete.waitForExistence(timeout: 5))
        secondDelete.tap()

        XCTAssertFalse(
            confirmation.waitForExistence(timeout: 1),
            "Only the first removal in a parent session should ask again."
        )
        XCTAssertTrue(
            app.buttons["Undo"].waitForExistence(timeout: 5),
            "Undo must remain available after the second removal."
        )

        let addedOrder = app.buttons["Sort words by Added order"]
        XCTAssertTrue(addedOrder.waitForExistence(timeout: 5))
        addedOrder.tap()

        let alphabetical = app.buttons["A–Z"]
        XCTAssertTrue(alphabetical.waitForExistence(timeout: 3))
        alphabetical.tap()
        XCTAssertTrue(
            app.buttons["Sort words by A–Z"].waitForExistence(timeout: 3),
            "The pool sort menu should still update after consecutive deletes."
        )
    }

    /// Delete All always names the affected mode and current count, requires a
    /// dedicated destructive confirmation, and leaves a full-pool Undo.
    func testParentDeleteAllConfirmsCountAndRestoresEntireReadPool() throws {
        launchParentWordManager()

        let deleteAll = app.buttons["Delete all 5 Read words"]
        XCTAssertTrue(deleteAll.waitForExistence(timeout: 5))
        deleteAll.tap()

        let confirmation = app.alerts["Delete all 5 Read words?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        XCTAssertTrue(
            confirmation.staticTexts[
                "All 5 words will leave the Read pool and future practice. Learning history stays available. You can undo this change."
            ].exists
        )
        confirmation.buttons["Delete all"].tap()

        XCTAssertTrue(app.staticTexts["No read words yet"].waitForExistence(timeout: 5))
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()

        XCTAssertTrue(app.buttons["Remove the"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Delete all 5 Read words"].exists)
    }

    /// Presets remain parent-controlled: opening a suggested list is read-only,
    /// and one explicit Add action de-duplicates independently into both pools.
    func testParentPresetSelectionAddsOnlyAfterExplicitApproval() throws {
        launchDemo()
        unlockParentArea()

        let wordsAndPractice = app.buttons["guardian.home.words-and-practice"]
        XCTAssertTrue(wordsAndPractice.waitForExistence(timeout: 8))
        wordsAndPractice.tap()

        let openPresets = app.buttons["guardian.words.presets"]
        XCTAssertTrue(openPresets.waitForExistence(timeout: 8))
        openPresets.tap()

        XCTAssertTrue(app.staticTexts["Preset words"].waitForExistence(timeout: 5))
        let starterList = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Pre-K Starters")
        ).firstMatch
        XCTAssertTrue(starterList.waitForExistence(timeout: 5))
        starterList.tap()

        let selectAll = app.buttons["Select all"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.buttons["Add 40 selected words"].exists,
            "Opening a preset must not preselect or add its words."
        )
        selectAll.tap()

        let both = app.buttons["Both"]
        XCTAssertTrue(both.waitForExistence(timeout: 3))
        both.tap()

        let add = app.buttons["Add 40 selected words"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()

        XCTAssertTrue(
            app.staticTexts[
                "Added 73 pool entries. 7 already exist in the selected pool or pools."
            ]
            .waitForExistence(timeout: 8),
            "The two pools should be updated only after the parent's final Add."
        )
    }

    /// Exercises the system sheet boundary implicated by the report that sort
    /// stopped responding after leaving bulk import. Presenting and dismissing
    /// the same PhotosPicker guards against a stuck modal or hit-testing layer.
    func testPoolSortWorksAfterDismissingPhotoPicker() throws {
        launchParentWordManager()

        XCTAssertFalse(
            app.buttons["guardian.ocr-fixture"].exists,
            "The OCR fixture must remain hidden without explicit UI-test flags."
        )

        let choosePhotos = app.buttons["Choose Photos"]
        XCTAssertTrue(choosePhotos.waitForExistence(timeout: 5))
        choosePhotos.tap()

        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(
            cancel.waitForExistence(timeout: 8),
            "The system Photos picker should present a Cancel control."
        )
        cancel.tap()

        let addedOrder = app.buttons["Sort words by Added order"]
        XCTAssertTrue(addedOrder.waitForExistence(timeout: 5))
        addedOrder.tap()
        XCTAssertTrue(app.buttons["Most practiced"].waitForExistence(timeout: 3))
        app.buttons["Most practiced"].tap()
        XCTAssertTrue(
            app.buttons["Sort words by Most practiced"].waitForExistence(timeout: 3)
        )
    }

    /// Runs the real OCR review and bulk-add UI without depending on a seeded
    /// system Photos library. The deterministic recognizer is compiled only in
    /// Debug and requires both explicit UI-test launch flags.
    func testOCRFixtureReviewAddAllAndPoolSort() throws {
        launchParentWordManager(
            additionalLaunchArguments: [
                "--ui-testing",
                "--ui-testing-ocr-fixture",
            ]
        )

        let fixtureImport = app.buttons["guardian.ocr-fixture"]
        // On an iPhone in landscape, the debug-only import control sits just
        // below the visible part of the input card. Bring it into the viewport
        // before querying it so XCTest does not spend minutes snapshotting an
        // off-screen SwiftUI hierarchy after a failed lookup.
        let managerScrollView = app.scrollViews.firstMatch
        for _ in 0..<3 where !fixtureImport.exists {
            managerScrollView.swipeUp()
        }
        XCTAssertTrue(fixtureImport.waitForExistence(timeout: 5))
        fixtureImport.tap()

        let reviewTitle = app.staticTexts["Review scanned words"]
        XCTAssertTrue(reviewTitle.waitForExistence(timeout: 8))
        XCTAssertFalse(
            app.staticTexts["Help with pronunciation"].exists,
            "Canonical pronunciation should not require a context editor."
        )
        let scrollToBottom = app.buttons["Scroll to bottom"]
        for word in ["cat", "read", "bow", "to"] {
            let rowAction = app.buttons["Remove \(word)"]
            if !rowAction.exists {
                XCTAssertTrue(scrollToBottom.waitForExistence(timeout: 3))
                scrollToBottom.tap()
            }
            XCTAssertTrue(
                rowAction.waitForExistence(timeout: 3),
                "OCR Review should contain \(word)."
            )
        }

        let addAll = app.buttons["Add all 4 to Read"]
        XCTAssertTrue(addAll.waitForExistence(timeout: 5))
        XCTAssertTrue(addAll.isEnabled)
        addAll.tap()

        XCTAssertTrue(
            waitUntil(timeout: 8) { !reviewTitle.exists },
            "A successful Add All should dismiss OCR Review."
        )
        for word in ["cat", "read", "bow", "to"] {
            XCTAssertTrue(
                app.buttons["Remove \(word)"].waitForExistence(timeout: 5),
                "The Read Pool should contain imported word \(word)."
            )
        }

        let addedOrder = app.buttons["Sort words by Added order"]
        XCTAssertTrue(addedOrder.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            app.scrollViews.firstMatch.swipeDown()
        }
        addedOrder.tap()
        XCTAssertTrue(app.buttons["A–Z"].waitForExistence(timeout: 3))
        app.buttons["A–Z"].tap()
        XCTAssertTrue(
            app.buttons["Sort words by A–Z"].waitForExistence(timeout: 3),
            "Pool sorting should remain interactive after Add All."
        )
    }

    private func launchDemo(
        startingAt route: String? = nil,
        additionalLaunchArguments: [String] = []
    ) {
        app.launchArguments = ["--demo-mode"] + additionalLaunchArguments
        if let route {
            app.launchArguments.append("--demo-start=\(route)")
        }
        app.launch()
    }

    private func launchParentWordManager(
        additionalLaunchArguments: [String] = []
    ) {
        launchDemo(additionalLaunchArguments: additionalLaunchArguments)
        unlockParentArea()

        let wordsAndPractice = app.buttons["guardian.home.words-and-practice"]
        XCTAssertTrue(wordsAndPractice.waitForExistence(timeout: 8))
        wordsAndPractice.tap()

        let manageWords = app.buttons["guardian.words.manage"]
        XCTAssertTrue(manageWords.waitForExistence(timeout: 8))
        manageWords.tap()
    }

    private func completeCurrentWriteWord() {
        let canvas = element(label: "Handwriting area")
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertTrue(canvas.isHittable)

        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.58))
            .press(
                forDuration: 0.08,
                thenDragTo: canvas.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.70, dy: 0.42)
                )
            )

        let done = app.buttons["Done"]
        XCTAssertTrue(waitUntil(timeout: 3) { done.isEnabled && done.isHittable })
        done.tap()
    }

    private func assertWriteSuccessDismissesAndAdvances(toItem item: Int) {
        let success = element(label: "Great job. Beautiful writing!")
        // The acknowledgement is intentionally shorter than XCUITest's
        // post-tap idle synchronization, so it may already be gone when the
        // test process regains control. Advancement plus the final absence is
        // the stable regression assertion for the never-dismissed blocker.
        _ = success.waitForExistence(timeout: 0.4)

        let progress = element(label: "Quest progress")
        XCTAssertTrue(
            waitUntil(timeout: 4) {
                (progress.value as? String)?.hasPrefix("Item \(item) of ") == true
            },
            "The quest should advance to item \(item)."
        )
        XCTAssertFalse(
            success.exists,
            "The completion acknowledgement must not remain over the next word."
        )
    }

    private func assertReadSuccessDismissesAndAdvances(toItem item: Int) {
        let success = element(label: "Great job. You got it!")
        _ = success.waitForExistence(timeout: 2.5)

        let progress = element(label: "Quest progress")
        XCTAssertTrue(
            waitUntil(timeout: 6) {
                (progress.value as? String)?.hasPrefix("Item \(item) of ") == true
            },
            "Read Practice should advance to item \(item)."
        )
        XCTAssertFalse(
            success.exists,
            "You got it must not remain over the next Read word."
        )
    }

    private func unlockParentArea() {
        let parents = app.buttons["profile-chooser.grown-ups"]
        XCTAssertTrue(parents.waitForExistence(timeout: 8))
        parents.tap()

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
    }

    private func element(label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", label)
        ).firstMatch
    }

    private var startListeningButton: XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "Start listening")
        ).firstMatch
    }

    @discardableResult
    private func waitUntil(
        timeout: TimeInterval,
        pollInterval: TimeInterval = 0.08,
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
