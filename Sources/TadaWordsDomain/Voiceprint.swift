import Foundation

/// A device-local speaker embedding. Raw microphone audio is deliberately not
/// represented by this domain type and must never cross the platform-adapter
/// boundary as durable data.
public struct VoiceprintEmbedding: Codable, Hashable, Sendable {
    public let modelIdentifier: String
    public let vector: [Float]

    public init(
        modelIdentifier: String,
        vector: [Float]
    ) throws {
        let normalizedIdentifier = modelIdentifier.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedIdentifier.isEmpty else {
            throw VoiceprintValidationError.missingModelIdentifier
        }
        guard !vector.isEmpty else {
            throw VoiceprintValidationError.emptyEmbedding
        }
        guard vector.count <= 4_096 else {
            throw VoiceprintValidationError.embeddingTooLarge(vector.count)
        }
        guard vector.allSatisfy(\.isFinite) else {
            throw VoiceprintValidationError.nonFiniteEmbedding
        }

        let squaredMagnitude = vector.reduce(Float.zero) { partial, value in
            partial + value * value
        }
        guard squaredMagnitude.isFinite, squaredMagnitude > 0 else {
            throw VoiceprintValidationError.zeroMagnitudeEmbedding
        }

        let magnitude = squaredMagnitude.squareRoot()
        self.modelIdentifier = normalizedIdentifier
        self.vector = vector.map { $0 / magnitude }
    }

    public func cosineSimilarity(with other: VoiceprintEmbedding) throws -> Double {
        guard modelIdentifier == other.modelIdentifier else {
            throw VoiceprintValidationError.modelMismatch(
                expected: modelIdentifier,
                found: other.modelIdentifier
            )
        }
        guard vector.count == other.vector.count else {
            throw VoiceprintValidationError.dimensionMismatch(
                expected: vector.count,
                found: other.vector.count
            )
        }

        return zip(vector, other.vector).reduce(0) { partial, pair in
            partial + Double(pair.0 * pair.1)
        }
    }
}

public enum VoiceprintValidationError: Error, Equatable, Sendable {
    case missingModelIdentifier
    case emptyEmbedding
    case embeddingTooLarge(Int)
    case nonFiniteEmbedding
    case zeroMagnitudeEmbedding
    case modelMismatch(expected: String, found: String)
    case dimensionMismatch(expected: Int, found: Int)
    case enrollmentNotReady
}

/// The only persistent voiceprint artifact. It contains a normalized embedding
/// centroid and enrollment metadata, never a recording or transcript.
public struct DeviceVoiceprintTemplate: Codable, Hashable, Sendable {
    public let profileID: ProfileID
    public let embedding: VoiceprintEmbedding
    public let acceptedSegmentCount: Int
    public let acceptedSpeechDuration: ElapsedTime
    public let enrolledAt: Date

    public init(
        profileID: ProfileID,
        embedding: VoiceprintEmbedding,
        acceptedSegmentCount: Int,
        acceptedSpeechDuration: ElapsedTime,
        enrolledAt: Date
    ) {
        self.profileID = profileID
        self.embedding = embedding
        self.acceptedSegmentCount = max(1, acceptedSegmentCount)
        self.acceptedSpeechDuration = acceptedSpeechDuration
        self.enrolledAt = enrolledAt
    }
}

/// Voiceprints are intentionally device-scoped. A CloudKit or server-backed
/// implementation must not conform to this contract.
public protocol DeviceVoiceprintRepository: Sendable {
    func template(for profileID: ProfileID) async throws -> DeviceVoiceprintTemplate?

    func save(_ template: DeviceVoiceprintTemplate) async throws

    func delete(for profileID: ProfileID) async throws
}

/// Generates a compact acoustic signature entirely in memory. Implementations
/// must not retain or persist the source PCM samples.
public protocol VoiceprintEmbeddingExtracting: Sendable {
    var modelIdentifier: String { get }

    func embedding(
        from samples: [Float],
        sampleRate: Double
    ) throws -> VoiceprintEmbedding
}

public struct VoiceprintMatchPolicy: Equatable, Sendable {
    public let likelyMatchThreshold: Double
    public let possibleMismatchThreshold: Double

    public init(
        likelyMatchThreshold: Double = 0.78,
        possibleMismatchThreshold: Double = 0.42
    ) {
        let match = min(1, max(-1, likelyMatchThreshold))
        self.likelyMatchThreshold = match
        self.possibleMismatchThreshold = min(
            match,
            max(-1, possibleMismatchThreshold)
        )
    }

    public func signal(for similarity: Double) -> SpeakerConfidenceSignal {
        let confidence = RecognitionConfidence((similarity + 1) / 2)
        if similarity >= likelyMatchThreshold {
            return .likelyMatch(confidence)
        }
        if similarity <= possibleMismatchThreshold {
            return .possibleMismatch(confidence)
        }
        return .unavailable
    }
}

public struct VoiceprintEnrollmentPolicy: Equatable, Sendable {
    public let minimumAcceptedSegments: Int
    public let minimumAcceptedSpeechDuration: ElapsedTime
    public let minimumSegmentDuration: ElapsedTime
    public let maximumSegmentDuration: ElapsedTime

    public init(
        minimumAcceptedSegments: Int = 6,
        minimumAcceptedSpeechDuration: ElapsedTime = ElapsedTime(seconds: 15),
        minimumSegmentDuration: ElapsedTime = ElapsedTime(seconds: 1.5),
        maximumSegmentDuration: ElapsedTime = ElapsedTime(seconds: 5)
    ) {
        self.minimumAcceptedSegments = max(2, minimumAcceptedSegments)
        self.minimumAcceptedSpeechDuration = minimumAcceptedSpeechDuration
        self.minimumSegmentDuration = minimumSegmentDuration
        self.maximumSegmentDuration = max(
            minimumSegmentDuration,
            maximumSegmentDuration
        )
    }

