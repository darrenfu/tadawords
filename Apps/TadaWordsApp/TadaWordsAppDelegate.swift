import TadaWordsApplePlatform
import UIKit

@MainActor
final class TadaWordsAppDelegate: NSObject, UIApplicationDelegate {
    let interfaceOrientationController = AppleInterfaceOrientationController()

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
}
