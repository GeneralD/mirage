import Domain
import Presenters
import TestSupport
import Testing

@testable import ViewGallery

/// A controls window that is never on screen: it only counts what the gallery asks of it, and holds the Presenter it was given.
@MainActor
private final class FakeControlsMenuWindow {
    private(set) var shows = 0
    let presenter: MenuBarPresenter

    init(presenter: MenuBarPresenter) {
        self.presenter = presenter
    }
}

extension FakeControlsMenuWindow: ControlsMenuWindow {
    func show() {
        shows += 1
    }
}

@MainActor
@Suite("Controls menu screens", .timeLimit(.minutes(1)))
struct ControlsMenuScreenTests {
    @Test("the two controls menu screens are registered once each, under their names")
    func registered() {
        let names = galleryScreens.map(\.name)

        #expect(names.filter { $0 == "controls-menu" }.count == 1)
        #expect(names.filter { $0 == "controls-menu-bypassed" }.count == 1)
    }

    @Test("controls-menu's summary says bypass off, 30 fps and the chosen effect, in one line")
    func summary() throws {
        let screen = try #require(galleryScreens.first { $0.name == "controls-menu" })

        #expect(screen.summary == "Effects menu: bypass off, 30 fps, Chromatic Grain chosen")
    }

    @Test("opening controls-menu makes one window and shows it once, its Presenter is unbypassed at 30 fps with six rows")
    func opensOneWindow() async throws {
        let windows = Collector<FakeControlsMenuWindow>()

        _ = openControlsMenu(showing: effectPickerCatalog, controls: ControlsState(isBypassed: false, framesPerSecond: 30)) { presenter in
            let window = FakeControlsMenuWindow(presenter: presenter)
            windows.append(window)
            return window
        }

        let window = try #require(windows.values.first)
        #expect(windows.count == 1)
        #expect(window.shows == 1)
        await settle(window.presenter.$items) { !$0.isEmpty }
        await settle(window.presenter.$frameRateLine) { $0 != nil }
        #expect(window.presenter.isBypassed == false)
        #expect(window.presenter.frameRateLine == "30 fps")
        #expect(window.presenter.iconName == "camera.filters")
        #expect(window.presenter.items.count == 6)
    }

    @Test("controls-menu-bypassed opens its Presenter bypassed: no frame rate line, the plain camera icon, and the compile failure line")
    func opensBypassed() async throws {
        let windows = Collector<FakeControlsMenuWindow>()

        _ = openControlsMenu(showing: effectPickerFailedCatalog, controls: ControlsState(isBypassed: true, framesPerSecond: 0)) { presenter in
            let window = FakeControlsMenuWindow(presenter: presenter)
            windows.append(window)
            return window
        }

        let window = try #require(windows.values.first)
        await settle(window.presenter.$isBypassed) { $0 }
        await settle(window.presenter.$items) { !$0.isEmpty }
        #expect(window.presenter.isBypassed == true)
        #expect(window.presenter.frameRateLine == nil)
        #expect(window.presenter.status == "Ripple: compile failed")
        #expect(window.presenter.iconName == "camera")
    }

    @Test("GalleryControlsMenuWindow made over a Presenter is not on screen until it is shown, and is titled Menu")
    func windowIsHiddenUntilShown() {
        let presenter = MenuBarPresenter()

        let window = GalleryControlsMenuWindow(presenter: presenter)

        #expect(window.isVisible == false)
        #expect(window.windowTitle == "Menu")
    }
}
