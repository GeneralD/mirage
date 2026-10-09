// `swift run dev-harness`: AppKit's launch and nothing else. The window is
// HarnessAppDelegate's; everything the harness does is HarnessSession's.
import AppKit

let delegate = HarnessAppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.regular)
NSApplication.shared.run()
