import Foundation
import TadaWordsContent
import TadaWordsDomain

public enum ProductionUITestFixture: String, Codable, Equatable, Sendable {
    case parentKid = "parent-kid"

    public var profile: KidProfile {
        switch self {
        case .parentKid:
            KidProfile(
                id: Self.parentKidProfileID,
                displayName: "Mia",
                avatar: .cartoonAnimal(assetID: "hare"),
                selectedWorld: .moonpetalKingdom,
                schoolGrade: .preK,
                ageYears: 4,
                createdAt: Self.referenceDate
            )
        }
    }

    public var readWords: [String] {
        switch self {
        case .parentKid:
            ["apple", "moon", "tree"]
        }
    }

    public var writeWords: [String] {
        switch self {
        case .parentKid:
            ["dog", "map", "sun"]
        }
    }

    public var practiceSettings: ProfilePracticeSettings {
        ProfilePracticeSettings(
            profileID: profile.id,
            read: LearningRouteSettings(
                newWordLimit: readWords.count,
                reviewWordLimit: 0,
                contentOrder: .newThenReview,
                emergencyAfterSeconds: 60
            ),
            write: LearningRouteSettings(
                newWordLimit: writeWords.count,
                reviewWordLimit: 0,
                contentOrder: .newThenReview,
                emergencyAfterSeconds: 60
            )
        )
    }

    public var clock: any AppClock {
        ProductionUITestClock(now: Self.referenceDate)
    }

    public var timeZone: TimeZone {
        TimeZone(secondsFromGMT: 0) ?? .current
    }

    private static let referenceDate = Date(timeIntervalSince1970: 1_735_689_600)

    private static let parentKidProfileID: ProfileID = {
        guard
            let value = UUID(
                uuidString: "7B6CF84F-6E7C-4CD3-9FA7-6930AF6A9A01"
            )
        else {
            preconditionFailure("The Parent/Kid UI-test profile ID is invalid.")
        }
        return ProfileID(rawValue: value)
    }()
}

public struct ProductionUITestClock: AppClock, Equatable, Sendable {
    public let now: Date

    public init(now: Date) {
        self.now = now
    }
}

public struct ProductionUITestLaunchConfiguration: Equatable, Sendable {
    public static let productionFlag = "--ui-testing-production"
    public static let resetFlag = "--ui-testing-reset"

    public let fixture: ProductionUITestFixture
    public let runID: String
    public let resetsRunDirectory: Bool

    public init(
        fixture: ProductionUITestFixture,
        runID: String,
        resetsRunDirectory: Bool
    ) {
        self.fixture = fixture
        self.runID = runID
        self.resetsRunDirectory = resetsRunDirectory
    }

    public func applicationSupportDirectory(in baseDirectory: URL) -> URL {
        baseDirectory
            .appendingPathComponent("UITests", isDirectory: true)
            .appendingPathComponent(runID, isDirectory: true)
    }

    public static func resolve(
        arguments: [String],
        localDeviceQAEnabled: Bool
    ) -> ProductionUITestLaunchResolution {
        let productionFlagCount = arguments.filter { $0 == productionFlag }.count
        guard productionFlagCount > 0 else { return .notRequested }
        guard localDeviceQAEnabled, productionFlagCount == 1 else {
            return .rejected
        }

        let fixtureValues = values(for: "--ui-testing-fixture=", in: arguments)
        let runIDValues = values(for: "--ui-testing-run-id=", in: arguments)
        let resetCount = arguments.filter { $0 == resetFlag }.count
        guard fixtureValues.count == 1,
            runIDValues.count == 1,
            resetCount <= 1,
            let fixture = ProductionUITestFixture(rawValue: fixtureValues[0]),
            let runID = sanitizedRunID(runIDValues[0])
        else {
            return .rejected
        }

        return .enabled(
            ProductionUITestLaunchConfiguration(
                fixture: fixture,
                runID: runID,
                resetsRunDirectory: resetCount == 1
            )
        )
    }

    private static func values(
        for prefix: String,
        in arguments: [String]
    ) -> [String] {
        arguments.compactMap { argument in
            guard argument.hasPrefix(prefix) else { return nil }
            return String(argument.dropFirst(prefix.count))
        }
    }

    private static func sanitizedRunID(_ rawValue: String) -> String? {
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
        )
        var result = ""
        var needsSeparator = false

        for scalar in rawValue.unicodeScalars {
            if allowed.contains(scalar) {
                if needsSeparator, !result.isEmpty, !result.hasSuffix("-") {
                    result.append("-")
                }
                result.unicodeScalars.append(scalar)
                needsSeparator = false
            } else if !result.isEmpty {
                needsSeparator = true
            }
        }

