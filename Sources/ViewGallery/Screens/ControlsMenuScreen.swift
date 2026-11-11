import AppKit
import Dependencies
import Domain
import Presenters
import SwiftUI
import Views

private let menuWidth: CGFloat = 300
private let menuPadding: CGFloat = 16

extension GalleryScreen {
    /// The menu over the chosen bundled effect, not bypassed, at 30 frames per second.
    static var controlsMenu: GalleryScreen {
        GalleryScreen(name: "controls-menu", summary: "Effects menu: bypass off, 30 fps, Chromatic Grain chosen") {
            openControlsMenu(showing: effectPickerCatalog, controls: ControlsState(isBypassed: false, framesPerSecond: 30))
        }
    }

    /// The menu with the bypass on over the catalog whose chosen effect failed to compile: the status line stays, the readout goes.
    static var controlsMenuBypassed: GalleryScreen {
        GalleryScreen(name: "controls-menu-bypassed", summary: "Effects menu: bypass on while the chosen effect failed to compile") {
            openControlsMenu(showing: effectPickerFailedCatalog, controls: ControlsState(isBypassed: true, framesPerSecond: 0))
        }
    }
}

/// The window a controls-menu screen shows. `openControlsMenu` makes one and shows it once; a test puts a fake in its place.
@MainActor
protocol ControlsMenuWindow: AnyObject {
    func show()
}

/// Builds a `MenuBarPresenter` whose Interactors publish `catalog` and `controls`, starts it, shows the window `makeWindow` makes over
/// it and answers that window, which keeps the Presenter alive. The Presenter is made inside `withDependencies` because it captures the
/// dependencies of the scope it is built in. `makeWindow` is the seam a test uses to open no real window.
@MainActor
func openControlsMenu(
    showing catalog: EffectCatalogState,
    controls: ControlsState,
    makeWindow: @escaping @MainActor (MenuBarPresenter) -> any ControlsMenuWindow = { GalleryControlsMenuWindow(presenter: $0) }
) -> AnyObject {
    let presenter = withDependencies {
        $0.effectInteractor = GalleryEffectInteractor(catalog: catalog)
        $0.controlsInteractor = GalleryControlsInteractor(controls: controls)
    } operation: {
        MenuBarPresenter()
    }
    presenter.start()
    let window = makeWindow(presenter)
    window.show()
    return window
}

/// The menu as a window of its own: the menu bar icon, a divider, then the `EffectMenu`, stacked the way the menu lists them. The
/// menu bar has no window to host it in, so the gallery draws the same views in a plain `NSWindow`. Holding the Presenter keeps it
/// started; releasing this window stops it.
@MainActor
final class GalleryControlsMenuWindow {
    private let presenter: MenuBarPresenter
    private let window: NSWindow

    init(presenter: MenuBarPresenter) {
        self.presenter = presenter
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: menuWidth, height: 0),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true)
        window.title = "Menu"
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(
            rootView: VStack(alignment: .leading, spacing: 8) {
                MenuBarLabel(presenter: presenter)
                Divider()
                EffectMenu(presenter: presenter)
            }
            .padding(menuPadding)
            .frame(width: menuWidth))
        window.contentView = hostingView
        window.setContentSize(hostingView.fittingSize)
    }

    /// The title the window was made with, for a test.
    internal var windowTitle: String {
        window.title
    }

    /// Whether the window is on screen, for a test: it is `false` until `show()`.
    internal var isVisible: Bool {
        window.isVisible
    }
}

extension GalleryControlsMenuWindow: ControlsMenuWindow {
    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
