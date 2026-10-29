import AppRouter
import Dependencies
import Domain
import Presenters
import TestDoubles
import TestSupport
import Testing
import Views

/// The Router's half of the effect picker (#12): the window it opens from the menu's *Browse Effects…*,
/// the picker's Presenter it starts and stops with that window, and the window's end, from the title bar
/// or from `stop()`. Every window here is a `FakePickerWindow` made through `makePickerWindow`, so no
/// suite opens a real one; the live window's own glue is the last test, which makes one and never shows it.
@MainActor
@Suite("AppRouter: the effect picker", .timeLimit(.minutes(1)))
struct AppRouterPickerTests {
    private let chromatic = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))
    private let glitch = EffectCatalogEntry.fixture(.package("glitch"), displayName: "Glitch")

    @Test("the picker's Presenter is built with the Router, once, and the Router is the menu's router; no window is made")
    func builtWithTheRouter() {
        let rig = PickerRig(state: .fixture([chromatic]))

        #expect(rig.pickerBuilds.count == 1)
        #expect(rig.windows.count == 0)
        #expect(rig.router.menuBarPresenter.router === rig.router)
        #expect(rig.router.effectPickerPresenter === rig.router.effectPickerPresenter)
    }

    @Test("Browse Effects… in the menu makes one window over the picker's Presenter, shows it and starts the Presenter")
    func browseOpensThePicker() async throws {
        let rig = PickerRig(state: .fixture([chromatic, glitch]))

        rig.router.menuBarPresenter.browseEffects()

        let window = try #require(rig.windows.values.first)
        #expect(rig.windows.count == 1)
        #expect(window.presenter === rig.router.effectPickerPresenter)
        #expect(window.shows == 1)
        await settle(rig.router.effectPickerPresenter.$cells) { $0.count == 2 }
        #expect(rig.router.effectPickerPresenter.cells.map(\.id) == [chromatic.id, glitch.id])
    }

    @Test("asking again while the picker is open brings the same window forward and makes no other")
    func openWhileOpenShowsTheSameWindow() throws {
        let rig = PickerRig(state: .fixture([chromatic]))

        rig.router.openEffectPicker()
        rig.router.openEffectPicker()
        rig.router.menuBarPresenter.browseEffects()

        let window = try #require(rig.windows.values.first)
        #expect(rig.windows.count == 1)
        #expect(window.shows == 3)
    }

    @Test("closing the window from its title bar stops the picker's Presenter, and the next request makes a new window")
    func titleBarCloseEndsThePicker() async throws {
        let rig = PickerRig(state: .fixture([chromatic]))
        rig.router.openEffectPicker()
        let first = try #require(rig.windows.values.first)
        await settle(rig.router.effectPickerPresenter.$cells) { !$0.isEmpty }
        rig.router.effectPickerPresenter.query = "chromatic"

        first.closeFromTitleBar()

        #expect(rig.router.effectPickerPresenter.query.isEmpty, "the Presenter was stopped: stopping is what clears the search")
        #expect(first.closes == 0, "the window closed itself; the Router does not close it again")
        rig.router.openEffectPicker()
        #expect(rig.windows.count == 2)
        #expect(first.shows == 1)
        #expect(rig.windows.values.last?.shows == 1)
    }

    @Test("closeEffectPicker closes the open window once and stops the picker's Presenter; without a window it does nothing")
    func closeEffectPickerClosesTheWindow() throws {
        let rig = PickerRig(state: .fixture([chromatic]))
        rig.router.closeEffectPicker()
        rig.router.openEffectPicker()
        let window = try #require(rig.windows.values.first)
        rig.router.effectPickerPresenter.query = "chromatic"

        rig.router.closeEffectPicker()
        rig.router.closeEffectPicker()

        #expect(window.closes == 1)
        #expect(rig.router.effectPickerPresenter.query.isEmpty)
        rig.router.openEffectPicker()
        #expect(rig.windows.count == 2, "the closed window is not brought back")
    }

    @Test("a close reported by a window the Router has already let go leaves the open one alone")
    func staleCloseIsIgnored() throws {
        let rig = PickerRig(state: .fixture([chromatic]))
        rig.router.openEffectPicker()
        let first = try #require(rig.windows.values.first)
        rig.router.closeEffectPicker()
        rig.router.openEffectPicker()
        let second = try #require(rig.windows.values.last)
        rig.router.effectPickerPresenter.query = "chromatic"

        first.closeFromTitleBar()

        #expect(rig.router.effectPickerPresenter.query == "chromatic", "the open picker's Presenter was not stopped")
        rig.router.openEffectPicker()
        #expect(rig.windows.count == 2)
        #expect(second.shows == 2, "the second window is still the open one")
    }

    @Test("stop closes the picker as well as the menu")
    func stopClosesThePicker() async throws {
        let rig = PickerRig(state: .fixture([chromatic]))
        rig.router.start()
        await settle(rig.router.menuBarPresenter.$items) { !$0.isEmpty }
        rig.router.openEffectPicker()
        let window = try #require(rig.windows.values.first)

        rig.router.stop()

        #expect(window.closes == 1)
        #expect(rig.interactor.stops.count == 1)
    }

    @Test("opening and closing the picker never starts or stops the Interactor: the menu's Presenter owns its run")
    func pickerLeavesTheInteractorAlone() async throws {
        let rig = PickerRig(state: .fixture([chromatic]))

        rig.router.openEffectPicker()
        await settle(rig.router.effectPickerPresenter.$cells) { !$0.isEmpty }
        try #require(rig.windows.values.first).closeFromTitleBar()
        rig.router.openEffectPicker()
        rig.router.closeEffectPicker()

        #expect(rig.interactor.starts.count == 0)
        #expect(rig.interactor.stops.count == 0)
    }

    @Test("a Router with the picker open that is let go stops the Interactor, as one with the menu alone does")
    func letGoWithThePickerOpen() async {
        let interactor = FakeEffectInteractor(state: .fixture([chromatic]))
        var rig: PickerRig? = await openedPickerRig(over: interactor)
        #expect(rig != nil)
        #expect(interactor.stops.count == 0)

        rig = nil

        #expect(interactor.stops.count == 1, "nothing the picker added keeps the Router or the menu's Presenter alive")
    }

    @Test("the live window is an EffectPickerWindow over the Presenter, and its close reports that window")
    func liveWindowReportsItsClose() throws {
        let presenter = withDependencies {
            $0.effectInteractor = FakeEffectInteractor(state: .fixture([chromatic]))
        } operation: {
            EffectPickerPresenter()
        }
        let closed = Collector<ObjectIdentifier>()

        let window = AppRouter.pickerWindow(over: presenter) { closed.append(ObjectIdentifier($0)) }
        // Never shown: closing a window that was never on screen still reports, and puts nothing on screen.
        window.close()

        let reported: [ObjectIdentifier] = closed.values
        #expect(window is EffectPickerWindow)
        #expect(reported == [ObjectIdentifier(window)])
    }
}

