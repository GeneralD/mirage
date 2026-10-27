import AppRouter
import Dependencies
import Domain
import Presenters
import TestDoubles
import TestSupport
import Testing

@MainActor
@Suite("AppRouter", .timeLimit(.minutes(1)))
struct AppRouterTests {
    private let chromatic = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))

    // MARK: - The Presenter

    @Test("the Presenter is built when the Router is, once, and nothing is started or asked of the Interactor then")
    func presenterIsBuiltOnceAndQuiet() {
        let rig = RouterRig(state: .fixture([chromatic]))

        #expect(rig.builds.count == 1)
        #expect(rig.interactor.starts.count == 0)
        #expect(rig.interactor.stops.count == 0)
        #expect(rig.router.menuBarPresenter.items.isEmpty)
    }

    @Test("every read of menuBarPresenter is the one Presenter, and the factory is not asked again")
    func presenterIsOneInstance() {
        let rig = RouterRig(state: .fixture([chromatic]))

        let reads = (0..<3).map { _ in ObjectIdentifier(rig.router.menuBarPresenter) }
        rig.router.start()
        rig.router.stop()
        rig.router.start()
        let readAfterwards = ObjectIdentifier(rig.router.menuBarPresenter)

        #expect(Set(reads + [readAfterwards]).count == 1)
        #expect(rig.builds.count == 1)
    }

    @Test("the Router hands out the Presenter its factory made")
    func presenterIsTheFactorysOwn() {
        let interactor = FakeEffectInteractor(state: .fixture([chromatic]))
        let made = Collector<ObjectIdentifier>()
        let router = AppRouter(makeMenuBarPresenter: {
            let presenter = makePresenter(over: interactor)
            made.append(ObjectIdentifier(presenter))
            return presenter
        })

        #expect(made.values == [ObjectIdentifier(router.menuBarPresenter)])
    }

    @Test("the default factory builds a Presenter over the Interactor of the scope the Router is made in")
    func defaultFactoryUsesTheScopeOfTheConstruction() {
        let interactor = FakeEffectInteractor(state: .fixture([chromatic]))
        let router = withDependencies {
            $0.effectInteractor = interactor
        } operation: {
            AppRouter()
        }

        router.start()

        #expect(interactor.starts.count == 1)
    }

    // MARK: - Lifecycle

    @Test("start starts the Interactor once, however many times it is called")
    func startIsIdempotent() async {
        let rig = RouterRig(state: .fixture([chromatic]))

        rig.router.start()
        rig.router.start()
        await settle(rig.router.menuBarPresenter.$items) { !$0.isEmpty }

        #expect(rig.interactor.starts.count == 1)
    }

    @Test("start brings the catalog's rows into the Presenter the View draws from")
    func startFillsThePresenter() async {
        let rig = RouterRig(state: .fixture([chromatic]))

        rig.router.start()
        await settle(rig.router.menuBarPresenter.$items) { !$0.isEmpty }

        #expect(rig.router.menuBarPresenter.items.map(\.id) == [.bundled("Chromatic Grain")])
    }

    @Test("stop stops the Interactor")
    func stopStopsTheInteractor() async {
        let rig = RouterRig(state: .fixture([chromatic]))
        rig.router.start()
        await settle(rig.router.menuBarPresenter.$items) { !$0.isEmpty }
        #expect(rig.interactor.stops.count == 0)

        rig.router.stop()

        #expect(rig.interactor.stops.count == 1)
    }

    @Test("stopping twice, or before any start, starts nothing")
    func extraStopsStartNothing() {
        let rig = RouterRig(state: .fixture([chromatic]))

        rig.router.stop()
        rig.router.start()
        rig.router.stop()
        rig.router.stop()

        #expect(rig.interactor.starts.count == 1, "only the one start the test asked for")
    }

    @Test("a stopped Router can start again, and that start reaches the Interactor")
    func restartAfterStop() async {
        let rig = RouterRig(state: .fixture([chromatic]))
        rig.router.start()
        rig.router.stop()

        rig.router.start()
        await settle(rig.router.menuBarPresenter.$items) { !$0.isEmpty }

        #expect(rig.interactor.starts.count == 2)
    }

    @Test("a started Router that is let go stops the Interactor: it holds nothing that would keep the Presenter alive")
    func letGoWhileStartedStops() async {
        let interactor = FakeEffectInteractor(state: .fixture([chromatic]))
        var router: AppRouter? = await startedRouter(over: interactor)
        #expect(router != nil)
        #expect(interactor.stops.count == 0)

        router = nil

        #expect(interactor.stops.count == 1)
    }
}

/// A Router whose Presenter talks to a `FakeEffectInteractor`: the factory builds the Presenter inside
/// `withDependencies` (the Presenter captures the dependencies of the scope it is made in), and counts
/// how often the Router asked for one.
@MainActor
private struct RouterRig {
    let interactor: FakeEffectInteractor
    let builds = Collector<Void>()
    let router: AppRouter

    init(state: EffectCatalogState) {
        let interactor = FakeEffectInteractor(state: state)
        let builds = builds
        self.interactor = interactor
        router = AppRouter(makeMenuBarPresenter: {
            builds.append(())
            return makePresenter(over: interactor)
        })
    }
}

/// A Presenter over `interactor`, built inside `withDependencies` (see `RouterRig`).
@MainActor
private func makePresenter(over interactor: FakeEffectInteractor) -> MenuBarPresenter {
    withDependencies {
        $0.effectInteractor = interactor
    } operation: {
        MenuBarPresenter()
    }
}

/// A started Router whose first state has reached the rows; the caller holds the only reference,
/// so a test lets go of it by dropping that one.
@MainActor
private func startedRouter(over interactor: FakeEffectInteractor) async -> AppRouter {
    let router = withDependencies {
        $0.effectInteractor = interactor
    } operation: {
        AppRouter()
    }
    router.start()
    await settle(router.menuBarPresenter.$items) { !$0.isEmpty }
    return router
}
