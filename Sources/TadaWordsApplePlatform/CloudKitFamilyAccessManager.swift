#if canImport(CloudKit)
    @preconcurrency import CloudKit
    import Foundation
    import TadaWordsDomain

    public enum CloudKitFamilyAccessManagerError: Error, Sendable {
        case shareRecordUnavailable
        case presentationUnavailable
    }

    /// Keeps the owner recovery path testable without introducing a second
    /// share-creation policy. The transport remains authoritative for deciding
    /// whether an existing share is healthy, transiently unavailable, or
    /// confirmed missing and safe to recreate.
    @MainActor
    enum CloudKitFamilyAccessShareLoader {
        static func load(
            scope: CloudKitFamilyDatabaseScope,
            ensureOwnerShare: () async throws -> Void,
            fetchRoot: () async throws -> CKRecord,
            fetchRecord: (CKRecord.ID) async throws -> CKRecord
        ) async throws -> CKShare {
            if scope == .privateDatabase {
                try await ensureOwnerShare()
            }
            let root = try await fetchRoot()
            guard let shareRecordID = root.share?.recordID,
                let share = try await fetchRecord(shareRecordID) as? CKShare
            else {
                throw CloudKitFamilyAccessManagerError.shareRecordUnavailable
            }
            return share
        }
    }
#endif

#if canImport(CloudKit) && canImport(UIKit)
    import UIKit

    /// Presents Apple's existing-share management UI using the Profile's
    /// durable private-owner or shared-participant binding. Invitation
    /// creation remains in the sync transport so both entry points operate on
    /// the same CKShare and account-generation boundary.
    @MainActor
    public final class CloudKitFamilyAccessManager: NSObject,
        UICloudSharingControllerDelegate
    {
        private let transport: CloudKitFamilySyncTransport
        private let container: CKContainer
        private weak var activeController: UICloudSharingController?
        private var isPreparingController = false

        public init(
            transport: CloudKitFamilySyncTransport,
            containerIdentifier: String = "iCloud.com.tadawords.app"
        ) {
            self.transport = transport
            container = CKContainer(identifier: containerIdentifier)
        }

        public func presentAccessManagement(for profileID: ProfileID) async throws {
            guard activeController == nil, !isPreparingController else { return }
            isPreparingController = true
            defer { isPreparingController = false }

            let share = try await loadShare(for: profileID)
            guard let presenter = Self.topViewController() else {
                throw CloudKitFamilyAccessManagerError.presentationUnavailable
            }

            let controller = UICloudSharingController(
                share: share,
                container: container
            )
            controller.delegate = self
            controller.availablePermissions = [.allowPrivate, .allowReadWrite]
            controller.modalPresentationStyle = .formSheet
            if let popover = controller.popoverPresentationController {
                guard let sourceView = presenter.view else {
                    throw CloudKitFamilyAccessManagerError.presentationUnavailable
                }
                popover.sourceView = sourceView
                popover.sourceRect = CGRect(
                    x: sourceView.bounds.midX,
                    y: sourceView.bounds.midY,
                    width: 1,
                    height: 1
                )
                popover.permittedArrowDirections = []
            }
            activeController = controller
            presenter.present(controller, animated: true)
        }

        public func cloudSharingController(
            _ cloudSharingController: UICloudSharingController,
            failedToSaveShareWithError error: any Error
        ) {
            _ = error
            clearActiveController(ifMatching: cloudSharingController)
        }

        public func itemTitle(
            for cloudSharingController: UICloudSharingController
        ) -> String? {
            _ = cloudSharingController
            return "Tada Words family"
        }

        public func cloudSharingControllerDidSaveShare(
            _ cloudSharingController: UICloudSharingController
        ) {
            clearActiveController(ifMatching: cloudSharingController)
            reconcileShareChange()
        }

        public func cloudSharingControllerDidStopSharing(
            _ cloudSharingController: UICloudSharingController
        ) {
            clearActiveController(ifMatching: cloudSharingController)
            reconcileShareChange()
        }

        private func loadShare(for profileID: ProfileID) async throws -> CKShare {
            let location = try await transport.accessManagementLocation(
                for: profileID
            )
            let database: CKDatabase =
                switch location.scope {
                case .privateDatabase:
                    container.privateCloudDatabase
                case .sharedDatabase:
                    container.sharedCloudDatabase
                }
            return try await CloudKitFamilyAccessShareLoader.load(
                scope: location.scope,
                ensureOwnerShare: { [transport] in
                    _ = try await transport.createShare(for: profileID)
                },
                fetchRoot: {
                    try await database.record(for: location.rootRecordID)
                },
                fetchRecord: { recordID in
                    try await database.record(for: recordID)
                }
            )
        }

        private func clearActiveController(
            ifMatching controller: UICloudSharingController
        ) {
            guard activeController === controller else { return }
            activeController = nil
        }

        private func reconcileShareChange() {
            Task {
                _ = await FamilySyncRemoteNotificationBridge.shared
                    .handleNotification()
            }
        }

        private static func topViewController() -> UIViewController? {
            let root = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .rootViewController
            return topViewController(startingAt: root)
        }

        private static func topViewController(
            startingAt controller: UIViewController?
        ) -> UIViewController? {
            guard let controller else { return nil }
            if let presented = controller.presentedViewController,
                !presented.isBeingDismissed
            {
                return topViewController(startingAt: presented)
            }
            if let navigation = controller as? UINavigationController {
                return topViewController(
                    startingAt: navigation.visibleViewController
                )
            }
            if let tab = controller as? UITabBarController {
                return topViewController(startingAt: tab.selectedViewController)
            }
            return controller
        }
    }
#endif
