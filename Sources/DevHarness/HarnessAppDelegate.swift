import AppKit
import AppRouter
import HostDependencyInjection
import SwiftUI
import Views

/// AppKit glue, untested by design: the harness's lifecycle and wiring are
/// `HarnessSession`'s, and what it does is `HarnessInteractor`'s.
/// One window whose content is `PreviewView`, sized to the 1280 × 720 frame it
/// shows (resize it and the preview's black bars appear), a Quit item, the session
/// started once the window is up and stopped on termination. Closing the window
/// quits. Importing `HostDependencyInjection` links the host's live values, as `App` does.
///
/// The main menu also has an Effects menu: the host's `EffectMenu`, hosted by an
/// `NSHostingMenu` over the Presenter of an `AppRouter` this delegate owns, started and
/// stopped beside the session as `HostAppDelegate` does. Choosing an effect there is what
/// the host's menu bar does, so the effect switch and the hot reload can be tried here
/// without the extension. The router is built outside the session's substitution on
/// purpose: the effects menu resolves nothing the discarding sink touches.
@MainActor
final class HarnessAppDelegate: NSObject, NSApplicationDelegate {
    private let session = HarnessSession.live()
    private let router = AppRouter()
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.mainMenu = mainMenu
        window.title = "Dev Harness"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PreviewView { [session] target in session.attach(target) })
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
        session.start()
        router.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        router.stop()
        session.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private var mainMenu: NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let menu = NSMenu()
        menu.addItem(appItem)
        // `NSHostingMenu` is macOS 14.4+ while the package's floor is 14.0: on an older macOS the
        // harness has no Effects menu, and the host's `MenuBarExtra` is unaffected.
        if #available(macOS 14.4, *) {
            menu.addItem(effectsItem)
        }
        return menu
    }

    @available(macOS 14.4, *)
    private var effectsItem: NSMenuItem {
        let item = NSMenuItem(title: "Effects", action: nil, keyEquivalent: "")
        item.submenu = NSHostingMenu(rootView: EffectMenu(presenter: router.menuBarPresenter))
        return item
    }
}
