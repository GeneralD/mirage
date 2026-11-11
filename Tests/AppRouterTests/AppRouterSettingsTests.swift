import AppRouter
import Dependencies
import Domain
import Presenters
import TestDoubles
import TestSupport
import Testing

/// The Router's half of the settings window (#199): the window it opens from the menu's *Settings…*, the
/// settings Presenter it starts and stops with that window, the window's end from the title bar or from
/// `stop()`, and the menu's restart after a reset-all. Every window here is a `FakeSettingsWindow` made
/// through `makeSettingsWindow`, so no suite opens a real one; the live window's own glue is the last test,
/// which makes one and never shows it.
@MainActor
@Suite("AppRouter: the settings window", .timeLimit(.minutes(1)))
struct AppRouterSettingsTests {
    private let chromatic = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))

    @Test("the Router makes no window, and its settings Presenter reports to the Router; nothing is started")
    func builtWithTheRouter() {
        let rig = SettingsRig(state: .fixture([chromatic]))

        #expect(rig.windows.count == 0)
        #expect(rig.router.settingsPresenter.router === rig.router)
        #expect(rig.settings.refreshes.count == 0)
    }

    @Test("Settings… in the menu makes one window over the Router's settings Presenter, shows it and starts the Presenter")
    func settingsOpensTheWindow() throws {
        let rig = SettingsRig(state: .fixture([chromatic]))

        rig.router.menuBarPresenter.openSettings()

        let window = try #require(rig.windows.values.first)
        #expect(rig.windows.count == 1)
        #expect(window.presenter === rig.router.settingsPresenter)
        #expect(window.shows == 1)
        #expect(rig.settings.refreshes.count == 1)
    }

    @Test("asking again while the settings window is open brings the same window forward and makes no other")
    func openWhileOpenShowsTheSameWindow() throws {
        let rig = SettingsRig(state: .fixture([chromatic]))

        rig.router.openSettings()
        rig.router.menuBarPresenter.openSettings()

        let window = try #require(rig.windows.values.first)
        #expect(rig.windows.count == 1)
        #expect(window.shows == 2)
        #expect(rig.settings.refreshes.count == 1)
    }

    @Test("closing the settings window from its title bar stops its Presenter, and the next request makes a new window")
    func titleBarCloseEndsTheSettings() throws {
        let rig = SettingsRig(state: .fixture([chromatic]))
        rig.router.openSettings()
        let first = try #require(rig.windows.values.first)

        first.closeFromTitleBar()

        #expect(rig.settings.stateCancels.count == 1, "the Presenter was stopped: its observation of the state ended")
        #expect(first.closes == 0, "the window closed itself; the Router does not close it again")
        rig.router.openSettings()
        #expect(rig.windows.count == 2)
        #expect(first.shows == 1)
        #expect(rig.windows.values.last?.shows == 1)
    }

    @Test("closeSettings closes the open window once and stops its Presenter; without a window it does nothing")
    func closeSettingsClosesTheWindow() throws {
        let rig = SettingsRig(state: .fixture([chromatic]))
        rig.router.closeSettings()
        rig.router.openSettings()
        let window = try #require(rig.windows.values.first)

        rig.router.closeSettings()
        rig.router.closeSettings()

        #expect(window.closes == 1)
        #expect(rig.settings.stateCancels.count == 1)
        rig.router.openSettings()
        #expect(rig.windows.count == 2, "the closed window is not brought back")
    }

    @Test("a close reported by a window the Router has already let go leaves the open one alone")
    func staleCloseIsIgnored() throws {
        let rig = SettingsRig(state: .fixture([chromatic]))
        rig.router.openSettings()
        let first = try #require(rig.windows.values.first)
        rig.router.closeSettings()
        rig.router.openSettings()
        let second = try #require(rig.windows.values.last)

        first.closeFromTitleBar()

        #expect(rig.settings.stateCancels.count == 1, "only the first close ended an observation; the open window's Presenter still observes")
        rig.router.openSettings()
        #expect(rig.windows.count == 2)
        #expect(second.shows == 2, "the second window is still the open one")
    }

    @Test("stop closes the settings window as well as the menu")
    func stopClosesTheSettings() async throws {
        let rig = SettingsRig(state: .fixture([chromatic]))
        rig.router.start()
        await settle(rig.router.menuBarPresenter.$items) { !$0.isEmpty }
        rig.router.openSettings()
        let window = try #require(rig.windows.values.first)

        rig.router.stop()

        #expect(window.closes == 1)
        #expect(rig.settings.stateCancels.count == 1)
        #expect(rig.effects.stops.count == 1)
    }

    @Test("a finished reset-all restarts the menu: both Interactors are stopped once and started again")
    func settingsDidResetRestartsTheMenu() async {
        let rig = SettingsRig(state: .fixture([chromatic]))
        rig.router.start()
        await settle(rig.router.menuBarPresenter.$items) { !$0.isEmpty }
        #expect(rig.effects.starts.count == 1)
        #expect(rig.controls.starts.count == 1)

        rig.router.settingsDidReset()

        #expect(rig.effects.stops.count == 1)
        #expect(rig.controls.stops.count == 1)
        #expect(rig.effects.starts.count == 2)
        #expect(rig.controls.starts.count == 2)
    }

    @Test("a reset confirmed in the settings window runs once, and the menu restarts when it has finished")
    func confirmedResetRestartsTheMenu() async {
        let rig = SettingsRig(state: .fixture([chromatic]))
        rig.router.start()
        await settle(rig.router.menuBarPresenter.$items) { !$0.isEmpty }
        rig.router.openSettings()
        let presenter = rig.router.settingsPresenter

        presenter.requestReset()
        presenter.confirmReset()
        await settle(presenter.$isResetting) { !$0 }

        #expect(rig.settings.resets.count == 1)
        #expect(rig.effects.starts.count == 2, "the menu was restarted after the reset")
    }

    @Test("the live window is a SettingsPanelWindow over the Presenter, and its close reports that window")
    func liveWindowReportsItsClose() {
        let presenter = withDependencies {
            $0.settingsInteractor = FakeSettingsInteractor()
        } operation: {
            SettingsPresenter()
        }
        let closed = Collector<ObjectIdentifier>()

        let window = AppRouter.settingsWindow(over: presenter) { closed.append(ObjectIdentifier($0)) }
        // Never shown: closing a window that was never on screen still reports, and puts nothing on screen.
        window.close()

        let reported: [ObjectIdentifier] = closed.values
        #expect(window is SettingsPanelWindow)
        #expect(reported == [ObjectIdentifier(window)])
    }
}

