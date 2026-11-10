import Combine
import Dependencies
import Domain
import Presenters
import TestDoubles
import TestSupport
import Testing

@MainActor @Suite("ParameterPanelPresenter", .timeLimit(.minutes(1)))
struct ParameterPanelPresenterTests {
    @Test("nothing is shown, and nothing is asked of the Interactor, until the Presenter starts")
    func quietBeforeStart() {
        let rig = PanelRig(state: panel("Ripple", ripplePair))

        #expect(rig.presenter.rows.isEmpty)
        #expect(rig.presenter.heading.isEmpty)
        #expect(rig.presenter.emptyMessage == nil)
        #expect(!rig.presenter.isObserving)
        #expect(rig.interactor.starts.count == 0)
    }

    @Test("start shows the chosen effect's parameters as rows, in declaration order, under its name")
    func rowsInDeclarationOrder() async {
        let rig = PanelRig(state: panel("Ripple", ripplePair))

        await rig.start()

        #expect(rig.presenter.heading == "Ripple")
        #expect(rig.presenter.rows == ripplePairRows)
        #expect(rig.presenter.emptyMessage == nil)
    }

    @Test("the heading is the chosen effect's display name, or its key when the listing has no entry for it")
    func headingFallsBackToTheKey() async {
        let state = EffectCatalogState(entries: [chromatic], selection: .package("ripple"), parameters: ripplePair)
        let rig = PanelRig(state: state)

        await rig.start()

        #expect(rig.presenter.heading == "ripple")
    }

    @Test("an effect with no parameters has no rows, and the empty message names it")
    func noParametersSaysSoByName() async {
        let rig = PanelRig(state: .fixture([chromatic]))

        await rig.start()

        #expect(rig.presenter.rows.isEmpty)
        #expect(rig.presenter.emptyMessage == "Chromatic Grain has no parameters")
    }

    @Test("an effect whose parameters cannot be drawn has no rows, and the same empty message")
    func undrawableParametersSayNoParameters() async {
        let dead = EffectParameterState(
            spec: EffectParameterSpec(id: "dead", label: "Dead", kind: .float(min: 1, max: 1, step: nil, defaultValue: 1)),
            value: .float(1))
        let rig = PanelRig(state: panel("Ripple", [dead]))

        await rig.start()

        #expect(rig.presenter.rows.isEmpty)
        #expect(rig.presenter.emptyMessage == "Ripple has no parameters")
    }

    @Test("a new state replaces the rows, and choosing an effect with no parameters leaves none")
    func newStateReplacesTheRows() async {
        let rig = PanelRig(state: panel("Ripple", ripplePair))
        await rig.start()

        rig.interactor.publish(panel("Ripple", [EffectParameterState(spec: .inverted, value: .bool(false))]))
        await settle(rig.presenter.$rows) { $0.count == 1 }
        #expect(rig.presenter.rows == [ParameterPanelRow(id: "inverted", label: "Inverted", control: .toggle(isOn: false))])

        rig.interactor.publish(.fixture([chromatic]))
        await settle(rig.presenter.$emptyMessage) { $0 != nil }
        #expect(rig.presenter.rows.isEmpty)
        #expect(rig.presenter.heading == "Chromatic Grain")
        #expect(rig.presenter.emptyMessage == "Chromatic Grain has no parameters")
    }

