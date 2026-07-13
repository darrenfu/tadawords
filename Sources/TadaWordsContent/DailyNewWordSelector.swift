import Foundation
import TadaWordsDomain

public enum DailyNewWordLimit {
    public static func defaultValue(for learningMode: LearningMode) -> Int {
        switch learningMode {
        case .read:
            QuestConfiguration.defaultRead.newWordLimit
        case .write:
            QuestConfiguration.defaultWrite.newWordLimit
        }
    }
}

public struct DailyNewWordSelectionRequest: Sendable {
    public let profileID: ProfileID
    public let learningMode: LearningMode
    public let date: Date
    public let limit: Int
    public let excludingWordPromptIDs: Set<WordPromptID>

    public init(
        profileID: ProfileID,
        learningMode: LearningMode,
        date: Date,
        limit: Int? = nil,
        excludingWordPromptIDs: Set<WordPromptID> = []
    ) {
        self.profileID = profileID
        self.learningMode = learningMode
        self.date = date
        self.limit = max(
            0,
            limit ?? DailyNewWordLimit.defaultValue(for: learningMode)
        )
        self.excludingWordPromptIDs = excludingWordPromptIDs
    }
}

/// Selects today's manual entries first, followed by the oldest queued pool
/// entries. All tie-breaks are explicit so repository return order is irrelevant.
public struct DailyNewWordSelector: Sendable {
    private let calendar: Calendar

    public init(timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    public func select(
        from entries: [WordPoolEntry],
        request: DailyNewWordSelectionRequest
    ) -> [WordPoolEntry] {
        entries
            .filter { entry in
                entry.profileID == request.profileID
                    && entry.learningMode == request.learningMode
                    && entry.isActive
                    && !request.excludingWordPromptIDs.contains(entry.prompt.id)
            }
            .sorted { left, right in
                selectionOrder(left, right, on: request.date)
            }
            .prefix(request.limit)
            .map { $0 }
    }

    private func selectionOrder(
        _ left: WordPoolEntry,
        _ right: WordPoolEntry,
        on date: Date
    ) -> Bool {
        let leftWasQueuedToday = calendar.isDate(
            left.lastQueuedAt,
            inSameDayAs: date
        )
        let rightWasQueuedToday = calendar.isDate(
            right.lastQueuedAt,
            inSameDayAs: date
        )

        if leftWasQueuedToday != rightWasQueuedToday {
            return leftWasQueuedToday
        }

        if leftWasQueuedToday, left.lastQueuedAt != right.lastQueuedAt {
            return left.lastQueuedAt > right.lastQueuedAt
        }

        if !leftWasQueuedToday, left.addedAt != right.addedAt {
            return left.addedAt < right.addedAt
        }

        if left.positionInLastBatch != right.positionInLastBatch {
            return left.positionInLastBatch < right.positionInLastBatch
        }
        if left.normalizedText != right.normalizedText {
            return left.normalizedText < right.normalizedText
        }
        return left.id.rawValue.uuidString < right.id.rawValue.uuidString
    }
}
