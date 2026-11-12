import AppRouter
import Dependencies
import Domain
import Presenters
import TestDoubles
import TestSupport
import Testing

/// The Router's half of the effect parameter panel (#119): the window it opens from the menu router, the
/// panel's Presenter it starts and stops with that window, and the window's end, from the title bar or from
/// `stop()`. Every window here is a fake made through the window factories, so no suite opens a real one;
/// the live window's own glue is the last test, which makes one and never shows it.
@MainActor
@Suite("AppRouter: the parameter panel", .timeLimit(.minutes(1)))
struct AppRouterParameterPanelTests {
    private let chromatic = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))
    private let gain = EffectParameterState(
        spec: EffectParameterSpec(id: "gain", label: "Gain", kind: .float(min: 0, max: 1, step: nil, defaultValue: 0.5)),
        value: .float(0.5))

    @Test("the panel's Presenter is built with the Router, once; no window is made and it is not observing")
    func builtWithTheRouter() {
        let rig = ParameterRig(state: .fixture([chromatic], parameters: [gain]))

        #expect(rig.panelBuilds.count == 1)
        #expect(rig.windows.count == 0)
        #expect(rig.router.parameterPanelPresenter.isObserving == false)
    }

    @Test("opening the panel makes one window over the panel's Presenter, shows it and starts the Presenter")
    func openShowsThePanel() async throws {
        let rig = ParameterRig(state: .fixture([chromatic], parameters: [gain]))

        rig.router.openParameterPanel()

        let window = try #require(rig.windows.values.first)
        #expect(rig.windows.count == 1)
        #expect(window.presenter === rig.router.parameterPanelPresenter)
        #expect(window.shows == 1)
        #expect(rig.router.parameterPanelPresenter.isObserving)
        await settle(rig.router.parameterPanelPresenter.$rows) { !$0.isEmpty }
        #expect(rig.router.parameterPanelPresenter.rows.count == 1)
    }

    @Test("asking again while the panel is open brings the same window forward and makes no other")
    func openWhileOpenShowsTheSameWindow() throws {
        let rig = ParameterRig(state: .fixture([chromatic], parameters: [gain]))

        rig.router.openParameterPanel()
        rig.router.openParameterPanel()

        let window = try #require(rig.windows.values.first)
        #expect(rig.windows.count == 1)
        #expect(window.shows == 2)
    }

    @Test("closing the panel from its title bar stops its Presenter, and the next request makes a new window that starts it again")
    func titleBarCloseEndsThePanel() throws {
        let rig = ParameterRig(state: .fixture([chromatic], parameters: [gain]))
        rig.router.openParameterPanel()
        let first = try #require(rig.windows.values.first)

        first.closeFromTitleBar()

        #expect(rig.router.parameterPanelPresenter.isObserving == false, "the Presenter was stopped by the close")
        #expect(first.closes == 0, "the window closed itself; the Router does not close it again")
        rig.router.openParameterPanel()
        #expect(rig.windows.count == 2)
        #expect(first.shows == 1)
        #expect(rig.windows.values.last?.shows == 1)
        #expect(rig.router.parameterPanelPresenter.isObserving, "the new window started the Presenter again")
    }

    @Test("closeParameterPanel closes the open window once and stops the panel's Presenter; without a window it does nothing")
    func closeParameterPanelClosesTheWindow() throws {
        let rig = ParameterRig(state: .fixture([chromatic], parameters: [gain]))
        rig.router.closeParameterPanel()
        #expect(rig.windows.count == 0)
        rig.router.openParameterPanel()
        let window = try #require(rig.windows.values.first)
        #expect(rig.router.parameterPanelPresenter.isObserving)

        rig.router.closeParameterPanel()
        rig.router.closeParameterPanel()

        #expect(window.closes == 1)
        #expect(rig.router.parameterPanelPresenter.isObserving == false)
        rig.router.openParameterPanel()
        #expect(rig.windows.count == 2, "the closed window is not brought back")
    }

    @Test("a close reported by a window the Router has already let go leaves the open panel alone")
    func staleCloseIsIgnored() throws {
        let rig = ParameterRig(state: .fixture([chromatic], parameters: [gain]))
        rig.router.openParameterPanel()
        let first = try #require(rig.windows.values.first)
        rig.router.closeParameterPanel()
        rig.router.openParameterPanel()
        let second = try #require(rig.windows.values.last)

        first.closeFromTitleBar()

        #expect(rig.router.parameterPanelPresenter.isObserving, "the open panel's Presenter was not stopped")
        rig.router.openParameterPanel()
        #expect(rig.windows.count == 2)
        #expect(second.shows == 2, "the second window is still the open one")
    }

    @Test("stop closes the panel as well as the picker and the menu, and the panel's Presenter stops")
    func stopClosesThePanel() async throws {
        let rig = ParameterRig(state: .fixture([chromatic], parameters: [gain]))
        rig.router.start()
        await settle(rig.router.menuBarPresenter.$items) { !$0.isEmpty }
        rig.router.openEffectPicker()
        rig.router.openParameterPanel()
        let panel = try #require(rig.windows.values.first)
        let picker = try #require(rig.pickerWindows.values.first)

        rig.router.stop()

        #expect(panel.closes == 1)
        #expect(picker.closes == 1)
        #expect(rig.router.parameterPanelPresenter.isObserving == false)
        #expect(rig.interactor.stops.count == 1, "the panel never stops the Interactor; the menu's stop does")
    }

    @Test("the picker and the panel are independent: opening or closing one makes or closes no window of the other")
    func pickerAndPanelAreIndependent() throws {
        let rig = ParameterRig(state: .fixture([chromatic], parameters: [gain]))

        rig.router.openEffectPicker()
        #expect(rig.windows.count == 0, "opening the picker makes no panel window")
        #expect(rig.router.parameterPanelPresenter.isObserving == false)
        rig.router.openParameterPanel()
        let picker = try #require(rig.pickerWindows.values.first)
        let panel = try #require(rig.windows.values.first)

        rig.router.closeEffectPicker()
        #expect(picker.closes == 1)
        #expect(panel.closes == 0, "closing the picker leaves the panel open")
        #expect(rig.windows.count == 1)
        #expect(rig.router.parameterPanelPresenter.isObserving)

        rig.router.closeParameterPanel()
        #expect(panel.closes == 1)
        #expect(picker.closes == 1, "closing the panel closes no picker window")
        #expect(rig.pickerWindows.count == 1)
    }

    @Test("the default panel window is a ParameterPanelWindow over the Presenter, and its close reports that window; it is never shown")
    func liveWindowReportsItsClose() throws {
        let presenter = withDependencies {
            $0.effectInteractor = FakeEffectInteractor(state: .fixture([chromatic], parameters: [gain]))
        } operation: {
            ParameterPanelPresenter()
        }
        let closed = Collector<ObjectIdentifier>()

        let window = AppRouter.parameterWindow(over: presenter) { closed.append(ObjectIdentifier($0)) }
        // Never shown: closing a window that was never on screen still reports, and puts nothing on screen.
        window.close()

        let reported: [ObjectIdentifier] = closed.values
        #expect(window is ParameterPanelWindow)
        #expect(reported == [ObjectIdentifier(window)])
    }
}

