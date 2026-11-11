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
/// With a `PreviewPresenter` (#68) the window is taller and the pane sits above the grid; the window
/// then tells the preview whether it is on screen, which `pickerWindowIsShown` decides from the window's state.
///
/// It is its window's delegate, so a close from the title bar, or from anything that sends
/// `performClose:` or `close()`, reaches `onClose` as one from `close()` does. It owns the window,
/// so the window is not released when it closes.
@MainActor
public final class EffectPickerWindow: NSObject {
    private let window: NSWindow
    private let preview: PreviewPresenter?
    private let onClose: @MainActor (EffectPickerWindow) -> Void

    public init(
        presenter: EffectPickerPresenter, preview: PreviewPresenter? = nil,
        onClose: @escaping @MainActor (EffectPickerWindow) -> Void
    ) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: preview == nil ? 480 : 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true)
        self.preview = preview
        self.onClose = onClose
        super.init()
        window.title = "Effects"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: EffectPickerView(presenter: presenter, preview: preview, decode: EffectThumbnailDecoding.image(of:)))
        if preview != nil {
            window.contentMinSize = NSSize(width: 320, height: PreviewGeometry.minimumContentHeight)
        }
        window.delegate = self
        window.center()
    }

    /// Brings the application forward, since a menu-bar app is not active while its menu is used,
    /// and the window to the front. The preview is told the window is shown at once, without waiting
    /// for the first occlusion report.
    public func show() {
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        preview?.setVisible(true)
    }

    public func close() {
        window.close()
    }
}

extension EffectPickerWindow: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        onClose(self)
    }

    /// The window was covered or uncovered. The notification is not read: the window's state is.
    public func windowDidChangeOcclusionState(_ notification: Notification) {
        reportVisibility()
    }

    public func windowDidMiniaturize(_ notification: Notification) {
        reportVisibility()
    }

    public func windowDidDeminiaturize(_ notification: Notification) {
        reportVisibility()
    }

    /// Tells the preview whether the window is on screen now.
    private func reportVisibility() {
        preview?.setVisible(pickerWindowIsShown(occlusion: window.occlusionState, isMiniaturized: window.isMiniaturized))
    }
}

/// Whether the picker's window is on screen: its occlusion state shows it visible, and it is not miniaturized.
/// A window that has never been on screen has no visible occlusion state, so it is not shown.
func pickerWindowIsShown(occlusion: NSWindow.OcclusionState, isMiniaturized: Bool) -> Bool {
    occlusion.contains(.visible) && !isMiniaturized
}
