import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

#if DEBUG
    final class DemoSpeechRecognitionServiceTests: XCTestCase {
        func testDemoWaitsUsingHumanPerceptibleDefaultDelay() async throws {
            let recorder = DelayRecorder()
            let service = DemoSpeechRecognitionService { duration in
                await recorder.record(duration)
            }

            let result = try await service.recognize(makeRequest())
            let durations = await recorder.recordedDurations()

            XCTAssertEqual(
                durations,
                [DemoSpeechRecognitionService.defaultDelay]
            )
            XCTAssertEqual(
                DemoSpeechRecognitionService.defaultDelay,
                .milliseconds(1_500)
            )
            XCTAssertEqual(result.decision, .matched)
            XCTAssertEqual(result.recognizedText, "look")
        }

        func testDemoDelayIsCancellationSafe() async throws {
            let service = DemoSpeechRecognitionService()
            let request = try makeRequest()
            let task = Task {
                try await service.recognize(request)
            }

            await Task.yield()
            task.cancel()

            do {
                _ = try await task.value
                XCTFail("A cancelled simulated recording must not succeed.")
            } catch is CancellationError {
                // Expected. Task.sleep propagates structured cancellation.
            }
        }

        private func makeRequest() throws -> SpeechRecognitionRequest {
            SpeechRecognitionRequest(
                profileID: ProfileID(),
                prompt: try WordPrompt(learningMode: .read, text: "look"),
                maximumRecordingDuration: ElapsedTime(seconds: 5)
            )
        }
    }

    private actor DelayRecorder {
        private var durations: [Duration] = []

        func record(_ duration: Duration) {
            durations.append(duration)
        }

        func recordedDurations() -> [Duration] {
            durations
        }
    }
#endif
