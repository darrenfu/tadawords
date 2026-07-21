#if os(iOS)
    import SwiftUI
    import UIKit

    /// Presents Apple's portrait-only camera as the topmost full-screen UIKit
    /// controller instead of embedding it inside a landscape SwiftUI host.
    @MainActor
    struct GuardianSystemCameraPicker: UIViewControllerRepresentable {
        let onImage: (UIImage) -> Void
        let onCancel: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(onImage: onImage, onCancel: onCancel)
        }

        func makeUIViewController(context: Context) -> PresentationController {
            let controller = PresentationController()
            controller.onReady = { [weak coordinator = context.coordinator] presenter in
                coordinator?.presentCamera(from: presenter)
            }
            return controller
        }

        func updateUIViewController(
            _ uiViewController: PresentationController,
            context: Context
        ) {}

        final class PresentationController: UIViewController {
            var onReady: ((UIViewController) -> Void)?
            private var hasPresentedCamera = false

            override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
                .portrait
            }

            override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
                .portrait
            }

            override func viewDidLoad() {
                super.viewDidLoad()
                view.backgroundColor = .black
            }

            override func viewWillAppear(_ animated: Bool) {
                super.viewWillAppear(animated)
                requestPortraitGeometry()
            }

            override func viewDidAppear(_ animated: Bool) {
                super.viewDidAppear(animated)
                requestPortraitGeometry()
                guard !hasPresentedCamera else { return }
                hasPresentedCamera = true
                onReady?(self)
            }

            private func requestPortraitGeometry() {
                setNeedsUpdateOfSupportedInterfaceOrientations()
                view.window?.windowScene?.requestGeometryUpdate(
                    .iOS(interfaceOrientations: .portrait)
                ) { _ in
                    // The stock picker remains portrait-only even if the scene
                    // temporarily refuses a geometry request during presentation.
                }
            }
        }

        final class Coordinator: NSObject, UINavigationControllerDelegate,
            UIImagePickerControllerDelegate
        {
            let onImage: (UIImage) -> Void
            let onCancel: () -> Void
            private weak var picker: UIImagePickerController?

            init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
                self.onImage = onImage
                self.onCancel = onCancel
            }

            func presentCamera(from presenter: UIViewController) {
                guard picker == nil else { return }
                let picker = UIImagePickerController()
                picker.sourceType = .camera
                picker.cameraCaptureMode = .photo
                picker.delegate = self
                picker.modalPresentationStyle = .fullScreen
                self.picker = picker
                presenter.present(picker, animated: false)
            }

            func imagePickerController(
                _ picker: UIImagePickerController,
                didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
            ) {
                guard let image = info[.originalImage] as? UIImage else {
                    finish(picker, action: onCancel)
                    return
                }
                finish(picker) { [onImage] in
                    onImage(image)
                }
            }

            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                finish(picker, action: onCancel)
            }

            private func finish(
                _ picker: UIImagePickerController,
                action: @escaping () -> Void
            ) {
                self.picker = nil
                picker.dismiss(animated: false, completion: action)
            }
        }
    }
#endif
