import Foundation

/// Converts the quest-wide active timer into a per-attempt active duration.
/// Resetting after any retry prevents earlier speaking/writing and recognition
/// waits from leaking into the next valid pace measurement.
struct AttemptResponseClock: Equatable, Sendable {
    private(set) var originElapsedSeconds: TimeInterval

    init(startingAt elapsedSeconds: TimeInterval) {
        originElapsedSeconds = Self.normalized(elapsedSeconds)
    }

    mutating func reset(at elapsedSeconds: TimeInterval) {
        originElapsedSeconds = Self.normalized(elapsedSeconds)
    }

    func elapsed(at elapsedSeconds: TimeInterval) -> TimeInterval {
        max(0, Self.normalized(elapsedSeconds) - originElapsedSeconds)
    }

    private static func normalized(_ value: TimeInterval) -> TimeInterval {
        value.isFinite ? max(0, value) : 0
    }
}