    public static let oneMinuteRegistration = VoiceprintEnrollmentPolicy()
}

public enum VoiceprintSegmentRejectionReason: String, Codable, CaseIterable,
    Hashable, Sendable
{
    case noSpeech
    case tooShort
    case tooLong
    case tooNoisy
    case multipleSpeakers
    case modelMismatch
    case dimensionMismatch
    case technicalFailure
}

public struct VoiceprintEnrollmentProgress: Equatable, Sendable {
    public let acceptedSegmentCount: Int
    public let acceptedSpeechDuration: ElapsedTime
    public let rejectedSegmentCount: Int
    public let isReadyToFinalize: Bool
}

public struct VoiceprintEnrollmentStepResult: Equatable, Sendable {
    public let progress: VoiceprintEnrollmentProgress
    public let rejectionReason: VoiceprintSegmentRejectionReason?

    public init(
        progress: VoiceprintEnrollmentProgress,
        rejectionReason: VoiceprintSegmentRejectionReason?
    ) {
        self.progress = progress
        self.rejectionReason = rejectionReason
    }
}

public protocol DeviceVoiceprintEnrolling: Sendable {
    func begin(profileID: ProfileID) async throws -> VoiceprintEnrollmentProgress

    func captureSegment() async throws -> VoiceprintEnrollmentStepResult

    func finalize() async throws -> DeviceVoiceprintTemplate

    func cancel() async
}

public struct VoiceprintEnrollmentSession: Sendable {
    public let profileID: ProfileID
    public let modelIdentifier: String
    public let policy: VoiceprintEnrollmentPolicy

    private var acceptedEmbeddings: [VoiceprintEmbedding]
    private var acceptedSpeechDuration: ElapsedTime
    private var rejectedSegmentCount: Int

    public init(
        profileID: ProfileID,
        modelIdentifier: String,
        policy: VoiceprintEnrollmentPolicy = .oneMinuteRegistration
    ) throws {
        let normalizedIdentifier = modelIdentifier.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedIdentifier.isEmpty else {
            throw VoiceprintValidationError.missingModelIdentifier
        }

        self.profileID = profileID
        self.modelIdentifier = normalizedIdentifier
        self.policy = policy
        acceptedEmbeddings = []
        acceptedSpeechDuration = .zero
        rejectedSegmentCount = 0
    }

    public var progress: VoiceprintEnrollmentProgress {
        VoiceprintEnrollmentProgress(
            acceptedSegmentCount: acceptedEmbeddings.count,
            acceptedSpeechDuration: acceptedSpeechDuration,
            rejectedSegmentCount: rejectedSegmentCount,
            isReadyToFinalize: acceptedEmbeddings.count
                >= policy.minimumAcceptedSegments
                && acceptedSpeechDuration >= policy.minimumAcceptedSpeechDuration
        )
    }

    /// Records only an embedding and its speech duration. The platform adapter
    /// must dispose of the in-memory PCM buffer before returning this value.
    @discardableResult
    public mutating func accept(
        embedding: VoiceprintEmbedding,
        speechDuration: ElapsedTime
    ) -> VoiceprintSegmentRejectionReason? {
        guard speechDuration >= policy.minimumSegmentDuration else {
            return reject(.tooShort)
        }
        guard speechDuration <= policy.maximumSegmentDuration else {
            return reject(.tooLong)
        }
        guard embedding.modelIdentifier == modelIdentifier else {
            return reject(.modelMismatch)
        }
        if let expectedDimension = acceptedEmbeddings.first?.vector.count,
            embedding.vector.count != expectedDimension
        {
            return reject(.dimensionMismatch)
        }

        acceptedEmbeddings.append(embedding)
        acceptedSpeechDuration = ElapsedTime(
            seconds: acceptedSpeechDuration.seconds + speechDuration.seconds
        )
        return nil
    }

    @discardableResult
    public mutating func reject(
        _ reason: VoiceprintSegmentRejectionReason
    ) -> VoiceprintSegmentRejectionReason {
        rejectedSegmentCount += 1
        return reason
    }

    public func makeTemplate(enrolledAt: Date) throws -> DeviceVoiceprintTemplate {
        guard progress.isReadyToFinalize, let first = acceptedEmbeddings.first else {
            throw VoiceprintValidationError.enrollmentNotReady
        }

        var centroid = [Float](repeating: 0, count: first.vector.count)
        for embedding in acceptedEmbeddings {
            for index in centroid.indices {
                centroid[index] += embedding.vector[index]
            }
        }

        let divisor = Float(acceptedEmbeddings.count)
        let averaged = centroid.map { $0 / divisor }
        let templateEmbedding = try VoiceprintEmbedding(
            modelIdentifier: modelIdentifier,
            vector: averaged
        )

        return DeviceVoiceprintTemplate(
            profileID: profileID,
            embedding: templateEmbedding,
            acceptedSegmentCount: acceptedEmbeddings.count,
            acceptedSpeechDuration: acceptedSpeechDuration,
            enrolledAt: enrolledAt
        )
    }
}

/// Speaker identity is supporting evidence only. Even a possible mismatch must
/// route to a technical retry, never to an incorrect learning result.
public enum SpeakerConfidenceSignal: Equatable, Sendable {
    case likelyMatch(RecognitionConfidence)
    case possibleMismatch(RecognitionConfidence)
    case unavailable

    public var targetSpeakerAssessment: TargetSpeakerAssessment {
        switch self {
        case .likelyMatch:
            .matched
        case .possibleMismatch:
            .mismatched
        case .unavailable:
            .unavailable
        }
    }

    public var canBlockLearning: Bool { false }
}
