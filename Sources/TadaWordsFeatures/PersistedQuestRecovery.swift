import Foundation
import TadaWordsDomain

enum PersistedQuestRecoveryError: Error, Equatable, Sendable {
    case inconsistentEvidence
}

struct PersistedQuestRecovery: Sendable {
    let attempts: [AttemptEvent]
    let completedWordIDs: Set<WordPromptID>
    let nextItemIndex: Int
    let eventsByWordID: [WordPromptID: [AttemptEvent]]
}

/// Reconstructs durable item checkpoints from immutable attempt evidence.
/// A multi-record summary is complete only when its persisted prefix reaches a
/// terminal state, so a crash halfway through appending retries cannot skip a
/// word on relaunch.
struct PersistedQuestRecoveryResolver: Sendable {
    func resolve(
        plan: QuestPlan,
        attempts: [AttemptEvent]
    ) throws -> PersistedQuestRecovery {
        let plannedItems = plan.orderedItems
        let plannedWordIDs = Set(plannedItems.map(\.wordPromptID))
        let questAttempts =
            attempts
            .filter { $0.questID == plan.id }
            .sorted(by: attemptPrecedes)

        guard
            questAttempts.allSatisfy({ attempt in
                attempt.profileID == plan.profileID
                    && attempt.learningMode == plan.configuration.learningMode
                    && plannedWordIDs.contains(attempt.wordPromptID)
            })
        else {
            throw PersistedQuestRecoveryError.inconsistentEvidence
        }

        let eventsByWordID = Dictionary(
            grouping: questAttempts,
            by: \.wordPromptID
        )
        var completedWordIDs = Set<WordPromptID>()
        var nextItemIndex = 0
        var foundIncompleteItem = false

        for (index, item) in plannedItems.enumerated() {
            let events = eventsByWordID[item.wordPromptID] ?? []
            if foundIncompleteItem {
                guard events.isEmpty else {
                    throw PersistedQuestRecoveryError.inconsistentEvidence
                }
                continue
            }

            if try isTerminalCheckpoint(
                events,
                policy: plan.configuration.learningMode == .write ? .write : .read
            ) {
                completedWordIDs.insert(item.wordPromptID)
                nextItemIndex = index + 1
            } else {
                foundIncompleteItem = true
                nextItemIndex = index
            }
        }

        return PersistedQuestRecovery(
            attempts: questAttempts,
            completedWordIDs: completedWordIDs,
            nextItemIndex: nextItemIndex,
            eventsByWordID: eventsByWordID
        )
    }

    private func isTerminalCheckpoint(
        _ events: [AttemptEvent],
        policy: QuestAttemptPolicy
    ) throws -> Bool {
        var submissionCount = 0
        var consecutiveTechnicalIssueCount = 0

        for event in events {
            switch (event.evidence, event.outcome) {
            case (
                .firstIndependentAttempt,
                .correct
            ),
                (
                    .unaidedRetry,
                    .correct
                ),
                (
                    .guidedRetry,
                    .correct
                ):
                submissionCount += 1
                return true

            case (
                .firstIndependentAttempt,
                .incorrect
            ),
                (
                    .unaidedRetry,
                    .incorrect
                ),
                (
                    .guidedRetry,
                    .incorrect
                ):
                submissionCount += 1
                consecutiveTechnicalIssueCount = 0
                if submissionCount >= policy.maximumSubmissionCount {
                    return true
                }

            case (.technicalRetry, .technicalFailure):
                consecutiveTechnicalIssueCount += 1
                if consecutiveTechnicalIssueCount
                    >= QuestAttemptStateMachine.technicalIssueSkipThreshold
                {
                    return true
                }

            case (.recognitionUncertain, .recognitionUncertain):
                switch policy {
                case .read:
                    consecutiveTechnicalIssueCount += 1
                    if consecutiveTechnicalIssueCount
                        >= QuestAttemptStateMachine.technicalIssueSkipThreshold
                    {
                        return true
                    }
                case .write:
                    submissionCount += 1
                    consecutiveTechnicalIssueCount = 0
                    if submissionCount >= policy.maximumSubmissionCount {
                        return true
                    }
                }

            case (.studyExposed, .skipped), (.feedbackExposed, .skipped),
                (.helped, .skipped):
                continue

            default:
                throw PersistedQuestRecoveryError.inconsistentEvidence
            }
        }
        return false
    }

    private func attemptPrecedes(_ left: AttemptEvent, _ right: AttemptEvent) -> Bool {
        if left.occurredAt != right.occurredAt {
            return left.occurredAt < right.occurredAt
        }
        return left.id.rawValue.uuidString < right.id.rawValue.uuidString
    }
}
