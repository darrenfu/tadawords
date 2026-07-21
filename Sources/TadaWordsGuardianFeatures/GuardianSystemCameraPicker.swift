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
            controller.onCancel = { [weak coordinator = context.coordinator] in
                coordinator?.cancelBeforePresentingCamera()
            }
            return controller
        }

        func updateUIViewController(
            _ uiViewController: PresentationController,
            context: Context
        ) {}

        final class PresentationController: UIViewController {
            var onReady: ((UIViewController) -> Void)?
            var onCancel: (() -> Void)?
            private var hasAppeared = false
            private var hasPresentedCamera = false
            private var geometryRequestFailed = false

            private let instructionLabel: UILabel = {
                let label = UILabel()
                label.translatesAutoresizingMaskIntoConstraints = false
                label.text = "Rotate iPhone upright to take a photo"
                label.textColor = .white
                label.font = .preferredFont(forTextStyle: .title2)
                label.textAlignment = .center
                label.numberOfLines = 0
                return label
            }()

            private lazy var cancelButton: UIButton = {
                var configuration = UIButton.Configuration.gray()
                configuration.title = "Cancel"
                configuration.cornerStyle = .capsule
                let button = UIButton(configuration: configuration)
                button.translatesAutoresizingMaskIntoConstraints = false
                button.addTarget(self, action: #selector(cancel), for: .touchUpInside)
                return button
            }()

            override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
                .portrait
            }

            override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
                .portrait
            }

            override func viewDidLoad() {
                super.viewDidLoad()
                view.backgroundColor = .black
                view.addSubview(instructionLabel)
                view.addSubview(cancelButton)
                NSLayoutConstraint.activate([
                    cancelButton.leadingAnchor.constraint(
                        equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                        constant: 20
                    ),
                    cancelButton.topAnchor.constraint(
                        equalTo: view.safeAreaLayoutGuide.topAnchor,
                        constant: 16
                    ),
                    instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                    instructionLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                    instructionLabel.leadingAnchor.constraint(
                        greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor,
                        constant: 32
                    ),
                    instructionLabel.trailingAnchor.constraint(
                        lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor,
                        constant: -32
                    ),
                ])
            }

            override func viewWillAppear(_ animated: Bool) {
                super.viewWillAppear(animated)
                requestPortraitGeometry()
            }

            override func viewDidAppear(_ animated: Bool) {
                super.viewDidAppear(animated)
                hasAppeared = true
                requestPortraitGeometry()
                presentCameraOnlyAfterPortraitTransition()
            }

            override func viewDidLayoutSubviews() {
                super.viewDidLayoutSubviews()
                presentCameraOnlyAfterPortraitTransition()
            }

            override func viewWillTransition(
                to size: CGSize,
                with coordinator: any UIViewControllerTransitionCoordinator
            ) {
                super.viewWillTransition(to: size, with: coordinator)
                coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                    self?.presentCameraOnlyAfterPortraitTransition()
                }
            }

            private func requestPortraitGeometry() {
                setNeedsUpdateOfSupportedInterfaceOrientations()
                guard let scene = view.window?.windowScene else { return }
                for window in scene.windows {
                    window.rootViewController?
                        .setNeedsUpdateOfSupportedInterfaceOrientations()
                }
                scene.requestGeometryUpdate(
                    .iOS(interfaceOrientations: .portrait)
                ) { [weak self] _ in
                    self?.geometryRequestFailed = true
                    self?.showRotateInstruction()
                }
            }

            private func presentCameraOnlyAfterPortraitTransition() {
                guard hasAppeared,
                    !hasPresentedCamera,
                    viewIfLoaded?.window != nil,
                    view.window?.windowScene?.interfaceOrientation.isPortrait == true
                else {
                    showRotateInstruction()
                    return
                }
                hasPresentedCamera = true
                instructionLabel.isHidden = true
                cancelButton.isHidden = true
                onReady?(self)
            }

            private func showRotateInstruction() {
                guard !hasPresentedCamera else { return }
                instructionLabel.isHidden = false
                cancelButton.isHidden = false
                if geometryRequestFailed {
                    instructionLabel.accessibilityHint =
                        "The system could not rotate the camera automatically"
                }
            }

            @objc private func cancel() {
                onCancel?()
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

            func cancelBeforePresentingCamera() {
                guard picker == nil else { return }
                onCancel()
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
