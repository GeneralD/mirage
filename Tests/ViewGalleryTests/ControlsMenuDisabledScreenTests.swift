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
@Suite("Controls menu disabled screen", .timeLimit(.minutes(1)))
struct ControlsMenuDisabledScreenTests {
    /// Opens the menu over the disabled catalog the way the screen does, and waits until its rows have arrived.
    private func openedMenu() async throws -> FakeControlsMenuWindow {
        let windows = Collector<FakeControlsMenuWindow>()

        _ = openControlsMenu(showing: effectPickerDisabledCatalog, controls: ControlsState(isBypassed: false, framesPerSecond: 30)) { presenter in
            let window = FakeControlsMenuWindow(presenter: presenter)
            windows.append(window)
            return window
        }

        let window = try #require(windows.values.first)
        await settle(window.presenter.$items) { !$0.isEmpty }
        return window
    }

    @Test("controls-menu-disabled is registered exactly once, under its name")
    func registered() {
        let names = galleryScreens.map(\.name)

        #expect(names.filter { $0 == "controls-menu-disabled" }.count == 1)
    }

    @Test("controls-menu-disabled's summary says the chosen effect and another were disabled, each with a Re-enable row")
    func summary() throws {
        let screen = try #require(galleryScreens.first { $0.name == "controls-menu-disabled" })

        #expect(screen.summary == "Effects menu: the chosen effect and another were disabled by the health policy, each with a Re-enable row")
    }

    @Test("opening controls-menu-disabled makes one window and shows it once")
    func opensOneWindow() async throws {
        let windows = Collector<FakeControlsMenuWindow>()

        _ = openControlsMenu(showing: effectPickerDisabledCatalog, controls: ControlsState(isBypassed: false, framesPerSecond: 30)) { presenter in
            let window = FakeControlsMenuWindow(presenter: presenter)
            windows.append(window)
            return window
        }

        let window = try #require(windows.values.first)
        #expect(windows.count == 1)
        #expect(window.shows == 1)
    }

    @Test("the menu lists the four rows in the catalog's order, with Glitch chosen and Glitch and Ripple disabled")
    func rowsInOrder() async throws {
        let window = try await openedMenu()
        let items = window.presenter.items

        #expect(items.map(\.title) == ["Chromatic Grain", "Glitch", "Ripple", "Neon Outline"])
        #expect(items.map(\.isEnabled) == [true, false, false, true])
        #expect(items.map(\.isSelected) == [false, true, false, false])
    }

    @Test("a row that health switched off offers Re-enable under its name, and the other rows offer none")
    func reenableRows() async throws {
        let window = try await openedMenu()
        let reenableTitles: [String?] = window.presenter.items.map(\.reenableTitle)

        #expect(reenableTitles == [nil, "Re-enable Glitch", "Re-enable Ripple", nil])
    }

    @Test("a row that health switched off says why as its second line, and a package that is enabled shows its author")
    func rowDetails() async throws {
        let window = try await openedMenu()
        let items = window.presenter.items

        #expect(items[1].detail == "Disabled: timed out")
        #expect(items[2].detail == "Disabled: over the GPU time budget")
        #expect(items[3].detail == "A. Sample")
    }

    @Test("the status line says the chosen effect is disabled and why")
    func disabledStatus() async throws {
        let window = try await openedMenu()
        await settle(window.presenter.$status) { $0 != nil }

        #expect(window.presenter.status == "Glitch: disabled, timed out")
    }
}
