import Foundation
import XCTest

@testable import TadaWordsDomain

final class VoiceprintTests: XCTestCase {
    func testMatchPolicyUsesConservativeUncertainMiddleBand() {
        let policy = VoiceprintMatchPolicy(
            likelyMatchThreshold: 0.8,
            possibleMismatchThreshold: 0.4
        )

        XCTAssertEqual(
            policy.signal(for: 0.9).targetSpeakerAssessment,
            .matched
        )
        XCTAssertEqual(
            policy.signal(for: 0.2).targetSpeakerAssessment,
            .mismatched
        )
        XCTAssertEqual(
            policy.signal(for: 0.6).targetSpeakerAssessment,
            .unavailable
        )
    }

    func testEmbeddingNormalizesAndComputesCosineSimilarity() throws {
        let first = try VoiceprintEmbedding(
            modelIdentifier: "alpha",
            vector: [3, 4]
        )
        let second = try VoiceprintEmbedding(
            modelIdentifier: "alpha",
            vector: [6, 8]
        )

        XCTAssertEqual(first.vector[0], 0.6, accuracy: 0.0001)
        XCTAssertEqual(first.vector[1], 0.8, accuracy: 0.0001)
        XCTAssertEqual(try first.cosineSimilarity(with: second), 1, accuracy: 0.0001)
    }

    func testEmbeddingRejectsInvalidAndIncompatibleVectors() throws {
        XCTAssertThrowsError(
            try VoiceprintEmbedding(modelIdentifier: "alpha", vector: [])
        )
        XCTAssertThrowsError(
            try VoiceprintEmbedding(
                modelIdentifier: "alpha",
                vector: [Float.nan]
            )
        )

        let first = try VoiceprintEmbedding(
            modelIdentifier: "alpha",
            vector: [1, 0]
        )
        let otherModel = try VoiceprintEmbedding(
            modelIdentifier: "beta",
            vector: [1, 0]
        )
        XCTAssertThrowsError(try first.cosineSimilarity(with: otherModel))
    }

    func testEnrollmentNeedsSeveralAcceptedSegmentsAndEnoughSpeech() throws {
        var session = try VoiceprintEnrollmentSession(
            profileID: ProfileID(),
            modelIdentifier: "alpha",
            policy: VoiceprintEnrollmentPolicy(
                minimumAcceptedSegments: 3,
                minimumAcceptedSpeechDuration: ElapsedTime(seconds: 6),
                minimumSegmentDuration: ElapsedTime(seconds: 1),
                maximumSegmentDuration: ElapsedTime(seconds: 3)
            )
        )

        let embedding = try VoiceprintEmbedding(
            modelIdentifier: "alpha",
            vector: [1, 0]
        )
        XCTAssertEqual(
            session.accept(
                embedding: embedding,
                speechDuration: ElapsedTime(seconds: 0.5)
            ),
            .tooShort
        )
        XCTAssertEqual(session.progress.rejectedSegmentCount, 1)

        for _ in 0..<3 {
            XCTAssertNil(
                session.accept(
                    embedding: embedding,
                    speechDuration: ElapsedTime(seconds: 2)
                )
            )
        }

        XCTAssertTrue(session.progress.isReadyToFinalize)
        let template = try session.makeTemplate(
            enrolledAt: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(template.acceptedSegmentCount, 3)
        XCTAssertEqual(template.acceptedSpeechDuration, ElapsedTime(seconds: 6))
        XCTAssertEqual(template.embedding, embedding)
    }

    func testEnrollmentRejectsMixedModelsAndDimensions() throws {
        var session = try VoiceprintEnrollmentSession(
            profileID: ProfileID(),
            modelIdentifier: "alpha"
        )
        let valid = try VoiceprintEmbedding(
            modelIdentifier: "alpha",
            vector: [1, 0]
        )
        let wrongModel = try VoiceprintEmbedding(
            modelIdentifier: "beta",
            vector: [1, 0]
        )
        let wrongDimension = try VoiceprintEmbedding(
            modelIdentifier: "alpha",
            vector: [1, 0, 0]
        )

        XCTAssertNil(
            session.accept(
                embedding: valid,
                speechDuration: ElapsedTime(seconds: 2.5)
            )
        )
        XCTAssertEqual(
            session.accept(
                embedding: wrongModel,
                speechDuration: ElapsedTime(seconds: 2.5)
            ),
            .modelMismatch
        )
        XCTAssertEqual(
            session.accept(
                embedding: wrongDimension,
                speechDuration: ElapsedTime(seconds: 2.5)
            ),
            .dimensionMismatch
        )
    }

    func testSpeakerConfidenceNeverBlocksLearning() {
        let signals: [SpeakerConfidenceSignal] = [
            .likelyMatch(RecognitionConfidence(0.9)),
            .possibleMismatch(RecognitionConfidence(0.9)),
            .unavailable,
        ]

        XCTAssertEqual(
            signals.map(\.targetSpeakerAssessment),
            [.matched, .mismatched, .unavailable]
        )
        XCTAssertTrue(signals.allSatisfy { !$0.canBlockLearning })
    }

    func testEnrollmentScriptHasSixUniqueShortSentences() {
        let sentences = VoiceprintEnrollmentScript.sentences

        XCTAssertEqual(sentences.count, 6)
        XCTAssertEqual(Set(sentences).count, sentences.count)
        XCTAssertTrue(sentences.allSatisfy { !$0.isEmpty && $0.count <= 32 })
        XCTAssertEqual(
            Set(VoiceprintEnrollmentScript.randomizedSentences()),
            Set(sentences)
        )
    }
}
