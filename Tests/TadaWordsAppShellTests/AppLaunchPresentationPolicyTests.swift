import Foundation
import XCTest

@testable import TadaWordsAppShell

@MainActor
final class AppLaunchPresentationPolicyTests: XCTestCase {
    func testLaunchPageWaitsNineTenthsOfASecond() {
        XCTAssertEqual(
            AppLaunchPresentationPolicy.minimumDisplayDuration,
            .milliseconds(900)
        )
    }

    func testLaunchPageUsesExistingQuickMotionToken() {
        XCTAssertEqual(
            AppLaunchPresentationPolicy.fadeDuration,
            0.16,
            accuracy: 0.001
        )
    }

    func testConfiguredSignatureStartsBeforeCountdownAndDismissal() async {
        var events: [String] = []
        var requestedDuration: Duration?
        let coordinator = AppLaunchPresentationCoordinator { duration in
            events.append("countdown")
            requestedDuration = duration
        }

        coordinator.startIfNeeded(
            prepare: {
                events.append("configured")
            },
            playSignature: {
                events.append("signature")
            }
        )

        await waitForDismissal(of: coordinator)

        XCTAssertEqual(events, ["configured", "signature", "countdown"])
        XCTAssertEqual(requestedDuration, .milliseconds(900))
        XCTAssertFalse(coordinator.isShowingLaunchPage)
    }

    func testDuplicateStartIsSuppressed() async {
        var events: [String] = []
        let coordinator = AppLaunchPresentationCoordinator { _ in
            events.append("countdown")
        }

        coordinator.startIfNeeded(
            prepare: {
                events.append("first configured")
            },
            playSignature: {
                events.append("first signature")
            }
        )
        coordinator.startIfNeeded(
            prepare: {
                events.append("duplicate configured")
            },
            playSignature: {
                events.append("duplicate signature")
            }
        )

        await waitForDismissal(of: coordinator)

        XCTAssertEqual(
            events,
            ["first configured", "first signature", "countdown"]
        )
        XCTAssertFalse(coordinator.isShowingLaunchPage)
    }

    func testSignatureTaskOutlivesLaunchPageDismissal() async {
        let signature = LaunchSignatureTaskProbe()
        let coordinator = AppLaunchPresentationCoordinator { _ in }

        coordinator.startIfNeeded(
            playSignature: {
                await signature.runUntilReleased()
            }
        )

        await waitForDismissal(of: coordinator)

        XCTAssertFalse(coordinator.isShowingLaunchPage)
        let isRunningAfterDismissal = signature.isRunning
        let hasFinishedAfterDismissal = signature.hasFinished
        XCTAssertTrue(isRunningAfterDismissal)
        XCTAssertFalse(hasFinishedAfterDismissal)

        signature.release()
        for _ in 0..<20 {
            if signature.hasFinished { break }
            await Task.yield()
        }
        let hasFinishedAfterRelease = signature.hasFinished
        XCTAssertTrue(hasFinishedAfterRelease)
    }

    private func waitForDismissal(
        of coordinator: AppLaunchPresentationCoordinator
    ) async {
        for _ in 0..<20 where coordinator.isShowingLaunchPage {
            await Task.yield()
        }
    }
}

@MainActor
private final class LaunchSignatureTaskProbe {
    private(set) var isRunning = false
    private(set) var hasFinished = false
    private var continuation: CheckedContinuation<Void, Never>?

    func runUntilReleased() async {
        isRunning = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        hasFinished = true
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
