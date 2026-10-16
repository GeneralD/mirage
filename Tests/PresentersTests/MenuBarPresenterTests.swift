import Combine
import Dependencies
import Domain
import Presenters
import TestDoubles
import TestSupport
import Testing

@MainActor
@Suite("MenuBarPresenter", .timeLimit(.minutes(1)))
struct MenuBarPresenterTests {
    private let chromatic = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))
    private let glitch = EffectCatalogEntry.fixture(.package("glitch"), displayName: "Glitch", author: "Ada")
    private let broken = EffectCatalogEntry.fixture(
        .package("old"), displayName: "old", availability: .broken(.manifestInvalid(message: "no name")))

    /// A catalog whose order is neither the display names' nor the keys' in any collation (the
    /// bundled effect first, then a package by lowercase name, then one by capitalised name), so a
    /// Presenter that sorted or regrouped the rows would show a different order.
    private let zeta = EffectCatalogEntry.fixture(.bundled("Zeta"))
    private let alpha = EffectCatalogEntry.fixture(.package("alpha"), author: "Ada")
    private let beta = EffectCatalogEntry.fixture(.package("Beta"), availability: .broken(.manifestInvalid(message: "no name")))

    // MARK: - Items

    @Test("nothing is shown, and nothing is asked of the Interactor, until the Presenter starts")
    func quietBeforeStart() {
        let rig = PresenterRig(state: .fixture([chromatic]))

        #expect(rig.presenter.items.isEmpty)
        #expect(rig.presenter.status == nil)
        #expect(rig.interactor.starts.count == 0)
    }

    @Test("the rows follow the catalog's order, the bundled effect first, one row per entry")
    func rowsInCatalogOrder() async {
        let rig = PresenterRig(state: .fixture([zeta, alpha, beta]))

        await rig.start()

        #expect(rig.presenter.items.map(\.id) == [.bundled("Zeta"), .package("alpha"), .package("Beta")])
        #expect(rig.presenter.items.map(\.title) == ["Zeta", "alpha", "Beta"])
    }

    @Test("exactly the chosen effect is selected")
    func selectionFlag() async {
        let state = EffectCatalogState(entries: [zeta, alpha, beta], selection: .package("alpha"))
        let rig = PresenterRig(state: state)

        await rig.start()

        #expect(rig.presenter.items.map(\.isSelected) == [false, true, false])
    }

    @Test("a package that failed to load is disabled and says why; a ready one is enabled")
    func brokenIsDisabledWithItsReason() async {
        let rig = PresenterRig(state: .fixture([zeta, alpha, beta]))

        await rig.start()

        #expect(rig.presenter.items.map(\.isEnabled) == [true, true, false])
        #expect(rig.presenter.items.map(\.detail) == [nil, "Ada", "manifest.json is invalid: no name"])
    }

    @Test("a ready package's detail is its author; without one there is no detail")
    func authorIsTheDetail() async {
        let rig = PresenterRig(state: .fixture([chromatic, glitch]))

        await rig.start()

        #expect(rig.presenter.items.map(\.detail) == [nil, "Ada"])
    }

    @Test(
        "every reason a package can be unusable has its own wording",
        arguments: [
            (EffectPackageProblem.manifestMissing, "manifest.json is missing"),
            (.manifestInvalid(message: "bad json"), "manifest.json is invalid: bad json"),
            (.unsupportedFormatVersion(7), "unsupported formatVersion 7"),
            (.sourceMissing, "effect.metal is missing"),
            (.unreadable(message: "permission denied"), "cannot be read: permission denied"),
        ])
    func problemWording(problem: EffectPackageProblem, wording: String) async {
        let entry = EffectCatalogEntry.fixture(.package("p"), availability: .broken(problem))
        let rig = PresenterRig(state: .fixture([chromatic, entry]))

        await rig.start()

        #expect(rig.presenter.items.last?.detail == wording)
    }

    @Test("a later state replaces the rows, and a state that changes nothing is not published again")
    func laterStateReplacesRows() async {
        let rig = PresenterRig(state: .fixture([chromatic]))
        await rig.start()

        rig.interactor.publish(.fixture([chromatic, glitch]))
        await settle(rig.presenter.$items) { $0.count == 2 }
        #expect(rig.presenter.items.map(\.id) == [.bundled("Chromatic Grain"), .package("glitch")])

        let published = Collector<[EffectMenuItem]>()
        let subscription = rig.presenter.$items.dropFirst().sink { published.append($0) }
        rig.interactor.publish(.fixture([chromatic, glitch]))
        rig.interactor.publish(.fixture([glitch]))
        await settle(rig.presenter.$items) { $0.count == 1 }
        #expect(published.values.map(\.count) == [1], "the repeated state published no rows of its own")
        withExtendedLifetime(subscription) {}
    }

    // MARK: - Status

    @Test(
        "status is one line about the chosen effect when the last attempt did not succeed, and nil otherwise",
        arguments: [
            (EffectSelectionOutcome?.none, String?.none),
            (.prepared, nil),
            (.failed(.compileFailed), "Chromatic Grain: compile failed"),
            (.failed(.timeout), "Chromatic Grain: timed out"),
            (.failed(.pageFault), "Chromatic Grain: GPU page fault"),
            (.failed(.accessRevoked), "Chromatic Grain: GPU access revoked"),
            (.failed(.outOfMemory), "Chromatic Grain: out of memory"),
            (.failed(.invalidResource), "Chromatic Grain: invalid GPU resource"),
            (.failed(.internalError), "Chromatic Grain: internal error"),
            (.failed(.unknown(code: 42)), "Chromatic Grain: unknown error (42)"),
            (.unavailable(.sourceMissing), "Chromatic Grain: effect.metal is missing"),
            (.unavailable(nil), "Chromatic Grain: no longer available"),
        ])
    func statusLine(outcome: EffectSelectionOutcome?, expected: String?) async {
        let rig = PresenterRig(state: .fixture([chromatic], outcome: outcome))

        await rig.start()

        #expect(rig.presenter.status == expected)
    }

    @Test("status names the chosen effect by its display name, and by its key once the catalog no longer lists it")
    func statusNamesTheChosenEffect() async {
        let named = EffectCatalogState(entries: [chromatic, glitch], selection: .package("glitch"), outcome: .failed(.compileFailed))
        let rig = PresenterRig(state: named)
        await rig.start()
        #expect(rig.presenter.status == "Glitch: compile failed")

        rig.interactor.publish(EffectCatalogState(entries: [chromatic], selection: .package("gone"), outcome: .unavailable(nil)))
        await settle(rig.presenter.$status) { $0 == "gone: no longer available" }
        #expect(rig.presenter.status == "gone: no longer available")
    }

    @Test("a failure that is fixed clears the status")
    func fixedFailureClearsStatus() async {
        let rig = PresenterRig(state: .fixture([chromatic], outcome: .failed(.compileFailed)))
        await rig.start()
        #expect(rig.presenter.status == "Chromatic Grain: compile failed")

        rig.interactor.publish(.fixture([chromatic], outcome: .prepared))
        await settle(rig.presenter.$status) { $0 == nil }

        #expect(rig.presenter.status == nil)
    }

    // MARK: - Commands

    @Test("select goes to the Interactor, whichever row it is and whether or not the row is enabled")
    func selectGoesToTheInteractor() async {
        let rig = PresenterRig(state: .fixture([chromatic, glitch, broken]))
        await rig.start()

        rig.presenter.select(.package("glitch"))
        rig.presenter.select(.package("old"))

        #expect(rig.interactor.selections.values == [.package("glitch"), .package("old")])
    }

    @Test("openEffectsFolder goes to the Interactor")
    func openEffectsFolderGoesToTheInteractor() {
        let rig = PresenterRig(state: .fixture([chromatic]))

        rig.presenter.openEffectsFolder()

        #expect(rig.interactor.folderOpens.count == 1)
    }

    // MARK: - Lifecycle

    @Test("start starts the Interactor once, however many times it is called")
    func startIsIdempotent() async {
        let rig = PresenterRig(state: .fixture([chromatic]))

        rig.presenter.start()
        rig.presenter.start()
        await settle(rig.presenter.$items) { !$0.isEmpty }

        #expect(rig.interactor.inner.starts.count == 1)
    }

    @Test("stop cancels the subscription to the Interactor's state and stops the Interactor")
    func stopEndsObservation() async {
        let rig = PresenterRig(state: .fixture([chromatic]))
        await rig.start()
        #expect(rig.interactor.cancellations.count == 0)

        rig.presenter.stop()

        // Both happen inside stop(), on the main actor the test is running on: there is nothing to wait for.
        #expect(rig.interactor.cancellations.count == 1, "the subscription was cancelled")
        #expect(rig.interactor.inner.stops.count == 1)
    }

    @Test("a state that was already on its way when stop was called is never applied")
    func stopDropsTheStateOnItsWay() async {
        let rig = PresenterRig(state: .fixture([chromatic]))
        await rig.start()
        let shown = Collector<[EffectID]>()
        let subscription = rig.presenter.$items.dropFirst().sink { shown.append($0.map(\.id)) }

        // The test holds the main actor from the first publish to the wait below, so the task that
        // applies states has not run: the state is on its way to the rows when stop() lands.
        rig.interactor.publish(.fixture([chromatic, glitch]))
        rig.presenter.stop()
        // What the restart begins from must differ from that state: a restarted subscription
        // replays the Interactor's current one, which would hide an application of the first.
        rig.interactor.publish(.fixture([glitch]))
        rig.presenter.start()
        await settle(rig.presenter.$items) { $0.map(\.id) == [.package("glitch")] }

        // The stopped observation's task was queued on the main actor ahead of the restarted
        // one, so an application of the stale state would have been published before this one.
        #expect(shown.values == [[.package("glitch")]], "the rows went from the state before stop straight to the restart's")
        withExtendedLifetime(subscription) {}
    }

    @Test("a Presenter can be started again after stop, and shows the Interactor's state then")
    func restartAfterStop() async {
        let rig = PresenterRig(state: .fixture([chromatic]))
        await rig.start()
        rig.presenter.stop()
        #expect(rig.interactor.cancellations.count == 1, "nobody was subscribed when the state below was published")
        rig.interactor.inner.publish(.fixture([chromatic, glitch]))

        rig.presenter.start()
        await settle(rig.presenter.$items) { $0.count == 2 }

        #expect(rig.interactor.inner.starts.count == 2)
    }

    // Releasing a Presenter releases the run it holds on the thread the test is running on, so like
    // `stop()` it has happened by the time the assignment returns: there is nothing to wait for, and a
    // release that hopped somewhere else would fail the first of these.
    //
    // What these read is the Interactor's stops. The observation task the release also ends (the run
    // ends it the same way `stop()` does) is parked on a stream nothing can reach any more, so no test
    // can see whether it ended; `stopEndsObservation` and `stopDropsTheStateOnItsWay` pin what `stop()` ends.

    @Test("a started Presenter that is let go stops the Interactor")
    func letGoWhileStartedStops() async {
        let interactor = SpyEffectInteractor(FakeEffectInteractor(state: .fixture([chromatic])))
        var presenter: MenuBarPresenter? = await startedPresenter(over: interactor)
        weak let letGo = presenter
        #expect(interactor.inner.stops.count == 0)

        presenter = nil

        #expect(letGo == nil, "nothing else holds the Presenter, so the stop below is its release's")
        #expect(interactor.inner.stops.count == 1)
    }

    @Test("a Presenter that was never started asks nothing of the Interactor when it is let go")
    func letGoBeforeStartIsQuiet() async {
        let interactor = SpyEffectInteractor(FakeEffectInteractor(state: .fixture([chromatic])))

        _ = makePresenter(over: interactor)
        // A started Presenter let go afterwards shows that a release does reach the Interactor, so
        // the single stop below is the started one's and the idle one's silence is not a deinit that never ran.
        _ = await startedPresenter(over: interactor)

        #expect(interactor.inner.stops.count == 1)
    }

    @Test("a Presenter that was stopped does not stop the Interactor a second time when it is let go")
    func letGoAfterStopIsQuiet() async {
        let interactor = SpyEffectInteractor(FakeEffectInteractor(state: .fixture([chromatic])))
        var presenter: MenuBarPresenter? = await startedPresenter(over: interactor)
        presenter?.stop()
        #expect(interactor.inner.stops.count == 1)

        presenter = nil

        #expect(interactor.inner.stops.count == 1)
    }
}

