import AppKit
import Presenters
import SwiftUI
import Views

/// The effect picker's window (#12): it hosts `EffectPickerView` in an `NSWindow` and does the
/// three things `AppRouter` does with it, which are to show it, close it and hear that it closed.
/// AppKit glue, free of decisions: when the window opens or closes, and what its closing ends, are
/// the Router's. It lives with the Router rather than in `Views`, which holds declarations only;
/// `AppRouterPickerTests` makes one and closes it without showing it. It hands the view
/// `EffectThumbnailDecoding`, the one call that makes a picture of a thumbnail's bytes.
///
/// It is its window's delegate, so a close from the title bar, or from anything that sends
/// `performClose:` or `close()`, reaches `onClose` as one from `close()` does. It owns the window,
/// so the window is not released when it closes.
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
        window.contentView = NSHostingView(
            rootView: EffectPickerView(presenter: presenter, decode: EffectThumbnailDecoding.image(of:)))
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
