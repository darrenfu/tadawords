import Combine
import Foundation

enum QuestTimerSuspension: Hashable, Sendable {
    case legacy
    case userPause
    case promptPlayback
    case speechRecognition
    case handwritingRecognition
    case saving
    case appInactive
}

/// A quest-scoped monotonic-enough presentation clock. It owns only UI timing;
/// learning evidence records its own adapter-provided measurements.
@MainActor
final class QuestTimerModel: ObservableObject {
    @Published private(set) var elapsedSeconds: TimeInterval = 0

    let emergencyAfter: TimeInterval
    private let now: () -> TimeInterval
    private var accumulatedSeconds: TimeInterval = 0
    private var startedAt: TimeInterval?
    private var tickerTask: Task<Void, Never>?
    private var suspensions: Set<QuestTimerSuspension> = []
    private var hasStarted = false
    private(set) var isFinished = false

    init(
        emergencyAfter: TimeInterval,
        now: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.emergencyAfter = max(1, emergencyAfter)
        self.now = now
    }

    var elapsedText: String {
        let wholeSeconds = max(0, Int(elapsedSeconds.rounded(.down)))
        return String(format: "%d:%02d", wholeSeconds / 60, wholeSeconds % 60)
    }

    var isEmergency: Bool {
        elapsedSeconds >= emergencyAfter
    }

    var isRunning: Bool {
        startedAt != nil
    }

    func start() {
        guard !isFinished else { return }
        hasStarted = true
        startClockIfPossible()
    }

    func suspend(for reason: QuestTimerSuspension) {
        guard !isFinished else { return }
        guard suspensions.insert(reason).inserted else { return }
        pauseClock()
    }

    func resume(from reason: QuestTimerSuspension) {
        guard !isFinished else { return }
        suspensions.remove(reason)
        startClockIfPossible()
    }

    /// Compatibility seam for existing tests and callers. Production code
    /// should use named suspension reasons so overlapping waits stay paused.
    func pause() {
        suspend(for: .legacy)
    }

    func resume() {
        resume(from: .legacy)
    }

    func stop() {
        pauseClock()
        suspensions.removeAll()
        isFinished = true
    }

    private func startClockIfPossible() {
        guard hasStarted, suspensions.isEmpty, startedAt == nil else { return }
        startedAt = now()
        refresh()
        scheduleTicks()
    }

    private func pauseClock() {
        guard startedAt != nil else { return }
        refresh()
        accumulatedSeconds = elapsedSeconds
        startedAt = nil
        tickerTask?.cancel()
        tickerTask = nil
    }

    private func scheduleTicks() {
        tickerTask?.cancel()
        tickerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
                self?.refresh()
            }
        }
    }

    private func refresh() {
        guard let startedAt else {
            elapsedSeconds = accumulatedSeconds
            return
        }
        elapsedSeconds = accumulatedSeconds + max(0, now() - startedAt)
    }
}