/// A Presenter over a `FakeEffectInteractor` the test publishes into, built inside
/// `withDependencies` (the Presenter captures the dependencies of the scope it is made in).
@MainActor
private struct PresenterRig {
    let interactor: SpyEffectInteractor
    let presenter: MenuBarPresenter

    init(state: EffectCatalogState) {
        let interactor = SpyEffectInteractor(FakeEffectInteractor(state: state))
        self.interactor = interactor
        presenter = makePresenter(over: interactor)
    }

    /// Starts the Presenter and waits for the first state to reach the rows.
    func start() async {
        presenter.start()
        await settle(presenter.$items) { !$0.isEmpty }
    }
}

/// A Presenter over `interactor`, built inside `withDependencies` (see `PresenterRig`).
@MainActor
private func makePresenter(over interactor: SpyEffectInteractor) -> MenuBarPresenter {
    withDependencies {
        $0.effectInteractor = interactor
    } operation: {
        MenuBarPresenter()
    }
}

/// A started Presenter whose first state has reached the rows; the caller holds the only
/// reference, so a test lets go of it by dropping that one.
@MainActor
private func startedPresenter(over interactor: SpyEffectInteractor) async -> MenuBarPresenter {
    let presenter = makePresenter(over: interactor)
    presenter.start()
    await settle(presenter.$items) { !$0.isEmpty }
    return presenter
}

/// A `FakeEffectInteractor` that also counts its `state` subscriptions that were cancelled,
/// which is how a test proves that a Presenter let go of the publisher.
private final class SpyEffectInteractor: EffectInteractor, Sendable {
    let inner: FakeEffectInteractor
    /// One entry per `state` subscription that was cancelled.
    let cancellations = Collector<Void>()

    init(_ inner: FakeEffectInteractor) {
        self.inner = inner
    }

    var state: AnyPublisher<EffectCatalogState, Never> {
        let cancellations = cancellations
        return inner.state.handleEvents(receiveCancel: { cancellations.append(()) }).eraseToAnyPublisher()
    }

    func publish(_ state: EffectCatalogState) { inner.publish(state) }
    func start() { inner.start() }
    func stop() { inner.stop() }
    func select(_ id: EffectID) { inner.select(id) }
    func openEffectsFolder() { inner.openEffectsFolder() }

    var starts: Collector<Void> { inner.starts }
    var selections: Collector<EffectID> { inner.selections }
    var folderOpens: Collector<Void> { inner.folderOpens }
}
