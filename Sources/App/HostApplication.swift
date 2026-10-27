import Domain
import HostDependencyInjection
import SwiftUI
import Views

/// The host process entry point behind `Apps/Host/main.swift` (`HostApplication.main()`): a
/// menu-bar application with no window, whose one scene is the effects menu. Staying out of
/// the Dock is `LSUIElement` in the host's Info.plist (`project.yml`), not an activation
/// policy set at launch, which would show the Dock icon until it ran.
///
/// The delegate runs what is not a scene: the camera launch and the menu's Router, started
/// and stopped with the process. The menu is drawn from the Presenter the delegate's Router
/// built (`EffectMenu`); it starts nothing itself.
public struct HostApplication: App {
    @NSApplicationDelegateAdaptor(HostAppDelegate.self) private var delegate

    public init() {}

    public var body: some Scene {
        MenuBarExtra(ProductIdentity.displayName, systemImage: "camera.filters") {
            EffectMenu(presenter: delegate.router.menuBarPresenter)
        }
        .menuBarExtraStyle(.menu)
    }
}