/// The camera menu's restart after a reset-all (#167, #199): the reset removes the stored camera values, so the
/// menu's Presenter, started again, reads them afresh. The camera Interactor is the `camera` fake of `SettingsRig`.
@MainActor
@Suite("AppRouter: settings reset restarts the camera menu", .timeLimit(.minutes(1)))
struct AppRouterSettingsCameraResetTests {
    private let chromatic = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))

    @Test("with the camera menu shown, a finished reset-all restarts the camera Interactor: stopped once, then started again")
    func resetRestartsTheCameraInteractor() {
        let rig = SettingsRig(state: .fixture([chromatic]), showsCameraMenu: true)

        rig.router.start()
        #expect(rig.camera.starts.count == 1)
        #expect(rig.camera.stops.count == 0)

        rig.router.settingsDidReset()

        #expect(rig.camera.stops.count == 1)
        #expect(rig.camera.starts.count == 2)
    }

    @Test("with the camera menu not shown, starting the menu and a finished reset-all never touch the camera Interactor")
    func absentCameraMenuIsNotRestarted() {
        let rig = SettingsRig(state: .fixture([chromatic]))

        rig.router.start()
        rig.router.settingsDidReset()

        #expect(rig.camera.starts.count == 0)
        #expect(rig.camera.stops.count == 0)
    }

    @Test("a reset confirmed in the settings window restarts the camera menu once it has finished")
    func confirmedResetRestartsTheCameraMenu() async {
        let rig = SettingsRig(state: .fixture([chromatic]), showsCameraMenu: true)
        rig.router.start()
        await settle(rig.router.menuBarPresenter.$items) { !$0.isEmpty }
        rig.router.openSettings()
        let presenter = rig.router.settingsPresenter

        presenter.requestReset()
        presenter.confirmReset()
        await settle(presenter.$isResetting) { !$0 }

        #expect(rig.settings.resets.count == 1)
        #expect(rig.camera.starts.count == 2, "the camera menu was restarted after the reset")
    }
}

/// The settings window as the Router sees it. Like the live window, `close()` reports itself through
/// `onClose`; `closeFromTitleBar()` is a close the Router did not ask for.
@MainActor
private final class FakeSettingsWindow {
    let presenter: SettingsPresenter
    private let onClose: @MainActor (any SettingsWindow) -> Void
    private(set) var shows = 0
    private(set) var closes = 0

    init(presenter: SettingsPresenter, onClose: @escaping @MainActor (any SettingsWindow) -> Void) {
        self.presenter = presenter
        self.onClose = onClose
    }

    func closeFromTitleBar() {
        onClose(self)
    }
}

extension FakeSettingsWindow: SettingsWindow {
    func show() {
        shows += 1
    }

    func close() {
        closes += 1
        onClose(self)
    }
}

/// A Router whose three Presenters talk to fakes: the menu's and the settings Presenter are each built
/// inside `withDependencies`, over a `FakeEffectInteractor` and `FakeControlsInteractor`, and a
/// `FakeSettingsInteractor`, and its settings windows are `FakeSettingsWindow`s, recorded in the order
/// they were made. With `showsCameraMenu` its camera menu's Presenter talks to `camera`.
@MainActor
private struct SettingsRig {
    let effects: FakeEffectInteractor
    let controls: FakeControlsInteractor
    let settings: FakeSettingsInteractor
    let camera: FakeCameraSelectionInteractor
    let windows = Collector<FakeSettingsWindow>()
    let router: AppRouter

    init(state: EffectCatalogState, showsCameraMenu: Bool = false) {
        let effects = FakeEffectInteractor(state: state)
        let controls = FakeControlsInteractor()
        let settings = FakeSettingsInteractor()
        let camera = FakeCameraSelectionInteractor(state: .empty)
        let windows = windows
        self.effects = effects
        self.controls = controls
        self.settings = settings
        self.camera = camera
        router = AppRouter(
            makeMenuBarPresenter: {
                withDependencies {
                    $0.effectInteractor = effects
                    $0.controlsInteractor = controls
                } operation: {
                    MenuBarPresenter()
                }
            },
            makeSettingsPresenter: {
                withDependencies {
                    $0.settingsInteractor = settings
                } operation: {
                    SettingsPresenter()
                }
            },
            makeSettingsWindow: { presenter, onClose in
                let window = FakeSettingsWindow(presenter: presenter, onClose: onClose)
                windows.append(window)
                return window
            },
            makeCameraMenuPresenter: {
                withDependencies {
                    $0.cameraSelectionInteractor = camera
                } operation: {
                    CameraMenuPresenter()
                }
            },
            showsCameraMenu: showsCameraMenu)
    }
}
