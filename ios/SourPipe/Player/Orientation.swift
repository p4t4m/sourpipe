import UIKit

/// Full screen video is always landscape, even with rotation lock on, and never portrait.
/// The app delegate reports `mask`; changing it and asking the scene to rotate does the rest.
@MainActor
enum Orientation {
    private(set) static var mask: UIInterfaceOrientationMask = defaultMask

    private static var defaultMask: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    /// iPad full screen already fits either way, so only phones are forced.
    private static var applies: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    static func enterFullScreen() {
        guard applies else { return }
        set(.landscape, request: .landscape)
    }

    static func exitFullScreen() {
        guard applies else { return }
        set(defaultMask, request: .portrait)
    }

    private static func set(_ newMask: UIInterfaceOrientationMask,
                            request: UIInterfaceOrientationMask) {
        mask = newMask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                var controller = window.rootViewController
                while let current = controller {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = current.presentedViewController
                }
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: request)) { error in
                NSLog("[player] rotation refused: %@", error.localizedDescription)
            }
        }
        NSLog("[player] orientation mask %lu", newMask.rawValue)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { Orientation.mask }
    }
}
