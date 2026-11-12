import AppKit

/// The gallery's application delegate: opens the chosen screen once the application has launched and keeps what the
/// screen answers alive for as long as the delegate lives. The gallery quits when its window closes.
@MainActor
final class GalleryAppDelegate: NSObject {
    private let screen: GalleryScreen
    private var opened: AnyObject?

    init(screen: GalleryScreen) {
        self.screen = screen
        super.init()
    }
}

extension GalleryAppDelegate: NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        opened = screen.open()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
