import AppKit
import HostDependencyInjection
import SwiftUI
import Views

/// AppKit glue, untested by design: the harness's lifecycle and wiring are
/// `HarnessSession`'s, and what it does is `HarnessInteractor`'s.
/// One 4:3 window whose content is `PreviewView` (so the 16:9 frame shows the
/// preview's black bars), a Quit item, the session started once the window is
/// up and stopped on termination. Closing the window quits. Importing
/// `HostDependencyInjection` links the host's live values, as `App` does.
@MainActor
final class HarnessAppDelegate: NSObject, NSApplicationDelegate {
    private let session = HarnessSession()
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.mainMenu = quitMenu
        window.title = "Dev Harness"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PreviewView { [session] target in session.attach(target) })
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
        session.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        session.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private var quitMenu: NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let menu = NSMenu()
        menu.addItem(appItem)
        return menu
    }
}
