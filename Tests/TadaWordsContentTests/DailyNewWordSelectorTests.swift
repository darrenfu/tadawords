import TadaWordsContent
import TadaWordsDomain
import XCTest

final class DailyNewWordSelectorTests: XCTestCase {
    func testTodayBatchComesBeforeQueuedPoolAndKeepsBatchOrder() throws {
        let oldFirst = try ContentTestFixture.entry(
            "oldest",
            number: 1,
            addedAt: ContentTestFixture.day.addingTimeInterval(-172_800)
        )
        let oldSecond = try ContentTestFixture.entry(
            "older",
            number: 2,
            addedAt: ContentTestFixture.day.addingTimeInterval(-86_400)
        )
        let todayFirst = try ContentTestFixture.entry(
            "zebra",
            number: 3,
            addedAt: ContentTestFixture.day,
            position: 0
        )
        let todaySecond = try ContentTestFixture.entry(
            "apple",
            number: 4,
            addedAt: ContentTestFixture.day,
            position: 1
        )
        let entries = [oldSecond, todaySecond, oldFirst, todayFirst]

        let selected = DailyNewWordSelector(
            timeZone: ContentTestFixture.utc
        ).select(
            from: entries,
            request: DailyNewWordSelectionRequest(
                profileID: ContentTestFixture.profileID,
                learningMode: .read,
                date: ContentTestFixture.day
            )
        )

        XCTAssertEqual(
            selected.map(\.normalizedText),
            ["zebra", "apple", "oldest", "older"]
        )
    }

    func testLaterTodayBatchMovesAheadOfEarlierTodayBatch() throws {
        let early = try ContentTestFixture.entry(
            "early",
            number: 1,
            addedAt: ContentTestFixture.day,
            lastQueuedAt: ContentTestFixture.day,
            position: 0
        )
        let late = try ContentTestFixture.entry(
            "late",
            number: 2,
            addedAt: ContentTestFixture.day,
            lastQueuedAt: ContentTestFixture.day.addingTimeInterval(60),
            position: 0
        )

        let selected = DailyNewWordSelector(
            timeZone: ContentTestFixture.utc
        ).select(
            from: [early, late],
            request: DailyNewWordSelectionRequest(
                profileID: ContentTestFixture.profileID,
                learningMode: .read,
                date: ContentTestFixture.day
            )
        )

        XCTAssertEqual(selected.map(\.normalizedText), ["late", "early"])
    }

    func testFiltersProfileModeInactiveAndExcludedEntries() throws {
        let included = try ContentTestFixture.entry(
            "included",
            number: 1,
            addedAt: ContentTestFixture.day
        )
        let inactive = try ContentTestFixture.entry(
            "inactive",
            number: 2,
            addedAt: ContentTestFixture.day,
            isActive: false
        )
        let otherProfile = try ContentTestFixture.entry(
            "profile",
            number: 3,
            profileID: ContentTestFixture.secondProfileID,
            addedAt: ContentTestFixture.day
        )
        let write = try ContentTestFixture.entry(
            "write",
            number: 4,
            mode: .write,
            addedAt: ContentTestFixture.day,
            audioCue: .contextual("Please write the word write.")
        )
        let excluded = try ContentTestFixture.entry(
            "excluded",
            number: 5,
            addedAt: ContentTestFixture.day
        )

        let selected = DailyNewWordSelector(
            timeZone: ContentTestFixture.utc
        ).select(
            from: [inactive, otherProfile, write, excluded, included],
            request: DailyNewWordSelectionRequest(
                profileID: ContentTestFixture.profileID,
                learningMode: .read,
                date: ContentTestFixture.day,
                excludingWordPromptIDs: [excluded.prompt.id]
            )
        )

        XCTAssertEqual(selected.map(\.id), [included.id])
    }

    func testDefaultLimitsAreReadFiveAndWriteThree() throws {
        let readEntries = try (1...6).map { number in
            try ContentTestFixture.entry(
                "readword\(letter(for: number))",
                number: number,
                addedAt: ContentTestFixture.day,
                position: number
            )
        }
        let writeEntries = try (1...4).map { number in
            try ContentTestFixture.entry(
                "writeword\(letter(for: number))",
                number: number + 20,
                mode: .write,
                addedAt: ContentTestFixture.day,
                position: number
            )
        }
        let selector = DailyNewWordSelector(timeZone: ContentTestFixture.utc)

        let readSelection = selector.select(
            from: readEntries,
            request: DailyNewWordSelectionRequest(
                profileID: ContentTestFixture.profileID,
                learningMode: .read,
                date: ContentTestFixture.day
            )
        )
        let writeSelection = selector.select(
            from: writeEntries,
            request: DailyNewWordSelectionRequest(
                profileID: ContentTestFixture.profileID,
                learningMode: .write,
                date: ContentTestFixture.day
            )
        )

        XCTAssertEqual(readSelection.count, 5)
        XCTAssertEqual(writeSelection.count, 3)
    }

    func testSelectionDoesNotDependOnRepositoryReturnOrder() throws {
        let entries = try (1...5).map { number in
            try ContentTestFixture.entry(
                "word\(letter(for: number))",
                number: number,
                addedAt: ContentTestFixture.day.addingTimeInterval(
                    Double(-number * 60)
                )
            )
        }
        let selector = DailyNewWordSelector(timeZone: ContentTestFixture.utc)
        let request = DailyNewWordSelectionRequest(
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            date: ContentTestFixture.day,
            limit: 5
        )

        XCTAssertEqual(
            selector.select(from: entries, request: request).map(\.id),
            selector.select(from: entries.reversed(), request: request).map(\.id)
        )
    }

    func testExplicitTimeZoneDefinesTodayAtDayBoundary() throws {
        let timeZone = try XCTUnwrap(
            TimeZone(identifier: "America/Los_Angeles")
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let requestDate = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 12,
                    hour: 0,
                    minute: 15
                )
            )
        )
        let priorLocalDay = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 11,
                    hour: 23,
                    minute: 45
                )
            )
        )
        let currentLocalDay = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 12,
                    hour: 0,
                    minute: 1
                )
            )
        )
        let previous = try ContentTestFixture.entry(
            "previous",
            number: 1,
            addedAt: priorLocalDay
        )
        let today = try ContentTestFixture.entry(
            "today",
            number: 2,
            addedAt: currentLocalDay
        )

        let selected = DailyNewWordSelector(timeZone: timeZone).select(
            from: [previous, today],
            request: DailyNewWordSelectionRequest(
                profileID: ContentTestFixture.profileID,
                learningMode: .read,
                date: requestDate
            )
        )

        XCTAssertEqual(selected.map(\.normalizedText), ["today", "previous"])
    }

    private func letter(for number: Int) -> String {
        String(UnicodeScalar(96 + number)!)
    }
}
