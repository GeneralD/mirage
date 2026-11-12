import Domain
import HostDependencyInjection
import SwiftUI
import Views

/// The host process entry point behind `Apps/Host/main.swift` (`HostApplication.main()`): a
/// menu-bar application whose one scene is the menu. Its windows are the effect picker and the
/// onboarding window that the menu opens, through the Routers rather than as scenes. Staying out of
/// the Dock is `LSUIElement` in the host's Info.plist (`project.yml`), not an activation
/// policy set at launch, which would show the Dock icon until it ran.
///
/// The delegate runs what is not a scene: the camera launch and the menu's Router, started and stopped
/// with the process, and the onboarding Router, which opens its window on demand and is closed at
/// termination. The menu is drawn from the Presenter the delegate's Router built (`EffectMenu`), and so
/// is its icon in the menu bar (`MenuBarLabel`); the Camera submenu is drawn from that Router's camera
/// Presenter too, and the onboarding item calls the delegate's Router to open its window. The scene
/// starts nothing itself.
public struct HostApplication: App {
    @NSApplicationDelegateAdaptor(HostAppDelegate.self) private var delegate

    public init() {}

    public var body: some Scene {
        MenuBarExtra {
            OnboardingMenuItem { delegate.onboardingRouter.openOnboarding() }
            EffectMenu(presenter: delegate.router.menuBarPresenter, camera: delegate.router.cameraMenuPresenter)
        } label: {
            MenuBarLabel(presenter: delegate.router.menuBarPresenter)
        }
        .menuBarExtraStyle(.menu)
    }
}