/// A rig whose menu is started and whose picker is open, both showing the catalog.
@MainActor
private func openedPickerRig(over interactor: FakeEffectInteractor) async -> PickerRig {
    let rig = PickerRig(interactor: interactor)
    rig.router.start()
    rig.router.openEffectPicker()
    await settle(rig.router.menuBarPresenter.$items) { !$0.isEmpty }
    await settle(rig.router.effectPickerPresenter.$cells) { !$0.isEmpty }
    return rig
}

/// The picker's window as the Router sees it. Like the live window, `close()` reports itself through
/// `onClose`; `closeFromTitleBar()` is a close the Router did not ask for.
@MainActor
private final class FakePickerWindow {
    let presenter: EffectPickerPresenter
    private let onClose: @MainActor (any PickerWindow) -> Void
    private(set) var shows = 0
    private(set) var closes = 0

    init(presenter: EffectPickerPresenter, onClose: @escaping @MainActor (any PickerWindow) -> Void) {
        self.presenter = presenter
        self.onClose = onClose
    }

    func closeFromTitleBar() {
        onClose(self)
    }
}

extension FakePickerWindow: PickerWindow {
    func show() {
        shows += 1
    }

    func close() {
        closes += 1
        onClose(self)
    }
}

/// A Router whose two Presenters talk to one `FakeEffectInteractor`, each built inside `withDependencies`,
/// and whose picker windows are `FakePickerWindow`s, recorded in the order they were made.
@MainActor
private struct PickerRig {
    let interactor: FakeEffectInteractor
    let pickerBuilds = Collector<Void>()
    let windows = Collector<FakePickerWindow>()
    let router: AppRouter

    init(state: EffectCatalogState) {
        self.init(interactor: FakeEffectInteractor(state: state))
    }

    init(interactor: FakeEffectInteractor) {
        let (pickerBuilds, windows) = (pickerBuilds, windows)
        self.interactor = interactor
        router = AppRouter(
            makeMenuBarPresenter: {
                withDependencies {
                    $0.effectInteractor = interactor
                } operation: {
                    MenuBarPresenter()
                }
            },
            makeEffectPickerPresenter: {
                pickerBuilds.append(())
                return withDependencies {
                    $0.effectInteractor = interactor
                } operation: {
                    EffectPickerPresenter()
                }
            },
            makePickerWindow: { presenter, onClose in
                let window = FakePickerWindow(presenter: presenter, onClose: onClose)
                windows.append(window)
                return window
            })
    }
}
