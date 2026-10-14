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
        let rig = PresenterRig(state: .fixture([chromatic, glitch, broken]))

        await rig.start()

        #expect(rig.presenter.items.map(\.id) == [.bundled("Chromatic Grain"), .package("glitch"), .package("old")])
        #expect(rig.presenter.items.map(\.title) == ["Chromatic Grain", "Glitch", "old"])
    }

    @Test("exactly the chosen effect is selected")
    func selectionFlag() async {
        let state = EffectCatalogState(entries: [chromatic, glitch, broken], selection: .package("glitch"))
        let rig = PresenterRig(state: state)

        await rig.start()

        #expect(rig.presenter.items.map(\.isSelected) == [false, true, false])
    }

    @Test("a package that failed to load is disabled and says why; a ready one is enabled")
    func brokenIsDisabledWithItsReason() async {
        let rig = PresenterRig(state: .fixture([chromatic, glitch, broken]))

        await rig.start()

        #expect(rig.presenter.items.map(\.isEnabled) == [true, true, false])
        #expect(rig.presenter.items.last?.detail == "manifest.json is invalid: no name")
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

    @Test("stop ends the observation and stops the Interactor: later states change nothing")
    func stopEndsObservation() async {
        let rig = PresenterRig(state: .fixture([chromatic]))
        await rig.start()
        let shown = rig.presenter.items

        rig.presenter.stop()
        await rig.interactor.cancellations.waitForCount(1)
        rig.interactor.inner.publish(.fixture([chromatic, glitch]))

        #expect(rig.interactor.inner.stops.count == 1)
        #expect(rig.presenter.items == shown, "the subscription was gone before the state was published")
    }

    @Test("a Presenter can be started again after stop, and shows the Interactor's state then")
    func restartAfterStop() async {
        let rig = PresenterRig(state: .fixture([chromatic]))
        await rig.start()
        rig.presenter.stop()
        await rig.interactor.cancellations.waitForCount(1)
        rig.interactor.inner.publish(.fixture([chromatic, glitch]))

        rig.presenter.start()
        await settle(rig.presenter.$items) { $0.count == 2 }

        #expect(rig.interactor.inner.starts.count == 2)
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
        presenter = withDependencies {
            $0.effectInteractor = interactor
        } operation: {
            MenuBarPresenter()
        }
    }

    /// Starts the Presenter and waits for the first state to reach the rows.
    func start() async {
        presenter.start()
        await settle(presenter.$items) { !$0.isEmpty }
    }
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
