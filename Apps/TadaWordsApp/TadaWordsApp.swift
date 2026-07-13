import Foundation
import SwiftUI
import TadaWordsAppShell
import TadaWordsApplePlatform
import TadaWordsDomain

@main
struct TadaWordsApp: App {
    @UIApplicationDelegateAdaptor(TadaWordsAppDelegate.self)
    private var appDelegate

    private let audioExperienceService: AppleAudioExperienceService
    private let audioPromptService: SystemAudioPromptService
    private let voiceprintRepository: KeychainDeviceVoiceprintRepository
    private let speechRecognitionService: AppleSpeechRecognitionService
    private let voiceprintEnrollmentService: AppleVoiceprintEnrollmentService
    private let familySyncTransport: (any FamilySyncTransport)?
    private let notificationScheduler = AppleLearningNotificationScheduler()
    private let sensitiveActionAuthorizer = AppleSensitiveGuardianActionAuthorizer()
    private let handwritingRecognitionService = AppleHandwritingRecognitionService()
    private let imageTextRecognitionService = AppleImageTextRecognitionService()
    private let speechPermissionController = AppleSpeechPermissionController()

    init() {
        let experience = AppleAudioExperienceService()
        let voiceprints = KeychainDeviceVoiceprintRepository()
        #if targetEnvironment(simulator) || LOCAL_DEVICE_QA
            // CKContainer traps when an intentionally unsigned simulator build
            // has no iCloud entitlement. Simulator and Local Device QA builds
            // use the AppShell's explicit device-only composition instead.
            familySyncTransport = nil
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
                    interfaceOrientationController:
                        appDelegate.interfaceOrientationController,
                    demoMode: true
                )
            } else {
                TadaWordsApplicationView(
                    applicationSupportDirectory: Self.applicationSupportDirectory,
                    defaultProfile: Self.defaultProfile,
                    audioPromptService: audioPromptService,
                    speechRecognitionService: speechRecognitionService,
                    handwritingRecognitionService: handwritingRecognitionService,
                    imageTextRecognitionService: imageTextRecognitionService,
                    requestSpeechAuthorization: requestSpeechAuthorization,
                    audioExperienceService: audioExperienceService,
                    familySyncTransport: familySyncTransport,
                    notificationScheduler: notificationScheduler,
                    voiceprintEnrollmentService: voiceprintEnrollmentService,
                    voiceprintRepository: voiceprintRepository,
                    sensitiveActionAuthorizer: sensitiveActionAuthorizer,
                    interfaceOrientationController:
                        appDelegate.interfaceOrientationController
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
