import Foundation
import TadaWordsDomain

enum TestFixture {
    static let now = Date(timeIntervalSince1970: 2_000_000_000)
    static let profileID = ProfileID(
        rawValue: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    )
    static let questID = QuestID(
        rawValue: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    )

    static func wordID(_ number: Int) -> WordPromptID {
        let suffix = String(format: "%012X", number)
        return WordPromptID(
            rawValue: UUID(
                uuidString: "30000000-0000-0000-0000-\(suffix)"
            )!
        )
    }

    static func attemptID(_ number: Int) -> AttemptID {
        let suffix = String(format: "%012X", number)
        return AttemptID(
            rawValue: UUID(
                uuidString: "40000000-0000-0000-0000-\(suffix)"
            )!
        )
    }

    static func correctionID(_ number: Int) -> AttemptCorrectionID {
        let suffix = String(format: "%012X", number)
        return AttemptCorrectionID(
            rawValue: UUID(
                uuidString: "50000000-0000-0000-0000-\(suffix)"
            )!
        )
    }

    static func attempt(
        number: Int,
        wordNumber: Int,
        mode: LearningMode = .read,
        evidence: EncounterEvidence = .firstIndependentAttempt,
        outcome: AttemptOutcome,
        at date: Date = now,
        responseSeconds: TimeInterval? = 2,
        replayCount: Int = 0,
        questID: QuestID? = questID
    ) -> AttemptEvent {
        let elapsed = responseSeconds.map(ElapsedTime.init(seconds:))
        let timing: AttemptTiming
        switch mode {
        case .read:
            timing = AttemptTiming(
                totalResponseTime: elapsed,
                speechOnsetLatency: elapsed
            )
        case .write:
            timing = AttemptTiming(totalResponseTime: elapsed)
        }

        return AttemptEvent(
            id: attemptID(number),
            questID: questID,
            profileID: profileID,
            wordPromptID: wordID(wordNumber),
            learningMode: mode,
            evidence: evidence,
            outcome: outcome,
            timing: timing,
            occurredAt: date,
            replayCount: replayCount
        )
    }

    static func paceContext(
        mode: LearningMode = .read,
        wordLength: Int = 3
    ) -> PaceContext {
        PaceContext(
            learningMode: mode,
            deviceClass: .tablet,
            inputMethod: mode == .read ? .speech : .fingerWriting,
            wordLength: wordLength
        )
    }

    static func paceBand(
        context: PaceContext,
        lower: TimeInterval = 1,
        upper: TimeInterval = 3,
        sampleCount: Int = 5
    ) -> PersonalPaceBand {
        PersonalPaceBand(
            context: context,
            lowerBound: ElapsedTime(seconds: lower),
            upperBound: ElapsedTime(seconds: upper),
            sampleCount: sampleCount
        )
    }
}
