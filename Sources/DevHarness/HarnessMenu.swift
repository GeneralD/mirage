import AppKit
import AppRouter
import Dependencies
import HostDependencyInjection
import SwiftUI
import Views

/// The harness's main menu, and the lifecycle of the Router behind its Effects menu: what
/// `HarnessAppDelegate` would otherwise do inline, held here so that `DevHarnessTests` can reach
/// it. The delegate keeps the AppKit calls that need a running application (the window, the
/// activation, setting the menu on `NSApplication`).
///
/// The main menu is a Quit item under the application menu and an Effects menu: the host's
/// `EffectMenu`, hosted by an `NSHostingMenu` over the Presenter of the `AppRouter` this owns.
/// Choosing an effect there is what the host's menu bar does, so the effect switch and the hot
/// reload can be tried in the harness without the extension. The live Router has the host's Camera
/// submenu too: starting it applies the camera choice (the remembered camera, or the one picked when
/// none is remembered or it cannot give frames) before the first frame matters, as the host's does,
/// and the submenu changes it. `start()` and `stop()` are the
/// Router's, called beside the session's as `HostAppDelegate` calls them; this resolves nothing
/// itself (`scripts/check-dependency-keypaths.sh` denies `App` and `DevHarness` `\.effectInteractor`).
///
/// The Router is built inside the same substitution as the session (`live()`): the menu's controls
/// resolve the frame pipeline, and the pipeline keeps the sink of the scope that builds it, so a
/// Router built outside would give it the real sink. `live()` is that construction, and the one
/// place a Router is made for the harness.
@MainActor
final class HarnessMenu {
    /// The Router whose Presenter the Effects menu draws from.
    let router: AppRouter
    private let makeEffectsMenu: @MainActor (AppRouter) -> NSMenu?

    /// `makeEffectsMenu` answers the menu that hosts the effects of a Router's Presenter, or `nil`
    /// when the system cannot host one; the default is `hostingMenu(for:)`.
    init(router: AppRouter, makeEffectsMenu: @escaping @MainActor (AppRouter) -> NSMenu? = HarnessMenu.hostingMenu(for:)) {
        self.router = router
        self.makeEffectsMenu = makeEffectsMenu
    }

    /// The harness's menu over the live Router, as the process launches it. The Router is built inside the substitution, as the session's is.
    static func live() -> HarnessMenu {
        withDependencies {
            $0.useDiscardingVirtualCameraSink()
        } operation: {
            HarnessMenu(router: AppRouter(showsCameraMenu: true))
        }
    }

    /// The menu `NSApplication` shows: the application menu with Quit, then the Effects menu when
    /// the system can host it.
    var mainMenu: NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let menu = NSMenu()
        menu.addItem(appItem)
        if let effects = makeEffectsMenu(router) {
            let effectsItem = NSMenuItem(title: "Effects", action: nil, keyEquivalent: "")
            effectsItem.submenu = effects
            menu.addItem(effectsItem)
        }
        return menu
    }

    /// Once the window is up, beside the session's start.
    func start() {
        router.start()
    }

    /// On termination, before the session's stop.
    func stop() {
        router.stop()
    }

    /// The host's `EffectMenu` in an `NSHostingMenu`, with the Camera submenu when the Router has
    /// one. `NSHostingMenu` is macOS 14.4+ while the package's floor is 14.0: on an older macOS the
    /// harness has no Effects menu, and the host's `MenuBarExtra` is unaffected.
    static func hostingMenu(for router: AppRouter) -> NSMenu? {
        guard #available(macOS 14.4, *) else { return nil }
        return NSHostingMenu(rootView: EffectMenu(presenter: router.menuBarPresenter, camera: router.cameraMenuPresenter))
    }
}
