import AppKit
import HostDependencyInjection
import SwiftUI
import Views

/// AppKit glue, untested by design: the harness's lifecycle and wiring are
/// `HarnessSession`'s, what it does is `HarnessInteractor`'s, and the main menu and the
/// Router behind its Effects menu are `HarnessMenu`'s.
/// One window whose content is `PreviewView`, sized to the 1280 × 720 frame it
/// shows (resize it and the preview's black bars appear), the main menu, the session
/// and the menu's Router started once the window is up and stopped on termination.
/// Closing the window quits. Importing `HostDependencyInjection` links the host's
/// live values, as `App` does.
///
/// What remains here needs a running application: the window, the activation, and
/// the menu set on `NSApplication`. The Router is built outside the session's
/// substitution on purpose (`HarnessMenu.live()`): the effects menu resolves nothing
/// the discarding sink touches.
@MainActor
final class HarnessAppDelegate: NSObject, NSApplicationDelegate {
    private let session = HarnessSession.live()
    private let menu = HarnessMenu.live()
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.mainMenu = menu.mainMenu
        window.title = "Dev Harness"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PreviewView { [session] target in session.attach(target) })
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
        session.start()
        menu.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menu.stop()
        session.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
