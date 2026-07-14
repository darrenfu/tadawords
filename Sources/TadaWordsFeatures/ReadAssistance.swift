/// Read help stays locked until two genuine wrong answers. Silence, permission
/// failures, and recognizer uncertainty never reveal the answer early.
enum ReadAssistancePolicy {
    static let incorrectAttemptThreshold = 2

    static func shouldReveal(
        validIncorrectAttemptCount: Int,
        isComplete: Bool
    ) -> Bool {
        !isComplete
            && validIncorrectAttemptCount >= incorrectAttemptThreshold
    }
}
