import Foundation

/// Coordinates visible success feedback, transition audio, and the next word.
/// A child should never hear a new prompt attached to the tail of a celebration.
enum QuestAdvanceTimingPolicy {
    static let breathingRoomAfterTransition: Duration = .milliseconds(700)

    static func breathingRoom(hasNextItem: Bool) -> Duration {
        hasNextItem ? breathingRoomAfterTransition : .zero
    }

    static func waitBeforeAdvance(
        minimumFeedbackVisibility: Duration,
        feedbackPlayback: Task<Void, Never>?,
        hasNextItem: Bool
    ) async throws {
        let clock = ContinuousClock()
        let startedAt = clock.now

        if let feedbackPlayback {
            await feedbackPlayback.value
        }
        try Task.checkCancellation()

        let elapsed = startedAt.duration(to: clock.now)
        if elapsed < minimumFeedbackVisibility {
            try await Task.sleep(for: minimumFeedbackVisibility - elapsed)
        }

        let breathingRoom = breathingRoom(hasNextItem: hasNextItem)
        if breathingRoom > .zero {
            try await Task.sleep(for: breathingRoom)
        }
    }
}
