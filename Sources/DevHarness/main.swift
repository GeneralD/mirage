// `swift run dev-harness`: AppKit's launch and nothing else. The window is
// HarnessAppDelegate's, the lifecycle HarnessSession's.
import AppKit

let delegate = HarnessAppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.regular)
// `NSApplication.delegate` does not own the delegate: keep it alive for the
// whole run loop.
withExtendedLifetime(delegate) {
    NSApplication.shared.run()
}
