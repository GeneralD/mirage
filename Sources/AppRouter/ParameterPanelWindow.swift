import AppKit
import Presenters
import SwiftUI
import Views

/// The effect parameter panel's window (#118): it hosts `ParameterPanelView` in a titled, resizable `NSWindow` and does the three
/// things `AppRouter` does with it, which are to show it, close it and hear that it closed. AppKit glue, free of decisions: when
/// the panel opens or closes, and what its closing ends, are the Router's; the title, the rows and the words are the Presenter's
/// and the View's. It lives with the Router rather than in `Views`, which holds declarations only, the same as `EffectPickerWindow`.
///
/// It is its window's delegate, so a close from the title bar, or from anything that sends `performClose:` or `close()`, reaches
/// `onClose` as one from `close()` does. It owns the window, so the window is not released when it closes.
@MainActor
public final class ParameterPanelWindow: NSObject {
    private let window: NSWindow
    private let onClose: @MainActor (ParameterPanelWindow) -> Void

    public init(presenter: ParameterPanelPresenter, onClose: @escaping @MainActor (ParameterPanelWindow) -> Void) {
        window = NSWindow(
            contentRect: NSRect(
                x: 0, y: 0,
                width: ParameterPanelGeometry.initialWidth,
                height: ParameterPanelGeometry.initialHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true)
        self.onClose = onClose
        super.init()
        window.title = presenter.windowTitle
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(
            width: ParameterPanelGeometry.minimumWidth,
            height: ParameterPanelGeometry.minimumHeight)
        window.contentView = NSHostingView(rootView: ParameterPanelView(presenter: presenter))
        window.delegate = self
        window.center()
    }

    /// Brings the application forward, since a menu-bar app is not active while its menu is used, and the window to the front.
    public func show() {
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
    }

    public func close() {
        window.close()
    }

    /// The window's title, which the tests read.
    internal var windowTitle: String { window.title }
}

extension ParameterPanelWindow: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        onClose(self)
    }
}
