import Foundation
import TadaWordsDomain

@testable import TadaWordsFeatures

enum TestFixture {
    static let now = Date(timeIntervalSince1970: 2_000_000_000)
    static let utc = TimeZone(secondsFromGMT: 0)!
    static let questID = QuestID(
        rawValue: UUID(uuidString: "73000000-0000-0000-0000-000000000001")!
    )

    static func profile(name: String, number: Int) -> KidProfile {
        KidProfile(
            id: ProfileID(rawValue: uuid(prefix: "74", number: number)),
            displayName: name,
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    static func prompt(
        _ word: String,
        number: Int,
        mode: LearningMode = .read
    ) throws -> WordPrompt {
        try WordPrompt(
            id: WordPromptID(rawValue: uuid(prefix: "75", number: number)),
            learningMode: mode,
            text: word
        )
    }

    static func summary(
        decisions: [RecognitionDecision]
    ) throws -> QuestAttemptSummary {
        var machine = QuestAttemptStateMachine()
        for decision in decisions {
            guard machine.beginAttempt() else {
                throw TestFailure.invalidAttemptSequence
            }
            machine.receive(RecognitionResult(decision: decision))
        }
        guard let summary = machine.completedSummary else {
            throw TestFailure.incompleteAttemptSequence
        }
        return summary
    }

    private static func uuid(prefix: String, number: Int) -> UUID {
        let suffix = String(format: "%012X", number)
        return UUID(
            uuidString: "\(prefix)000000-0000-0000-0000-\(suffix)"
        )!
    }

    private enum TestFailure: Error {
        case invalidAttemptSequence
        case incompleteAttemptSequence
    }
}

struct TestClock: AppClock {
    let now: Date

    init(now: Date = TestFixture.now) {
        self.now = now
    }
}
