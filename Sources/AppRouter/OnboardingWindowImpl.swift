import AppKit
import Presenters
import SwiftUI
import Views

/// The onboarding window (#229): it hosts `OnboardingView` in a titled, resizable `NSWindow` and does the three things `AppRouter`
/// does with it, which are to show it, close it and hear that it closed. AppKit glue, free of decisions: when the window opens or
/// closes, and what its closing ends, are the Router's; the title is `Presenters`' and the view is the View's. It lives with the
/// Router rather than in `Views`, which holds declarations only, the same as `EffectPickerWindow` and `ParameterPanelWindow`.
///
/// It is its window's delegate, so a close from the title bar, or from anything that sends `performClose:` or `close()`, reaches
/// `onClose` as one from `close()` does. It owns the window, so the window is not released when it closes.
@MainActor
public final class OnboardingWindowImpl: NSObject {
    private let window: NSWindow
    private let onClose: @MainActor (OnboardingWindowImpl) -> Void

    public init(presenter: OnboardingPresenter, onClose: @escaping @MainActor (OnboardingWindowImpl) -> Void) {
        window = NSWindow(
            contentRect: NSRect(
                x: 0, y: 0,
                width: OnboardingGeometry.windowWidth,
                height: OnboardingGeometry.initialWindowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true)
        self.onClose = onClose
        super.init()
        window.title = onboardingWindowTitle
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView(presenter: presenter))
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

extension OnboardingWindowImpl: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        onClose(self)
    }
}
