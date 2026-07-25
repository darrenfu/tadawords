import Foundation
import SwiftUI
import TadaWordsAppShell
import TadaWordsApplePlatform
import TadaWordsContent
import TadaWordsDomain

@main
struct TadaWordsApp: App {
    @UIApplicationDelegateAdaptor(TadaWordsAppDelegate.self)
    private var appDelegate

    private let audioExperienceService: AppleAudioExperienceService
    private let audioPromptService: SystemAudioPromptService
    private let profileMutationGate: ProfileScopedMutationGate
    private let voiceprintRepository: ProfileMutationGatedDeviceVoiceprintRepository
    private let speechRecognitionService: AppleSpeechRecognitionService
    private let pictureHintProvider: AppleWordPictureHintService
    private let familySyncTransport: (any FamilySyncTransport)?
    private let familySyncAccessManagement: (@MainActor (ProfileID) async throws -> Void)?
    private let appClock: any AppClock
    private let appTimeZone: TimeZone
    private let notificationScheduler = AppleLearningNotificationScheduler()
    private let sensitiveActionAuthorizer = AppleSensitiveGuardianActionAuthorizer()
    private let handwritingRecognitionService = AppleHandwritingRecognitionService()
    private let imageTextRecognitionService = AppleImageTextRecognitionService()
    private let speechPermissionController = AppleSpeechPermissionController()

    init() {
        let experience = AppleAudioExperienceService()
        let mutationGate = ProfileScopedMutationGate()
        let baseVoiceprints: any DeviceVoiceprintRepository
        #if DEBUG && targetEnvironment(simulator) && !LOCAL_DEVICE_QA
            baseVoiceprints =
                FamilySyncSimulatorTestSupport.voiceprintRepository()
                ?? KeychainDeviceVoiceprintRepository()
        #else
            baseVoiceprints = KeychainDeviceVoiceprintRepository()
        #endif
        let voiceprints = ProfileMutationGatedDeviceVoiceprintRepository(
            base: baseVoiceprints,
            mutationGate: mutationGate
        )
        let teacherAudioCacheDirectory =
            ((try? Self.cachesDirectory())
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("TadaWords/teacher-audio", isDirectory: true)
        #if targetEnvironment(simulator) || LOCAL_DEVICE_QA
            // CKContainer traps when an intentionally unsigned simulator build
            // has no iCloud entitlement. Simulator and Local Device QA builds
            // use the AppShell's explicit device-only composition instead.
            #if DEBUG && targetEnvironment(simulator) && !LOCAL_DEVICE_QA
                familySyncTransport = FamilySyncSimulatorTestSupport.transport(
                    profileID: Self.defaultProfileID
                )
                familySyncAccessManagement = nil
                appClock =
                    FamilySyncSimulatorTestSupport.clock()
                    ?? SystemAppClock()
                appTimeZone =
                    FamilySyncSimulatorTestSupport.timeZone()
                    ?? .current
            #else
                familySyncTransport = nil
                familySyncAccessManagement = nil
                appClock = SystemAppClock()
                appTimeZone = .current
            #endif
        #else
            let transport = CloudKitFamilySyncTransport()
            let accessManager = CloudKitFamilyAccessManager(transport: transport)
            familySyncTransport = transport
            familySyncAccessManagement = { profileID in
                try await accessManager.presentAccessManagement(for: profileID)
            }
            appClock = SystemAppClock()
            appTimeZone = .current
        #endif
        audioExperienceService = experience
        profileMutationGate = mutationGate
        voiceprintRepository = voiceprints
        pictureHintProvider = AppleWordPictureHintService()
        audioPromptService = SystemAudioPromptService(
            audioExperienceService: experience,
            teacherWordAudioProvider: Self.teacherWordAudioProvider(
                cacheDirectory: teacherAudioCacheDirectory
            )
        )
        speechRecognitionService = AppleSpeechRecognitionService()
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
                    clock: appClock,
                    timeZone: appTimeZone,
                    audioPromptService: audioPromptService,
                    speechRecognitionService: speechRecognitionService,
                    handwritingRecognitionService: handwritingRecognitionService,
                    imageTextRecognitionService: imageTextRecognitionService,
                    pictureHintProvider: pictureHintProvider,
                    currentSpeechPermissionState: currentSpeechPermissionState,
                    requestSpeechPermissions: requestSpeechPermissions,
                    audioExperienceService: audioExperienceService,
                    familySyncTransport: familySyncTransport,
                    familySyncAccessManagement: familySyncAccessManagement,
                    notificationScheduler: notificationScheduler,
                    voiceprintEnrollmentService: nil,
                    voiceprintRepository: voiceprintRepository,
                    profileMutationGate: profileMutationGate,
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
        avatar: .cartoonAnimal(assetID: "rat"),
        selectedWorld: .moonpetalKingdom,
        createdAt: Date(timeIntervalSince1970: 1_735_689_600)
    )

    nonisolated private static let defaultProfileID: ProfileID = {
        #if DEBUG && targetEnvironment(simulator) && !LOCAL_DEVICE_QA
            // UI fixtures need one stable identity across deterministic
            // simulator launches. Physical and production installs must never
            // reuse a bundled child identity.
            guard
                let rawValue = UUID(
                    uuidString: "3B20FEF0-7E43-4B70-8F89-D37AD55454A1"
                )
            else {
                preconditionFailure("The simulator profile ID is invalid.")
            }
            return ProfileID(rawValue: rawValue)
        #else
            return ProfileID()
        #endif
    }()

    nonisolated private static func applicationSupportDirectory() throws -> URL {
        let systemDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        #if DEBUG && targetEnvironment(simulator) && !LOCAL_DEVICE_QA
            if let testDirectory =
                try FamilySyncSimulatorTestSupport
                .prepareApplicationSupportDirectory(
                    systemDirectory: systemDirectory,
                    profileID: defaultProfileID
                )
            {
                return testDirectory
            }
        #endif
        return systemDirectory
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

    private var currentSpeechPermissionState: @Sendable () async -> SpeechPermissionState {
        let controller = speechPermissionController
        return {
            await controller.currentState()
        }
    }

    private var requestSpeechPermissions: @Sendable () async -> SpeechPermissionState {
        let controller = speechPermissionController
        return {
            await controller.requestPermissions()
        }
    }
}
