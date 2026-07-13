import Foundation
import TadaWordsDomain
import TadaWordsGuardianFeatures

struct FirstRunOnboardingState: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case pending
        case completed
    }

    let schemaVersion: Int
    let status: Status
    let startedAt: Date
    let completedAt: Date?
    let profileID: ProfileID?
    let consentVersion: Int?
    let consentedAt: Date?

    static func pending(startedAt: Date) -> FirstRunOnboardingState {
        FirstRunOnboardingState(
            schemaVersion: 1,
            status: .pending,
            startedAt: startedAt,
            completedAt: nil,
            profileID: nil,
            consentVersion: nil,
            consentedAt: nil
        )
    }

    func completed(
        profileID: ProfileID,
        completedAt: Date,
        consentVersion: Int? = nil
    ) -> FirstRunOnboardingState {
        FirstRunOnboardingState(
            schemaVersion: schemaVersion,
            status: .completed,
            startedAt: startedAt,
            completedAt: completedAt,
            profileID: profileID,
            consentVersion: consentVersion,
            consentedAt: consentVersion == nil ? nil : completedAt
        )
    }
}

actor LocalFirstRunOnboardingRepository {
    let snapshotURL: URL

    init(snapshotURL: URL) {
        self.snapshotURL = snapshotURL
    }

    func state() throws -> FirstRunOnboardingState? {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            return nil
        }
        return try JSONDecoder().decode(
            FirstRunOnboardingState.self,
            from: Data(contentsOf: snapshotURL)
        )
    }

    func markPending(startedAt: Date) throws {
        if try state() != nil { return }
        try persist(.pending(startedAt: startedAt))
    }

    func markCompleted(
        profileID: ProfileID,
        completedAt: Date,
        consentVersion: Int? = nil
    ) throws {
        let current = try state() ?? .pending(startedAt: completedAt)
        try persist(
            current.completed(
                profileID: profileID,
                completedAt: completedAt,
                consentVersion: consentVersion
            )
        )
    }

    private func persist(_ state: FirstRunOnboardingState) throws {
        try FileManager.default.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: snapshotURL, options: .atomic)
    }
}

enum FirstRunOnboardingError: Error, Equatable {
    case consentRequired
    case profileNotFound
    case emptyDisplayName
    case displayNameTooLong(maximumCharacterCount: Int)
    case unsupportedAvatar
}

struct FirstRunOnboardingCompletion: Sendable {
    let profiles: [KidProfile]
    let selectedProfileID: ProfileID
}

struct FirstRunOnboardingSubmission: Sendable {
    static let currentConsentVersion = 1

    let profileDraft: GuardianProfileDraft
    let readWords: String
    let writeWords: String
    let consentVersion: Int

    init(
        profileDraft: GuardianProfileDraft,
        readWords: String,
        writeWords: String,
        consentVersion: Int = Self.currentConsentVersion
    ) {
        self.profileDraft = profileDraft
        self.readWords = readWords
        self.writeWords = writeWords
        self.consentVersion = consentVersion
    }
}

actor FirstRunOnboardingCoordinator {
    static let maximumDisplayNameCharacterCount = 24

    private let profileRepository: any KidProfileRepository
    private let childSessionRepository: any ChildSessionRepository
    private let onboardingRepository: LocalFirstRunOnboardingRepository
    private let guardianStore: any GuardianFamilyStore
    private let clock: any AppClock

    init(
        profileRepository: any KidProfileRepository,
        childSessionRepository: any ChildSessionRepository,
        onboardingRepository: LocalFirstRunOnboardingRepository,
        guardianStore: any GuardianFamilyStore,
        clock: any AppClock
    ) {
        self.profileRepository = profileRepository
        self.childSessionRepository = childSessionRepository
        self.onboardingRepository = onboardingRepository
        self.guardianStore = guardianStore
        self.clock = clock
    }

    func complete(
        profileID: ProfileID,
        submission: FirstRunOnboardingSubmission
    ) async throws -> FirstRunOnboardingCompletion {
        guard
            submission.consentVersion
                == FirstRunOnboardingSubmission.currentConsentVersion
        else {
            throw FirstRunOnboardingError.consentRequired
        }
        let draft = submission.profileDraft
        guard let existing = try await profileRepository.profile(id: profileID) else {
            throw FirstRunOnboardingError.profileNotFound
        }
        let displayName = draft.displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !displayName.isEmpty else {
            throw FirstRunOnboardingError.emptyDisplayName
        }
        guard displayName.count <= Self.maximumDisplayNameCharacterCount else {
            throw FirstRunOnboardingError.displayNameTooLong(
                maximumCharacterCount: Self.maximumDisplayNameCharacterCount
            )
        }
        guard case .cartoonAnimal(let assetID) = draft.avatar,
            GuardianAnimalAvatar.option(for: assetID) != nil
        else {
            // Camera and photo-library access are intentionally deferred until
            // the parent explicitly edits the profile later.
            throw FirstRunOnboardingError.unsupportedAvatar
        }

        let profile = KidProfile(
            id: existing.id,
            displayName: displayName,
            avatar: draft.avatar,
            selectedWorld: draft.selectedWorld,
            starterWorld: draft.selectedWorld,
            guardianUnlockedWorlds: [draft.selectedWorld],
            schoolGrade: draft.schoolGrade,
            ageYears: draft.ageYears,
            voiceprintStatus: existing.voiceprintStatus,
            createdAt: existing.createdAt,
            updatedAt: clock.now
        )

        // The completion marker is committed last. If the app is interrupted,
        // the flow reopens with the safely persisted profile instead of
        // exposing a half-configured child home.
        try await profileRepository.save(profile)
        try await childSessionRepository.saveLastSelectedProfileID(profile.id)
        _ = try await guardianStore.selectProfile(id: profile.id)
        try await importWordsIfPresent(
            submission.readWords,
            learningMode: .read
        )
        try await importWordsIfPresent(
            submission.writeWords,
            learningMode: .write
        )
        try await onboardingRepository.markCompleted(
            profileID: profile.id,
            completedAt: clock.now,
            consentVersion: submission.consentVersion
        )
        return FirstRunOnboardingCompletion(
            profiles: try await profileRepository.profiles(),
            selectedProfileID: profile.id
        )
    }

    private func importWordsIfPresent(
        _ rawText: String,
        learningMode: LearningMode
    ) async throws {
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        _ = try await guardianStore.importWords(
            GuardianWordImportRequest(
                rawText: rawText,
                learningMode: learningMode
            )
        )
    }
}
