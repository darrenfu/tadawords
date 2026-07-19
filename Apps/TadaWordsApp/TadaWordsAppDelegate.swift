import Network
import TadaWordsApplePlatform
import TadaWordsDomain
import UIKit

@MainActor
final class TadaWordsAppDelegate: NSObject, UIApplicationDelegate {
    let interfaceOrientationController = AppleInterfaceOrientationController()
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(
        label: "com.tadawords.family-sync.connectivity"
    )
    private var hasObservedUnsatisfiedPath = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        _ = launchOptions
        Task {
            await FamilySyncRemoteNotificationBridge.shared.configureRegistration(
                register: {
                    await MainActor.run {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                },
                unregister: {
                    await MainActor.run {
                        UIApplication.shared.unregisterForRemoteNotifications()
                    }
                }
            )
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let isSatisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.handlePathUpdate(isSatisfied: isSatisfied)
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        _ = application
        let idiom =
            window?.windowScene?.traitCollection.userInterfaceIdiom
            ?? UIDevice.current.userInterfaceIdiom
        return interfaceOrientationController.supportedOrientations(for: idiom)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler:
            @escaping (
                UIBackgroundFetchResult
            ) -> Void
    ) {
        _ = application
        _ = userInfo
        Task {
            let result = await FamilySyncRemoteNotificationBridge.shared
                .handleNotification()
            switch result {
            case .newData:
                completionHandler(.newData)
            case .noData:
                completionHandler(.noData)
            case .failed:
                completionHandler(.failed)
            }
        }
    }

    private func handlePathUpdate(isSatisfied: Bool) {
        guard isSatisfied else {
            hasObservedUnsatisfiedPath = true
            return
        }
        guard hasObservedUnsatisfiedPath else { return }
        hasObservedUnsatisfiedPath = false
        Task {
            await FamilySyncConnectivityRecoveryBridge.shared.handleRecovery()
        }
    }
}