/// The panel's window as the Router sees it. Like the live window, `close()` reports itself through
/// `onClose`; `closeFromTitleBar()` is a close the Router did not ask for.
@MainActor
private final class FakeParameterWindow {
    let presenter: ParameterPanelPresenter
    private let onClose: @MainActor (any ParameterWindow) -> Void
    private(set) var shows = 0
    private(set) var closes = 0

    init(presenter: ParameterPanelPresenter, onClose: @escaping @MainActor (any ParameterWindow) -> Void) {
        self.presenter = presenter
        self.onClose = onClose
    }

    func closeFromTitleBar() {
        onClose(self)
    }
}

extension FakeParameterWindow: ParameterWindow {
    func show() {
        shows += 1
    }

    func close() {
        closes += 1
        onClose(self)
    }
}

/// The picker's window, for the tests that open the picker beside the panel. It reports its close the way the live
/// window does, through the `onClose` it was made with.
@MainActor
private final class FakePickerWindow {
    private let onClose: @MainActor (any PickerWindow) -> Void
    private(set) var closes = 0

    init(onClose: @escaping @MainActor (any PickerWindow) -> Void) {
        self.onClose = onClose
    }
}

extension FakePickerWindow: PickerWindow {
    func show() {}

    func close() {
        closes += 1
        onClose(self)
    }
}

/// A Router whose Presenters talk to one `FakeEffectInteractor`, each built inside `withDependencies`, and whose
/// panel and picker windows are fakes, recorded in the order they were made.
@MainActor
private struct ParameterRig {
    let interactor: FakeEffectInteractor
    let panelBuilds = Collector<Void>()
    let windows = Collector<FakeParameterWindow>()
    let pickerWindows = Collector<FakePickerWindow>()
    let router: AppRouter

    init(state: EffectCatalogState) {
        self.init(interactor: FakeEffectInteractor(state: state))
    }

    init(interactor: FakeEffectInteractor) {
        let (panelBuilds, windows, pickerWindows) = (panelBuilds, windows, pickerWindows)
        self.interactor = interactor
        router = AppRouter(
            makeMenuBarPresenter: {
                withDependencies {
                    $0.effectInteractor = interactor
                    $0.controlsInteractor = FakeControlsInteractor()
                } operation: {
                    MenuBarPresenter()
                }
            },
            makeEffectPickerPresenter: {
                withDependencies {
                    $0.effectInteractor = interactor
                } operation: {
                    EffectPickerPresenter()
                }
            },
            makePickerWindow: { _, onClose in
                let window = FakePickerWindow(onClose: onClose)
                pickerWindows.append(window)
                return window
            },
            makeParameterPanelPresenter: {
                panelBuilds.append(())
                return withDependencies {
                    $0.effectInteractor = interactor
                } operation: {
                    ParameterPanelPresenter()
                }
            },
            makeParameterWindow: { presenter, onClose in
                let window = FakeParameterWindow(presenter: presenter, onClose: onClose)
                windows.append(window)
                return window
            })
    }
}