    @Test("rows are not published again when a state changes only the heading")
    func headingOnlyChangeKeepsTheRows() async {
        let rig = PanelRig(state: panel("Ripple", ripplePair))
        let published = Collector<[ParameterPanelRow]>()
        let subscription = rig.presenter.$rows.sink { published.append($0) }

        await rig.start()
        rig.interactor.publish(panel("Ripple Mk II", ripplePair))
        await settle(rig.presenter.$heading) { $0 == "Ripple Mk II" }

        #expect(
            published.values == [[], ripplePairRows],
            "the empty rows the subscription got, then the first rows; the renamed state published no rows of its own")
        withExtendedLifetime(subscription) {}
    }

    @Test("the window is titled Adjust Effect, and its reset button reads Reset")
    func titles() {
        let rig = PanelRig(state: panel("Ripple", ripplePair))

        #expect(rig.presenter.windowTitle == "Adjust Effect")
        #expect(rig.presenter.resetTitle == "Reset")
    }

    @Test("the Presenter never starts, stops or selects the Interactor")
    func onlyObserves() async {
        let rig = PanelRig(state: panel("Ripple", ripplePair))

        await rig.start()
        rig.presenter.stop()

        #expect(rig.interactor.starts.count == 0)
        #expect(rig.interactor.stops.count == 0)
        #expect(rig.interactor.selections.count == 0)
    }

    @Test("start subscribes once however many times it is called, and stop ends that subscription")
    func startSubscribesOnce() async {
        let rig = PanelRig(state: panel("Ripple", ripplePair))

        rig.presenter.start()
        rig.presenter.start()
        #expect(rig.presenter.isObserving)
        await settle(rig.presenter.$heading) { !$0.isEmpty }
        rig.presenter.stop()

        #expect(!rig.presenter.isObserving)
        #expect(rig.interactor.cancellations.count == 1, "one subscription was made, and stop ended it")
    }

    @Test("a state that was on its way when stop was called is never applied")
    func stopDropsTheStateOnItsWay() async {
        let rig = PanelRig(state: panel("Ripple", ripplePair))
        await rig.start()
        let shown = Collector<[ParameterPanelRow]>()
        let subscription = rig.presenter.$rows.dropFirst().sink { shown.append($0) }

        // The test holds the main actor from the first publish to the wait below, so the task that
        // applies states has not run: the state is on its way to the rows when stop() lands.
        rig.interactor.publish(panel("Ripple", [EffectParameterState(spec: .inverted, value: .bool(false))]))
        rig.presenter.stop()
        // What the restart begins from must differ from that state: a restarted subscription replays the
        // Interactor's current one, which would hide an application of the first.
        rig.interactor.publish(panel("Ripple", [EffectParameterState(spec: .strength, value: .float(0.5))]))
        rig.presenter.start()
        await settle(rig.presenter.$rows) { $0.map(\.id) == ["strength"] }

        #expect(shown.values.map { $0.map(\.id) } == [["strength"]], "the rows went straight from the last applied state to the restart's")
        withExtendedLifetime(subscription) {}
    }

    @Test("start after stop observes again, from the state the Interactor holds")
    func startAfterStopObservesAgain() async {
        let rig = PanelRig(state: panel("Ripple", ripplePair))
        await rig.start()
        rig.presenter.stop()
        rig.interactor.publish(panel("Ripple Mk II", ripplePair))

        rig.presenter.start()
        #expect(rig.presenter.isObserving)
        await settle(rig.presenter.$heading) { $0 == "Ripple Mk II" }

        #expect(rig.interactor.cancellations.count == 1, "the first subscription was ended by stop")
    }

    @Test("a started Presenter that is let go ends its subscription, and stops nothing")
    func letGoWhileStartedEndsTheSubscription() async {
        let interactor = SpyEffectInteractor(FakeEffectInteractor(state: panel("Ripple", ripplePair)))
        var presenter: ParameterPanelPresenter? = await startedPanel(over: interactor)
        weak let letGo = presenter
        #expect(interactor.cancellations.count == 0)

        presenter = nil

        #expect(letGo == nil, "nothing else holds the Presenter, so the cancellation below is its release's")
        #expect(interactor.cancellations.count == 1)
        #expect(interactor.stops.count == 0)
    }
}

private let chromatic = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))

/// The Ripple example's two parameters as the Interactor holds them: strength at 0.25 and inverted on.
private let ripplePair: [EffectParameterState] = [
    EffectParameterState(spec: .strength, value: .float(0.25)),
    EffectParameterState(spec: .inverted, value: .bool(true)),
]

/// The rows `ripplePair` draws, in the same order.
private let ripplePairRows: [ParameterPanelRow] = [
    ParameterPanelRow(
        id: "strength", label: "Strength",
        control: .slider(
            ParameterPanelSlider(title: "Strength", caption: nil, value: 0.25, range: 0...1, step: 0.25, text: "0.25"))),
    ParameterPanelRow(id: "inverted", label: "Inverted", control: .toggle(isOn: true)),
]

/// A state whose chosen effect is a package named `name`, with `parameters` for that choice.
private func panel(_ name: String, _ parameters: [EffectParameterState]) -> EffectCatalogState {
    EffectCatalogState(
        entries: [EffectCatalogEntry.fixture(.package("ripple"), displayName: name)], selection: .package("ripple"),
        parameters: parameters)
}

/// A panel Presenter over a `FakeEffectInteractor` the test publishes into, built inside
/// `withDependencies` (the Presenter captures the dependencies of the scope it is made in).
@MainActor
private struct PanelRig {
    let interactor: SpyEffectInteractor
    let presenter: ParameterPanelPresenter

    init(state: EffectCatalogState) {
        let interactor = SpyEffectInteractor(FakeEffectInteractor(state: state))
        self.interactor = interactor
        presenter = makePanel(over: interactor)
    }

    /// Starts the Presenter and waits for the first state to reach the heading.
    func start() async {
        presenter.start()
        await settle(presenter.$heading) { !$0.isEmpty }
    }
}

/// A panel Presenter over `interactor`, built inside `withDependencies` (see `PanelRig`).
@MainActor
private func makePanel(over interactor: SpyEffectInteractor) -> ParameterPanelPresenter {
    withDependencies {
        $0.effectInteractor = interactor
    } operation: {
        ParameterPanelPresenter()
    }
}

/// A started panel Presenter whose first state has reached the heading; the caller holds the only
/// reference, so a test lets go of it by dropping that one.
@MainActor
private func startedPanel(over interactor: SpyEffectInteractor) async -> ParameterPanelPresenter {
    let presenter = makePanel(over: interactor)
    presenter.start()
    await settle(presenter.$heading) { !$0.isEmpty }
    return presenter
}
