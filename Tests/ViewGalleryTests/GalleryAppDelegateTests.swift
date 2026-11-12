import AppKit
import Testing

@testable import ViewGallery

private final class Opened {}

/// Remembers the last object a screen opened without keeping it alive, and how often the screen was opened.
@MainActor
private final class OpenRecord {
    private(set) weak var last: AnyObject?
    private(set) var opens = 0

    func screen() -> GalleryScreen {
        GalleryScreen(name: "recorded", summary: "A screen") { [self] in
            let opened = Opened()
            last = opened
            opens += 1
            return opened
        }
    }
}

@MainActor
@Suite("GalleryAppDelegate")
struct GalleryAppDelegateTests {
    private let launched = Notification(name: NSApplication.didFinishLaunchingNotification)

    @Test("making the delegate opens nothing")
    func quietBeforeLaunch() {
        let record = OpenRecord()

        let delegate = GalleryAppDelegate(screen: record.screen())

        #expect(record.opens == 0)
        withExtendedLifetime(delegate) {}
    }

    @Test("launching opens the screen once and keeps what it opened alive until the delegate is let go")
    func launchOpensAndKeeps() {
        let record = OpenRecord()
        var delegate: GalleryAppDelegate? = GalleryAppDelegate(screen: record.screen())

        delegate?.applicationDidFinishLaunching(launched)

        #expect(record.opens == 1)
        #expect(record.last != nil)
        delegate = nil
        #expect(record.last == nil)
    }

    @Test("the gallery quits when its last window closes")
    func quitsWithItsWindow() {
        let delegate = GalleryAppDelegate(screen: OpenRecord().screen())

        #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}
