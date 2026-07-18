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
    private let pictureHintProvider: AppleWordPictureHintService
    private let familySyncTransport: (any FamilySyncTransport)?
    private let notificationScheduler = AppleLearningNotificationScheduler()
    private let sensitiveActionAuthorizer = AppleSensitiveGuardianActionAuthorizer()
    private let handwritingRecognitionService = AppleHandwritingRecognitionService()
    private let imageTextRecognitionService = AppleImageTextRecognitionService()
    private let speechPermissionController = AppleSpeechPermissionController()

    init() {
        let experience = AppleAudioExperienceService()
        let voiceprints = KeychainDeviceVoiceprintRepository()
        let teacherAudioCacheDirectory =
            ((try? Self.cachesDirectory())
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("TadaWords/teacher-audio", isDirectory: true)
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
        pictureHintProvider = AppleWordPictureHintService()
        voiceprintEnrollmentService = AppleVoiceprintEnrollmentService(
            repository: voiceprints,
            audioExperienceService: experience
        )
        audioPromptService = SystemAudioPromptService(
            audioExperienceService: experience,
            teacherWordAudioProvider: Self.teacherWordAudioProvider(
                cacheDirectory: teacherAudioCacheDirectory
            )
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
                    pictureHintProvider: pictureHintProvider,
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

    nonisolated private static func cachesDirectory() throws -> URL {
        try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    /// The versioned Katie pack is always first. The optional public app backend
    /// fills future pack misses, and Apple en-US TTS remains the final offline
    /// fallback. No Cartesia credential is present in the app.
    private static func teacherWordAudioProvider(
        cacheDirectory: URL,
        bundle: Bundle = .main
    ) -> (any TeacherWordAudioProviding)? {
        var providers: [any TeacherWordAudioProviding] = []
        if let bundled = BundledTeacherWordAudioProvider.production() {
            providers.append(bundled)
        }

        if let rawEndpoint = bundle.object(
            forInfoDictionaryKey: "TadaWordsTeacherAudioEndpoint"
        ) as? String,
            let endpoint = URL(string: rawEndpoint),
            endpoint.scheme?.lowercased() == "https"
        {
            providers.append(
                CachingTeacherWordAudioProvider(
                    upstream: RemoteTeacherWordAudioProvider(endpoint: endpoint),
                    cache: FileTeacherWordAudioCache(directory: cacheDirectory)
                )
            )
        }

        guard !providers.isEmpty else { return nil }
        return FirstAvailableTeacherWordAudioProvider(providers: providers)
    }

    private var requestSpeechAuthorization: @Sendable () async -> Bool {
        let controller = speechPermissionController
        return {
            await controller.requestPermissions().isAuthorized
        }
    }
}
