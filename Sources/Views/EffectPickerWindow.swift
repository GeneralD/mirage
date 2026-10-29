import AppKit
import Presenters
import SwiftUI

/// The effect picker's window (#12): an `NSWindow` whose content is `EffectPickerView`, and the
/// three things `AppRouter` does with it, which are to show it, close it and hear that it closed.
/// AppKit glue, untested by design and free of decisions (`Views` is coverage-ignored): when the
/// window opens or closes, and what its closing ends, are the Router's.
///
/// It is its window's delegate, so a close from the title bar or ⌘W reaches `onClose` as one from
/// `close()` does. It owns the window, so the window is not released when it closes.
@MainActor
public final class EffectPickerWindow: NSObject {
    private let window: NSWindow
    private let onClose: @MainActor (EffectPickerWindow) -> Void

    public init(presenter: EffectPickerPresenter, onClose: @escaping @MainActor (EffectPickerWindow) -> Void) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true)
        self.onClose = onClose
        super.init()
        window.title = "Effects"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EffectPickerView(presenter: presenter))
        window.delegate = self
        window.center()
    }

    /// Brings the application forward, since a menu-bar app is not active while its menu is used,
    /// and the window to the front.
    public func show() {
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
    }

    public func close() {
        window.close()
    }
}

extension EffectPickerWindow: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        onClose(self)
    }
}
