import Combine
import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import Presenters

@MainActor
@Suite("MenuBarPresenter controls", .timeLimit(.minutes(1)))
struct MenuBarControlsTests {
    private let chromatic = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))

    // MARK: - Lifecycle

    @Test("start starts both Interactors once, and a second start starts neither again")
    func startStartsBothOnce() {
        let rig = ControlsRig()

        rig.presenter.start()
        rig.presenter.start()

        #expect(rig.effect.starts.count == 1)
        #expect(rig.controls.starts.count == 1)
    }

    @Test("stop stops both Interactors even when the Presenter was never started")
    func stopBeforeStartStopsBoth() {
        let rig = ControlsRig()

        rig.presenter.stop()

        #expect(rig.effect.stops.count == 1)
        #expect(rig.controls.stops.count == 1)
    }

    @Test("stop cancels the controls subscription, stops both Interactors, clears the readout and keeps the bypass")
    func stopEndsTheControls() async {
        let rig = ControlsRig(controls: ControlsState(isBypassed: true, framesPerSecond: 30))
        rig.presenter.start()
        await settle(rig.presenter.$frameRateLine) { $0 == "30 fps" }

        rig.presenter.stop()

        #expect(rig.controls.stateCancels.count == 1, "the subscription to the controls was cancelled")
        #expect(rig.effect.stops.count == 1)
        #expect(rig.controls.stops.count == 1)
        #expect(rig.presenter.frameRateLine == nil)
        #expect(rig.presenter.isBypassed)
    }

    @Test("a controls state that was on its way when stop was called is never applied, and a restart shows the newest state")
    func stopDropsTheControlsStateOnItsWay() async {
        let rig = ControlsRig()
        rig.presenter.start()
        let shown = Collector<String?>()
        let subscription = rig.presenter.$frameRateLine.dropFirst().sink { shown.append($0) }

        // The test holds the main actor from the first publish to the wait below, so the task that
        // applies the controls has not run: the state is on its way to the readout when stop() lands.
        rig.controls.publish(ControlsState(framesPerSecond: 30))
        rig.presenter.stop()
        // Published while nothing observes the controls, so only the restart delivers it.
        rig.controls.publish(ControlsState(framesPerSecond: 60))
        rig.presenter.start()
        await settle(rig.presenter.$frameRateLine) { $0 == "60 fps" }

        #expect(shown.values == ["60 fps"], "the readout went straight from nil to the restart's state; the stopped one was never applied")
        withExtendedLifetime(subscription) {}
    }

    @Test("a started Presenter that is let go stops both Interactors and cancels both subscriptions")
    func letGoWhileStartedStopsBoth() {
        let effect = SpyEffectInteractor(FakeEffectInteractor(state: .fixture([chromatic])))
        let controls = FakeControlsInteractor()
        var presenter: MenuBarPresenter? = makeControlsPresenter(effect: effect, controls: controls)
        presenter?.start()
        weak let letGo = presenter
        #expect(controls.stops.count == 0)

        presenter = nil

        #expect(letGo == nil, "nothing else holds the Presenter, so the stops below are its release's")
        #expect(effect.inner.stops.count == 1)
        #expect(controls.stops.count == 1)
        #expect(effect.cancellations.count == 1)
        #expect(controls.stateCancels.count == 1)
    }

    // MARK: - Bypass and readout

    @Test("a published controls state shows the bypass and the frame-rate readout")
    func publishedStateShows() async {
        let rig = ControlsRig()
        rig.presenter.start()

        rig.controls.publish(ControlsState(isBypassed: true, framesPerSecond: 30))
        await settle(rig.presenter.$frameRateLine) { $0 == "30 fps" }

        #expect(rig.presenter.isBypassed)
        #expect(rig.presenter.frameRateLine == "30 fps")
    }

    @Test("zero frames per second clears the readout, and one frame per second shows it as one fps")
    func zeroClearsTheReadout() async {
        let rig = ControlsRig(controls: ControlsState(isBypassed: true, framesPerSecond: 30))
        rig.presenter.start()
        await settle(rig.presenter.$frameRateLine) { $0 == "30 fps" }

        rig.controls.publish(ControlsState(isBypassed: true, framesPerSecond: 0))
        await settle(rig.presenter.$frameRateLine) { $0 == nil }
        #expect(rig.presenter.frameRateLine == nil)

        rig.controls.publish(ControlsState(isBypassed: true, framesPerSecond: 1))
        await settle(rig.presenter.$frameRateLine) { $0 == "1 fps" }
        #expect(rig.presenter.frameRateLine == "1 fps")
    }

    @Test("toggleBypass goes to the controls Interactor once, and the bypass changes only when its state comes back")
    func toggleGoesToTheInteractor() async {
        let rig = ControlsRig()
        rig.presenter.start()

        rig.presenter.toggleBypass()

        #expect(rig.controls.toggles.count == 1)
        #expect(!rig.presenter.isBypassed, "the bypass has not changed before the Interactor publishes it")

        rig.controls.publish(ControlsState(isBypassed: true))
        await settle(rig.presenter.$isBypassed) { $0 }
        #expect(rig.presenter.isBypassed)
    }

    @Test(
        "the icon is the plain camera while bypassed, a warning while the chosen effect has a problem, and the filtered camera otherwise",
        arguments: [
            (false, false, "camera.filters"),
            (false, true, "exclamationmark.triangle"),
            (true, false, "camera"),
            (true, true, "camera"),
        ])
    func iconNameTable(bypassed: Bool, hasProblem: Bool, expected: String) async {
        let outcome: EffectSelectionOutcome? = hasProblem ? .failed(.compileFailed) : nil
        let rig = ControlsRig(effect: .fixture([chromatic], outcome: outcome), controls: ControlsState(isBypassed: bypassed))

        rig.presenter.start()
        await settle(rig.presenter.$status) { ($0 != nil) == hasProblem }
        await settle(rig.presenter.$isBypassed) { $0 == bypassed }

        #expect(rig.presenter.iconName == expected)
    }

    @Test(
        "the readout is the frame rate with its unit, and nothing for zero or less",
        arguments: [
            (-1, String?.none),
            (0, String?.none),
            (1, "1 fps"),
            (30, "30 fps"),
            (120, "120 fps"),
        ])
    func readoutWording(framesPerSecond: Int, expected: String?) {
        #expect(frameRateLine(framesPerSecond: framesPerSecond) == expected)
    }
}

/// Both Interactors as fakes, and a Presenter over them: the test publishes into the controls and the
/// effect, and the Presenter sees them only through its observations.
@MainActor
private struct ControlsRig {
    let effect: SpyEffectInteractor
    let controls: FakeControlsInteractor
    let presenter: MenuBarPresenter

    init(
        effect state: EffectCatalogState = .fixture([.fixture(.bundled("Chromatic Grain"))]),
        controls initial: ControlsState = ControlsState()
    ) {
        let effect = SpyEffectInteractor(FakeEffectInteractor(state: state))
        let controls = FakeControlsInteractor(state: initial)
        self.effect = effect
        self.controls = controls
        presenter = makeControlsPresenter(effect: effect, controls: controls)
    }
}

/// A Presenter over both fakes, built inside `withDependencies` (the Presenter captures the dependencies
/// of the scope it is made in).
@MainActor
private func makeControlsPresenter(effect: SpyEffectInteractor, controls: FakeControlsInteractor) -> MenuBarPresenter {
    withDependencies {
        $0.effectInteractor = effect
        $0.controlsInteractor = controls
    } operation: {
        MenuBarPresenter()
    }
}
