import SwiftUI
import UIKit
import Combine

@main
final class OldCameraAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = OldCameraSceneDelegate.self
        return configuration
    }

    /// The iOS 6 Camera interface stays portrait; captures follow the device.
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }
}

final class OldCameraSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = OldCameraHostingController(root: OldCameraRootView())
        window.backgroundColor = .black
        self.window = window
        window.makeKeyAndVisible()
    }
}

/// Status bar: hidden over the viewfinder (iOS 6), light over the Camera Roll.
final class CameraStatusBar: ObservableObject {
    static let shared = CameraStatusBar()

    @Published var hidden = true

    private init() {}
}

final class OldCameraHostingController: UIHostingController<OldCameraRootView> {
    private var cancellables = Set<AnyCancellable>()

    init(root: OldCameraRootView) {
        super.init(rootView: root)
        CameraStatusBar.shared.$hidden
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                UIView.animate(withDuration: 0.25) {
                    self?.setNeedsStatusBarAppearanceUpdate()
                }
            }
            .store(in: &cancellables)
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override var prefersStatusBarHidden: Bool {
        CameraStatusBar.shared.hidden
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }
}
