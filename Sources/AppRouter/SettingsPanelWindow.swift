import AppKit
import Presenters
import SwiftUI
import Views

/// The settings window's AppKit glue (#198): it hosts `SettingsView` in a titled, closable `NSWindow`
/// and does the three things `AppRouter` does with it, which are to show it, close it and hear that it
/// closed. Decisions are not made here: what the window says and does is the View's and the Presenter's.
/// It lives with the Router rather than in `Views`, which holds declarations only, the same as
/// `EffectPickerWindow`.
///
/// It is its window's delegate, so a close from the title bar, or from anything that sends
/// `performClose:` or `close()`, reaches `onClose` as one from `close()` does. It owns the window,
/// so the window is not released when it closes. The window takes its size from the content.
@MainActor
public final class SettingsPanelWindow: NSObject {
    private let window: NSWindow
    private let onClose: @MainActor (SettingsPanelWindow) -> Void

    public init(presenter: SettingsPresenter, onClose: @escaping @MainActor (SettingsPanelWindow) -> Void) {
        window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true)
        self.onClose = onClose
        super.init()
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(presenter: presenter))
        window.center()
        window.delegate = self
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

    /// The window's title, which the tests read.
    internal var windowTitle: String { window.title }
}

extension SettingsPanelWindow: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        onClose(self)
    }
}
