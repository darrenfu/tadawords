import Foundation
import SwiftUI
import TadaWordsAppShell
import TadaWordsApplePlatform
import TadaWordsDomain

@main
struct TadaWordsApp: App {
    private let audioExperienceService: AppleAudioExperienceService
    private let audioPromptService: SystemAudioPromptService
    private let voiceprintRepository: KeychainDeviceVoiceprintRepository
    private let speechRecognitionService: AppleSpeechRecognitionService
    private let voiceprintEnrollmentService: AppleVoiceprintEnrollmentService
    private let familySyncTransport: any FamilySyncTransport
    private let notificationScheduler = AppleLearningNotificationScheduler()
    private let sensitiveActionAuthorizer = AppleSensitiveGuardianActionAuthorizer()
    private let handwritingRecognitionService = AppleHandwritingRecognitionService()
    private let speechPermissionController = AppleSpeechPermissionController()

    init() {
        let experience = AppleAudioExperienceService()
        let voiceprints = KeychainDeviceVoiceprintRepository()
        #if targetEnvironment(simulator)
            // CKContainer traps when an intentionally unsigned simulator build
            // has no iCloud entitlement. Simulator QA remains local-first;
            // signed physical-device builds use the real CloudKit transport.
            familySyncTransport = SimulatorLocalOnlyFamilySyncTransport()
        #else
            familySyncTransport = CloudKitFamilySyncTransport()
        #endif
        audioExperienceService = experience
        voiceprintRepository = voiceprints
        voiceprintEnrollmentService = AppleVoiceprintEnrollmentService(
            repository: voiceprints
        )
        audioPromptService = SystemAudioPromptService(
            audioExperienceService: experience
        )
        speechRecognitionService = AppleSpeechRecognitionService(
            voiceprintVerifier: AppleVoiceprintVerifier(
                repository: voiceprints
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            if Self.isDemoModeEnabled {
                TadaWordsApplicationView(
                    audioPromptService: audioPromptService,
                    audioExperienceService: audioExperienceService,
                    demoMode: true
                )
            } else {
                TadaWordsApplicationView(
                    applicationSupportDirectory: Self.applicationSupportDirectory,
                    defaultProfile: Self.defaultProfile,
                    audioPromptService: audioPromptService,
                    speechRecognitionService: speechRecognitionService,
                    handwritingRecognitionService: handwritingRecognitionService,
                    requestSpeechAuthorization: requestSpeechAuthorization,
                    audioExperienceService: audioExperienceService,
                    familySyncTransport: familySyncTransport,
                    notificationScheduler: notificationScheduler,
                    voiceprintEnrollmentService: voiceprintEnrollmentService,
                    voiceprintRepository: voiceprintRepository,
                    sensitiveActionAuthorizer: sensitiveActionAuthorizer
                )
            }
        }
    }

    private static var isDemoModeEnabled: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("--demo-mode")
        #else
            false
        #endif
    }

    private static let defaultProfile = KidProfile(
        id: defaultProfileID,
        displayName: "My Kid",
        avatar: .cartoonAnimal(assetID: "hare"),
        selectedWorld: .moonpetalKingdom,
        createdAt: Date(timeIntervalSince1970: 1_735_689_600)
    )

    private static let defaultProfileID: ProfileID = {
        guard
            let rawValue = UUID(
                uuidString: "3B20FEF0-7E43-4B70-8F89-D37AD55454A1"
            )
        else {
            preconditionFailure("The bundled default profile ID is invalid.")
        }
        return ProfileID(rawValue: rawValue)
    }()

    nonisolated private static func applicationSupportDirectory() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    private var requestSpeechAuthorization: @Sendable () async -> Bool {
        let controller = speechPermissionController
        return {
            await controller.requestPermissions().isAuthorized
        }
    }
}

private actor SimulatorLocalOnlyFamilySyncTransport: FamilySyncTransport {
    func availability() async -> FamilySyncAvailability { .noAccount }

    func prepareProfileZone(_ profileID: ProfileID) async throws {
        _ = profileID
    }

    func fetchRecords(
        for profileID: ProfileID
    ) async throws -> [FamilySyncRecord] {
        _ = profileID
        return []
    }

    func push(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        _ = records
        _ = profileID
    }

    func createShare(for profileID: ProfileID) async throws -> URL {
        _ = profileID
        throw SimulatorFamilySyncError.unavailable
    }

    func acceptShare(at url: URL) async throws -> ProfileID {
        _ = url
        throw SimulatorFamilySyncError.unavailable
    }
}

private enum SimulatorFamilySyncError: Error {
    case unavailable
}