        let sanitized = String(result.prefix(96))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return sanitized.isEmpty ? nil : sanitized
    }
}

public enum ProductionUITestLaunchResolution: Equatable, Sendable {
    case notRequested
    case enabled(ProductionUITestLaunchConfiguration)
    case rejected
}

public enum ProductionUITestLaunchError: Error, Equatable, Sendable {
    case rejectedArguments
    case unmarkedDataDirectoryNotEmpty
    case invalidFixtureMarker
}

public final class ProductionUITestApplicationSupportDirectoryProvider:
    @unchecked Sendable
{
    private let configuration: ProductionUITestLaunchConfiguration
    private let baseDirectory: @Sendable () throws -> URL
    private let lock = NSLock()
    private var preparationResult: Result<URL, any Error>?

    public init(
        configuration: ProductionUITestLaunchConfiguration,
        baseDirectory: @escaping @Sendable () throws -> URL
    ) {
        self.configuration = configuration
        self.baseDirectory = baseDirectory
    }

    public func directory() throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        if let preparationResult {
            return try preparationResult.get()
        }

        do {
            let directory = configuration.applicationSupportDirectory(
                in: try baseDirectory()
            )
            if configuration.resetsRunDirectory,
                FileManager.default.fileExists(atPath: directory.path)
            {
                try FileManager.default.removeItem(at: directory)
            }
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            preparationResult = .success(directory)
            return directory
        } catch {
            preparationResult = .failure(error)
            throw error
        }
    }
}

struct ProductionUITestFixtureBootstrapper: ApplicationBootstrapping, Sendable {
    private let fixtureSeeder: ProductionUITestFixtureSeeder
    private let productionBootstrapper: ProductionApplicationBootstrapper

    init(
        fixture: ProductionUITestFixture,
        applicationSupportDirectory: @escaping @Sendable () throws -> URL,
        productionBootstrapper: ProductionApplicationBootstrapper
    ) {
        fixtureSeeder = ProductionUITestFixtureSeeder(
            fixture: fixture,
            applicationSupportDirectory: applicationSupportDirectory
        )
        self.productionBootstrapper = productionBootstrapper
    }

    func bootstrap() async throws -> ProductionApplicationEnvironment {
        try await fixtureSeeder.seedIfNeeded()
        return try await productionBootstrapper.bootstrap()
    }
}

struct ProductionUITestFixtureSeeder: Sendable {
    private static let markerFileName = "production-ui-test-fixture.json"
    private static let schemaVersion = 1

    private let fixture: ProductionUITestFixture
    private let applicationSupportDirectory: @Sendable () throws -> URL

    init(
        fixture: ProductionUITestFixture,
        applicationSupportDirectory: @escaping @Sendable () throws -> URL
    ) {
        self.fixture = fixture
        self.applicationSupportDirectory = applicationSupportDirectory
    }

    func seedIfNeeded() async throws {
        let paths = ApplicationDataPaths(
            applicationSupportDirectory: try applicationSupportDirectory()
        )
        let markerURL = paths.dataDirectory.appendingPathComponent(
            Self.markerFileName,
            isDirectory: false
        )

        if FileManager.default.fileExists(atPath: markerURL.path) {
            let marker = try JSONDecoder().decode(
                FixtureMarker.self,
                from: Data(contentsOf: markerURL)
            )
            guard marker.schemaVersion == Self.schemaVersion,
                marker.fixture == fixture
            else {
                throw ProductionUITestLaunchError.invalidFixtureMarker
            }
            return
        }

        if FileManager.default.fileExists(atPath: paths.dataDirectory.path),
            !((try? FileManager.default.contentsOfDirectory(
                at: paths.dataDirectory,
                includingPropertiesForKeys: nil
            )) ?? []).isEmpty
        {
            throw ProductionUITestLaunchError.unmarkedDataDirectoryNotEmpty
        }

        let profileRepository = LocalJSONKidProfileRepository(
            snapshotURL: paths.profilesSnapshot
        )
        let wordPoolRepository = LocalJSONWordPoolRepository(
            snapshotURL: paths.wordPoolSnapshot
        )
        let settingsRepository = LocalJSONPracticeSettingsRepository(
            snapshotURL: paths.practiceSettingsSnapshot
        )
        let childSessionRepository = LocalJSONChildSessionRepository(
            snapshotURL: paths.childSessionSnapshot
        )
        let onboardingRepository = LocalFirstRunOnboardingRepository(
            snapshotURL: paths.firstRunOnboardingSnapshot
        )
        let profile = fixture.profile

        try await profileRepository.save(profile)
        let importer = ManualWordPoolImporter(repository: wordPoolRepository)
        _ = try await importer.importBatch(
            fixture.readWords.joined(separator: "\n"),
            profileID: profile.id,
            learningMode: .read,
            addedAt: profile.createdAt,
            source: .guardianManual
        )
        _ = try await importer.importBatch(
            fixture.writeWords.joined(separator: "\n"),
            profileID: profile.id,
            learningMode: .write,
            addedAt: profile.createdAt,
            source: .guardianManual
        )
        try await settingsRepository.save(fixture.practiceSettings)
        try await childSessionRepository.saveLastSelectedProfileID(profile.id)
        try await onboardingRepository.markCompleted(
            profileID: profile.id,
            completedAt: profile.createdAt,
            consentVersion: FirstRunOnboardingSubmission.currentConsentVersion
        )

        try FileManager.default.createDirectory(
            at: paths.dataDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(
            FixtureMarker(
                schemaVersion: Self.schemaVersion,
                fixture: fixture
            )
        ).write(to: markerURL, options: .atomic)
    }

    private struct FixtureMarker: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let fixture: ProductionUITestFixture
    }
}

