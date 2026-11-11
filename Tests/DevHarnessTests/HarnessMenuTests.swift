import AppKit
import AppRouter
import Dependencies
import Domain
import Presenters
import SwiftUI
import TestDoubles
import TestSupport
import Testing
import Views

@testable import DevHarness

/// The harness's main menu and the Router's lifecycle behind it, over a Router whose Presenter talks
/// to a `FakeEffectInteractor`. The Presenter is built inside `withDependencies` (it captures the
/// dependencies of the scope it is made in), and no test here resolves the Interactor live or builds a
/// Presenter outside such a scope (the override is `$0.effectInteractor = fake`): the live values of
/// the catalog belong to `HarnessLiveWiringTests` (`scripts/check-live-owner.sh`), which also takes the
/// default route, the menu's own `live()` factory.
@MainActor
@Suite("HarnessMenu", .timeLimit(.minutes(1)))
struct HarnessMenuTests {
    // MARK: - The main menu

    @Test("the application menu has Quit, bound to terminate and to ⌘Q")
    func applicationMenuHasQuit() throws {
        let rig = MenuRig()

        let appItem = try #require(rig.subject.mainMenu.items.first)
        let quit = try #require(appItem.submenu?.items.first)

        #expect(appItem.submenu?.items.count == 1)
        #expect(quit.title == "Quit")
        #expect(quit.action == #selector(NSApplication.terminate(_:)))
        #expect(quit.keyEquivalent == "q")
    }

    @Test("an Effects item follows the application menu, and its submenu is the one asked of the Router")
    func effectsItemHoldsTheHostedMenu() throws {
        let hosted = NSMenu(title: "hosted")
        let asked = Collector<ObjectIdentifier>()
        let rig = MenuRig(makeEffectsMenu: { router in
            asked.append(ObjectIdentifier(router))
            return hosted
        })

        let menu = rig.subject.mainMenu

        #expect(menu.items.count == 2)
        let effects = try #require(menu.items.last)
        #expect(effects.title == "Effects")
        #expect(effects.submenu === hosted)
        #expect(asked.values == [ObjectIdentifier(rig.router)], "the menu is hosted over the Router the harness owns")
    }

    @Test("a system that cannot host a SwiftUI menu has no Effects item, and the application menu is untouched")
    func noEffectsItemWithoutAHostedMenu() throws {
        let rig = MenuRig(makeEffectsMenu: { _ in nil })

        let menu = rig.subject.mainMenu

        #expect(menu.items.count == 1)
        #expect(menu.items.first?.submenu?.items.map(\.title) == ["Quit"])
    }

    @Test("by default the Effects menu is the host's EffectMenu in an NSHostingMenu, where the system has one")
    func defaultMenuIsTheHostingMenu() throws {
        guard #available(macOS 14.4, *) else { return }
        let rig = MenuRig()

        let effects = try #require(rig.subject.mainMenu.items.last)

        #expect(effects.title == "Effects")
        #expect(effects.submenu is NSHostingMenu<EffectMenu>)
    }

    @Test("reading the menu starts nothing: the Router is started by whoever owns the harness's lifecycle")
    func buildingTheMenuStartsNothing() {
        let rig = MenuRig()

        _ = rig.subject.mainMenu
        _ = rig.subject.mainMenu

        #expect(rig.interactor.starts.count == 0)
        #expect(rig.interactor.stops.count == 0)
    }

    // MARK: - The Router's lifecycle

    @Test("start starts the Router, which starts the Interactor once and fills the Presenter the menu draws from")
    func startStartsTheRouter() async {
        let rig = MenuRig()

        rig.subject.start()
        await settle(rig.router.menuBarPresenter.$items) { !$0.isEmpty }

        #expect(rig.interactor.starts.count == 1)
        #expect(rig.router.menuBarPresenter.items.map(\.id) == [.bundled("Chromatic Grain")])
    }

    @Test("stop stops the Router, which stops the Interactor")
    func stopStopsTheRouter() async {
        let rig = MenuRig()
        rig.subject.start()
        await settle(rig.router.menuBarPresenter.$items) { !$0.isEmpty }
        #expect(rig.interactor.stops.count == 0)

        rig.subject.stop()

        #expect(rig.interactor.stops.count == 1)
    }

    // MARK: - The menu's views

    @Test("the effects menu builds over a presenter that holds the bypass and the frame-rate line it draws above the rows")
    func effectMenuBuildsWithBypassAndReadout() async {
        let rig = MenuRig(controls: ControlsState(isBypassed: true, framesPerSecond: 30))
        rig.subject.start()
        let presenter = rig.router.menuBarPresenter
        await settle(presenter.$frameRateLine) { $0 != nil }

        #expect(presenter.isBypassed)
        #expect(presenter.frameRateLine == "30 fps")
        _ = EffectMenu(presenter: presenter).body
    }

    @Test("the effects menu builds with no frame-rate line while the pipeline is not running, and the bypass unchecked")
    func effectMenuBuildsWithoutReadout() async {
        let rig = MenuRig()
        rig.subject.start()
        let presenter = rig.router.menuBarPresenter
        await settle(presenter.$items) { !$0.isEmpty }

        #expect(presenter.frameRateLine == nil)
        #expect(!presenter.isBypassed)
        _ = EffectMenu(presenter: presenter).body
    }

    @Test("the menu bar label builds for the plain camera while the effect is bypassed")
    func menuBarLabelShowsThePlainCameraWhileBypassed() async {
        let rig = MenuRig(controls: ControlsState(isBypassed: true))
        rig.subject.start()
        let presenter = rig.router.menuBarPresenter
        await settle(presenter.$isBypassed) { $0 }

        #expect(presenter.iconName == "camera")
        _ = MenuBarLabel(presenter: presenter).body
    }

    @Test("the menu bar label builds for the filtered camera while nothing is bypassed and no attempt failed")
    func menuBarLabelShowsTheFilteredCamera() async {
        let rig = MenuRig()
        rig.subject.start()
        let presenter = rig.router.menuBarPresenter
        await settle(presenter.$items) { !$0.isEmpty }

        #expect(presenter.iconName == "camera.filters")
        _ = MenuBarLabel(presenter: presenter).body
    }
}

/// A `HarnessMenu` over a Router whose Presenter talks to a `FakeEffectInteractor`, and whose controls
/// state is `controls` (bypass and frame rate).
@MainActor
private struct MenuRig {
    let interactor: FakeEffectInteractor
    let router: AppRouter
    let subject: HarnessMenu

    /// `makeEffectsMenu` is the menu's default builder, `HarnessMenu.hostingMenu(for:)`, unless a test
    /// passes its own.
    init(
        controls: ControlsState = ControlsState(),
        makeEffectsMenu: @escaping @MainActor (AppRouter) -> NSMenu? = HarnessMenu.hostingMenu(for:)
    ) {
        let interactor = FakeEffectInteractor(state: .fixture([.fixture(.bundled("Chromatic Grain"))]))
        let router = AppRouter(makeMenuBarPresenter: {
            withDependencies {
                $0.effectInteractor = interactor
                $0.controlsInteractor = FakeControlsInteractor(state: controls)
            } operation: {
                MenuBarPresenter()
            }
        })
        self.interactor = interactor
        self.router = router
        subject = HarnessMenu(router: router, makeEffectsMenu: makeEffectsMenu)
    }
}
