import XCTest

@MainActor
final class TadaWordsCriticalFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
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

        let writeQuest = app.descendants(matching: .any)["child-lobby.quest.write"]
        XCTAssertTrue(writeQuest.waitForExistence(timeout: 8))
        writeQuest.tap()

        XCTAssertTrue(app.staticTexts["Spell Mode"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["How do you want to spell?"].exists)
        XCTAssertTrue(app.buttons["Handwriting"].exists)
        XCTAssertTrue(app.buttons["Typing"].exists)
        let chooserBack = app.buttons["write-method.back"]
        XCTAssertTrue(chooserBack.exists)
        XCTAssertEqual(chooserBack.label, "Back")
        chooserBack.tap()
        XCTAssertTrue(writeQuest.waitForExistence(timeout: 5))
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
        assertContainedInVisibleWindow(
            app.buttons["quest.back"],
            message: "The compact quest chrome must keep Back on screen."
        )
        assertContainedInVisibleWindow(
            app.buttons["spell.key.A"],
            message: "The compact letter board must keep its first row on screen."
        )
        assertContainedInVisibleWindow(
            app.buttons["spell.done"],
            message: "The compact letter board must keep submission on screen."
        )
        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            let key = app.buttons["spell.key.\(letter)"]
            XCTAssertTrue(key.exists, "Missing custom letter key \(letter).")
        }

        // DemoQuestContentProvider deterministically presents `look` first.
        for letter in "LOOK" {
            let key = app.buttons["spell.key.\(letter)"]
            XCTAssertTrue(
                waitUntil(timeout: 5) { key.isEnabled },
                "The letter key should become interactive after prompt audio finishes."
            )
            tapCenter(of: key)
        }
        let done = app.buttons["spell.done"]
        XCTAssertTrue(waitUntil(timeout: 3) { done.isEnabled })
        tapCenter(of: done)

        let progress = element(label: "Quest progress")
        XCTAssertTrue(
            waitUntil(timeout: 4) {
                (progress.value as? String)?.hasPrefix("Item 2 of ") == true
            },
            "Correct custom-keyboard spelling should advance to item 2."
        )
    }

    /// Two independent spelling misses reveal the target without advancing.
    /// The child can then imitate the visible word on a third guided attempt.
    func testSpellSecondMissRevealsWordAndAllowsGuidedThirdAttempt() throws {
        launchDemo(startingAt: "moonpetal")

        let writeQuest = app.descendants(matching: .any)["child-lobby.quest.write"]
        XCTAssertTrue(writeQuest.waitForExistence(timeout: 8))
        writeQuest.tap()

        let spellWithLetters = app.descendants(matching: .any)[
            "write-method.letterKeyboard"
        ]
        XCTAssertTrue(spellWithLetters.waitForExistence(timeout: 5))
        spellWithLetters.tap()

        let aKey = app.buttons["spell.key.A"]
        let done = app.buttons["spell.done"]
        XCTAssertTrue(aKey.waitForExistence(timeout: 8))

        for _ in 0..<2 {
            for _ in 0..<4 {
                XCTAssertTrue(waitUntil(timeout: 5) { aKey.isEnabled })
                tapCenter(of: aKey)
            }
            XCTAssertTrue(waitUntil(timeout: 3) { done.isEnabled })
            tapCenter(of: done)
        }

        XCTAssertTrue(
            element(label: "Example spelling: look").waitForExistence(timeout: 5),
            "The second independent miss should reveal the answer for imitation."
        )
        XCTAssertTrue(
            waitUntil(timeout: 5) { aKey.isEnabled },
            "The revealed answer must not complete or disable the third attempt."
        )

        for letter in "LOOK" {
            let key = app.buttons["spell.key.\(letter)"]
            XCTAssertTrue(waitUntil(timeout: 5) { key.isEnabled })
            tapCenter(of: key)
        }
        XCTAssertTrue(waitUntil(timeout: 3) { done.isEnabled })
        tapCenter(of: done)

        let progress = element(label: "Quest progress")
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                (progress.value as? String)?.hasPrefix("Item 2 of ") == true
            },
            "A correct guided third attempt should advance to item 2."
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

    /// Exercises the real result-board reveal after all five deterministic
    /// demo answers so the final card uses the exact earned-word count.
    func testReadQuestResultShowsExactEarnedStarCount() throws {
        launchDemo(startingAt: "moonpetal-read")

        let progress = element(label: "Quest progress")
        for nextItem in 2...5 {
            XCTAssertTrue(startListeningButton.waitForExistence(timeout: 8))
            startListeningButton.tap()
            XCTAssertTrue(
                waitUntil(timeout: 6) {
                    (progress.value as? String)?.hasPrefix(
                        "Item \(nextItem) of "
                    ) == true
                },
                "Read Practice should advance to item \(nextItem)."
            )
        }

        XCTAssertTrue(startListeningButton.waitForExistence(timeout: 8))
        startListeningButton.tap()

        let starCount = app.otherElements["quest-result.star-count"]
        XCTAssertTrue(
            starCount.waitForExistence(timeout: 12),
            "Completing all five words should reveal the Quest Board star count."
        )
        XCTAssertEqual(starCount.label, "5 stars earned")
        XCTAssertNotEqual(
            starCount.value as? String,
            "0",
            "A nonzero result must begin at 1, never flash 0."
        )
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                (starCount.value as? String) == "5"
            },
            "The visible flip card should finish counting through 5."
        )
    }

    /// Parent Home uses ordinary back navigation while restoring the gate for
    /// the next visit; the old lock control is no longer presented.
    func testParentHomeBackReturnsToPreviousChildPage() throws {
        launchDemo()
        unlockParentArea()

        let back = app.buttons["guardian.home.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["guardian.home.lock"].exists)

        back.tap()

        XCTAssertTrue(
            app.buttons["profile-chooser.grown-ups"].waitForExistence(timeout: 8)
        )
    }

    /// App Store privacy and support resources stay parent-only while remaining
    /// discoverable in both compact phone and regular-width iPad layouts.
    func testParentAppAndFamilyExposesPrivacySupportAndDataControls() throws {
        launchDemo()
        unlockParentArea()

        let appAndFamily = app.buttons["guardian.home.app-and-family"]
        XCTAssertTrue(appAndFamily.waitForExistence(timeout: 8))
        appAndFamily.tap()

        let privacy = element(label: "Privacy Policy")
        let support = element(label: "Support")
        let localDeletion = element(labelPrefix: "Delete a local profile.")
        let permissions = element(labelPrefix: "Manage iOS permissions.")
        let appVersion = element(label: "Version 0.7.51 (2026072604)")

        for _ in 0..<4 where !privacy.exists {
            app.scrollViews.firstMatch.swipeUp()
        }

        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
        XCTAssertTrue(support.waitForExistence(timeout: 5))
        XCTAssertEqual(privacy.label, "Privacy Policy")
        XCTAssertEqual(support.label, "Support")

        for _ in 0..<4 where !permissions.exists {
            app.scrollViews.firstMatch.swipeUp()
        }

        XCTAssertTrue(localDeletion.waitForExistence(timeout: 5))
        XCTAssertTrue(permissions.waitForExistence(timeout: 5))

        for _ in 0..<4 where !appVersion.exists {
            app.scrollViews.firstMatch.swipeUp()
        }

        XCTAssertTrue(appVersion.waitForExistence(timeout: 5))
        XCTAssertEqual(appVersion.label, "Version 0.7.51 (2026072604)")
    }

    /// Third-party credits stay behind the Parent Gate while their complete
    /// attribution remains readable offline inside the app.
    func testParentCanOpenOfflineThirdPartyNotices() throws {
        launchDemo(
            additionalLaunchArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            ]
        )
        unlockParentArea()

        let appAndFamily = app.buttons["guardian.home.app-and-family"]
        XCTAssertTrue(appAndFamily.waitForExistence(timeout: 8))
        appAndFamily.tap()

        let notices = app.buttons["guardian.app.third-party-notices"]
        for _ in 0..<4 where !notices.exists {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(notices.waitForExistence(timeout: 5))
        notices.tap()

        for expectedText in [
            "Twemoji graphics © X Corp. and other contributors.",
            "Tada Words includes 74 unmodified graphics from jdecked/twemoji 17.0.3.",
            "The graphics are licensed under the Creative Commons Attribution 4.0 International license.",
            "This notice and the picture-hint graphics are built into Tada Words and remain available offline.",
        ] {
            let text = app.staticTexts[expectedText]
            for _ in 0..<5 where !text.exists {
                app.scrollViews.firstMatch.swipeUp()
            }
            XCTAssertTrue(text.waitForExistence(timeout: 5))
        }

        let sourceLink = app.links["guardian.third-party-notices.source"]
        let sourceButton = app.buttons["guardian.third-party-notices.source"]
        let licenseLink = app.links["guardian.third-party-notices.license"]
        let licenseButton = app.buttons["guardian.third-party-notices.license"]
        for _ in 0..<5 where !(sourceLink.exists || sourceButton.exists) {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(sourceLink.exists || sourceButton.exists)
        XCTAssertTrue(licenseLink.exists || licenseButton.exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Third-Party Notices - Largest Dynamic Type"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        for _ in 0..<5 where !app.buttons["Back"].exists {
            app.scrollViews.firstMatch.swipeDown()
        }
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(
            app.buttons["guardian.app.third-party-notices"]
                .waitForExistence(timeout: 5)
        )
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
            waitUntil(timeout: 8) { cancel.exists && cancel.isHittable },
            "The system Photos picker should present an interactive Cancel control."
        )
        tapCenter(of: cancel)
        XCTAssertTrue(
            waitUntil(timeout: 8) { !cancel.exists },
            "The Photos picker must finish dismissing before the app becomes interactive."
        )

        let addedOrder = app.buttons["Sort words by Added order"]
        XCTAssertTrue(addedOrder.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitUntil(timeout: 8) { addedOrder.isHittable },
            "The Word Pool sort control should be hittable after Photos picker dismissal."
        )
        tapCenter(of: addedOrder)
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

    /// Runs on both iPhone and iPad destinations. A deterministic captured-image
    /// fixture replaces only the unavailable simulator camera; the app still
    /// exercises the production capture-to-editor and cancellation state path.
    func testCameraCaptureRoutesToEditorAndCancelPreservesWordPool() throws {
        launchParentWordManager(
            additionalLaunchArguments: [
                "--ui-testing",
                "--ui-testing-camera-editor-fixture",
            ]
        )

        let takePhoto = app.buttons["Take Photo"]
        let managerScrollView = app.scrollViews.firstMatch
        for _ in 0..<3 where !takePhoto.exists {
            managerScrollView.swipeUp()
        }
        XCTAssertTrue(takePhoto.waitForExistence(timeout: 5))
        XCTAssertTrue(takePhoto.isEnabled)
        takePhoto.tap()

        XCTAssertTrue(
            app.otherElements["guardian.photo-editor"].waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.buttons["Use Photo"].exists)
        XCTAssertTrue(app.buttons["Reset"].exists)

        let topLeftCropHandle = app.otherElements["Crop top left corner"]
        XCTAssertTrue(topLeftCropHandle.waitForExistence(timeout: 3))
        XCTAssertTrue(topLeftCropHandle.isHittable)
        let undo = app.buttons["Undo"]
        XCTAssertFalse(undo.isEnabled)
        let cropStart = topLeftCropHandle.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )
        cropStart.press(
            forDuration: 0.1,
            thenDragTo: cropStart.withOffset(CGVector(dx: 36, dy: 28))
        )
        XCTAssertTrue(undo.isEnabled, "Dragging a visible crop handle should record an edit.")

        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.exists)
        cancel.tap()

        XCTAssertTrue(
            waitUntil(timeout: 8) {
                !self.app.otherElements["guardian.photo-editor"].exists
            },
            "Cancel should release the editor and return without opening OCR Review."
        )
        XCTAssertFalse(app.staticTexts["Review scanned words"].exists)
        XCTAssertTrue(app.staticTexts["Manage words"].waitForExistence(timeout: 5))
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

    private func assertContainedInVisibleWindow(
        _ element: XCUIElement,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        let visibleFrame = app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1)
        XCTAssertTrue(
            visibleFrame.contains(element.frame),
            "\(message) Window: \(visibleFrame), element: \(element.frame)",
            file: file,
            line: line
        )
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
        let showWord = app.buttons["Show the word"]
        XCTAssertTrue(
            waitUntil(timeout: 5) { showWord.isEnabled },
            "The canvas should become interactive after prompt audio finishes."
        )

        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.58))
            .press(
                forDuration: 0.08,
                thenDragTo: canvas.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.70, dy: 0.42)
                )
            )

        let done = app.buttons["Done"]
        XCTAssertTrue(waitUntil(timeout: 3) { done.isEnabled })
        tapCenter(of: done)
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
        // The parent gate owns initial focus, so the flow must accept typing
        // immediately after the single tap on Parents.
        answer.typeText(String(factors[0] * factors[1]))
    }

    private func element(label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", label)
        ).firstMatch
    }

    private func element(labelPrefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", labelPrefix)
        ).firstMatch
    }

    private func tapCenter(of element: XCUIElement) {
        // XCTest can expose portrait-space frames for controls after an app-
        // owned landscape handoff. A direct center coordinate sends the real
        // touch while state assertions still prove that the control responded.
        element.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).tap()
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