public struct ProductionUITestSpeechRecognitionService:
    SpeechRecognitionService,
    Sendable
{
    public init() {}

    public func recognize(
        _ request: SpeechRecognitionRequest
    ) async throws -> RecognitionResult {
        RecognitionResult(
            decision: .matched,
            recognizedText: request.prompt.normalizedText,
            confidence: RecognitionConfidence(1),
            targetSpeakerAssessment: .matched
        )
    }
}

public struct ProductionUITestHandwritingRecognitionService:
    HandwritingRecognitionService,
    Sendable
{
    public init() {}

    public func recognize(
        sample: HandwritingSample,
        prompt: WordPrompt,
        for profileID: ProfileID
    ) async throws -> RecognitionResult {
        _ = profileID
        guard !sample.strokes.isEmpty else {
            return RecognitionResult(
                decision: .technicalFailure(.corruptedInput)
            )
        }
        return RecognitionResult(
            decision: .matched,
            recognizedText: prompt.normalizedText,
            confidence: RecognitionConfidence(1)
        )
    }
}

public struct ProductionUITestImageTextRecognitionService:
    ImageTextRecognizing,
    Sendable
{
    public static let words = ["cat", "read", "bow", "to"]

    public init() {}

    public func recognizeText(in imageData: Data) async throws -> [String] {
        guard !imageData.isEmpty else {
            throw ImageTextRecognitionError.invalidImage
        }
        return [Self.words.joined(separator: " ")]
    }
}

public actor ProductionUITestVoiceprintRepository: DeviceVoiceprintRepository {
    private var templates: [ProfileID: DeviceVoiceprintTemplate] = [:]

    public init() {}

    public func template(
        for profileID: ProfileID
    ) async throws -> DeviceVoiceprintTemplate? {
        templates[profileID]
    }

    public func save(_ template: DeviceVoiceprintTemplate) async throws {
        templates[template.profileID] = template
    }

    public func delete(for profileID: ProfileID) async throws {
        templates[profileID] = nil
    }
}

public actor ProductionUITestVoiceprintEnrollmentService:
    DeviceVoiceprintEnrolling
{
    private static let modelIdentifier = "localqa-ui-test-v1"

    private let repository: any DeviceVoiceprintRepository
    private let clock: any AppClock
    private var session: VoiceprintEnrollmentSession?

    public init(
        repository: any DeviceVoiceprintRepository,
        clock: any AppClock
    ) {
        self.repository = repository
        self.clock = clock
    }

    public func begin(
        profileID: ProfileID
    ) async throws -> VoiceprintEnrollmentProgress {
        let session = try VoiceprintEnrollmentSession(
            profileID: profileID,
            modelIdentifier: Self.modelIdentifier
        )
        self.session = session
        return session.progress
    }

    public func captureSegment() async throws -> VoiceprintEnrollmentStepResult {
        guard var session else {
            throw VoiceprintValidationError.enrollmentNotReady
        }
        let embedding = try VoiceprintEmbedding(
            modelIdentifier: Self.modelIdentifier,
            vector: [1, 0, 0, 0]
        )
        while !session.progress.isReadyToFinalize {
            _ = session.accept(
                embedding: embedding,
                speechDuration: ElapsedTime(seconds: 3)
            )
        }
        self.session = session
        return VoiceprintEnrollmentStepResult(
            progress: session.progress,
            rejectionReason: nil
        )
    }

    public func finalize() async throws -> DeviceVoiceprintTemplate {
        guard let session else {
            throw VoiceprintValidationError.enrollmentNotReady
        }
        let template = try session.makeTemplate(enrolledAt: clock.now)
        try await repository.save(template)
        self.session = nil
        return template
    }

    public func cancel() async {
        session = nil
    }
}
