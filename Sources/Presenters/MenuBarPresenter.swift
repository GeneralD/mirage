import Combine
import Dependencies
import Domain

/// The effects menu's display state (epic #42, D9) and the menu bar's controls: the rows, a line about
/// how the last attempt to run the chosen effect went, whether the effect is bypassed, the frame-rate
/// readout, and the icon that the first two choose. It turns `EffectInteractor.state` and
/// `ControlsInteractor.state` into `@Published` values a View draws; deciding the words and flags is its
/// job, drawing them is not (it imports neither AppKit nor SwiftUI).
///
/// The Presenter owns the lifecycle of both Interactors for the menu: `start()` begins observing both
/// and starts both, `stop()` ends both observations and stops both. Whoever builds the Presenter (the
/// Router) calls them; nothing starts on its own. A started Presenter that is let go does what `stop()`
/// does, since its observation tasks and the Interactors' runs would outlive the only object that knows
/// about them.
///
/// The states reach the main actor through a `CatalogStateObservation` and a `StateObservation` of the
/// controls, each of which keeps the newest state until it is applied and applies nothing after it ends.
@MainActor
public final class MenuBarPresenter: ObservableObject {
    /// The menu's rows, in the catalog's order (the bundled effect first); empty until the first state arrives.
    @Published public private(set) var items: [EffectMenuItem] = []
    /// One line about the chosen effect when the last attempt to run it failed
    /// (`"<name>: compile failed"`); `nil` when it is running or nothing was attempted.
    @Published public private(set) var status: String?
    /// Whether the effect is bypassed, as the controls' state says. `toggleBypass()` changes it only
    /// through the controls' Interactor, so it stays as it was until that state comes back.
    @Published public private(set) var isBypassed = false
    /// The frame-rate readout (`"30 fps"`); `nil` while the pipeline is not running.
    @Published public private(set) var frameRateLine: String?
    /// Whether *Adjust Effect…* is offered: the chosen effect declares parameters. `false` until the first state arrives.
    @Published public private(set) var canAdjustEffect = false
    /// Where *Browse Effects…*, *Adjust Effect…* and *Settings…* go: the Router that built this Presenter,
    /// which opens the picker, the parameter panel or the settings window.
    /// Weak, because the Router owns the Presenter; until a Router takes it the item does nothing.
    public weak var router: (any MenuBarRouting)?

    /// The menu bar's icon for the current state: see `menuBarIconName(isBypassed:hasProblem:)`.
    public var iconName: String {
        menuBarIconName(isBypassed: isBypassed, hasProblem: status != nil)
    }

    @Dependency(\.effectInteractor) private var interactor
    @Dependency(\.controlsInteractor) private var controls
    /// What a started Presenter holds; `nil` when it was never started or has been stopped.
    /// Releasing it ends both observations and stops both Interactors, so `stop()` and letting the
    /// Presenter go are one path, and a Presenter that is not started asks nothing of the Interactors
    /// when it goes.
    private var running: Running?

    public init() {}

    /// Observes both Interactors' states, then starts both Interactors. Calling it again while
    /// started does nothing.
    public func start() {
        guard running == nil else { return }
        running = Running(
            over: interactor,
            controls: controls,
            applyEffect: { [weak self] state in self?.apply(state) },
            applyControls: { [weak self] state in self?.apply(controls: state) })
        interactor.start()
        controls.start()
    }

    /// Ends both observations and stops both Interactors. The rows stay as they were, even
    /// when a state had already been sent and not yet applied. The readout goes back to `nil`;
    /// the bypass stays as it was.
    public func stop() {
        guard running != nil else {
            interactor.stop()
            controls.stop()
            return
        }
        running = nil
        if frameRateLine != nil { frameRateLine = nil }
    }

    public func select(_ id: EffectID) {
        interactor.select(id)
    }

    /// Forgets the record that switched `id` off and chooses it again. Like `select(_:)`, it goes to the
    /// Interactor whether or not the row is enabled; whether the row is enabled is the View's `disabled`.
    public func reenable(_ id: EffectID) {
        interactor.reenable(id)
    }

    public func openEffectsFolder() {
        interactor.openEffectsFolder()
    }

    /// Flips the bypass in the controls' Interactor. `isBypassed` changes when its state comes back, not here.
    public func toggleBypass() {
        controls.toggleBypass()
    }

    /// *Browse Effects…*: asks the Router for the picker's window.
    public func browseEffects() {
        router?.openEffectPicker()
    }

    /// *Settings…*: asks the Router for the settings window.
    public func openSettings() {
        router?.openSettings()
    }

    /// The title of *Adjust Effect…*: the View draws this value rather than a literal of its own.
    public var adjustEffectTitle: String {
        MenuBarText.adjustEffectTitle
    }

    /// *Adjust Effect…*: asks the Router for the parameter panel's window.
    public func adjustEffect() {
        router?.openParameterPanel()
    }

    private func apply(_ state: EffectCatalogState) {
        let items = MenuBarText.items(of: state)
        let status = MenuBarText.status(of: state)
        let canAdjust = MenuBarText.canAdjustEffect(of: state)
        if self.items != items { self.items = items }
        if self.status != status { self.status = status }
        if canAdjustEffect != canAdjust { canAdjustEffect = canAdjust }
    }

    private func apply(controls state: ControlsState) {
        // Qualified: inside this type the bare name is the `frameRateLine` property.
        let line = Presenters.frameRateLine(framesPerSecond: state.framesPerSecond)
        if isBypassed != state.isBypassed { isBypassed = state.isBypassed }
        if frameRateLine != line { frameRateLine = line }
    }
}

extension MenuBarPresenter {
    /// A started Presenter's observations of both Interactors' states and both Interactors' runs, ended
    /// together when this is released. Its own class rather than the Presenter's `deinit`: a main-actor
    /// class's `deinit` is not isolated, so it could not reach the Presenter's state, and `isolated deinit`
    /// is not available on the toolchain that builds the release. Releasing it on any thread is safe: ending
    /// an observation and `stop()` both are.
    private final class Running {
        private let effectObservation: CatalogStateObservation
        private let controlsObservation: StateObservation<ControlsState>
        private let interactor: any EffectInteractor
        private let controls: any ControlsInteractor

        @MainActor
        init(
            over interactor: any EffectInteractor,
            controls: any ControlsInteractor,
            applyEffect: @escaping @MainActor (EffectCatalogState) -> Void,
            applyControls: @escaping @MainActor (ControlsState) -> Void
        ) {
            self.interactor = interactor
            self.controls = controls
            effectObservation = CatalogStateObservation(of: interactor.state, apply: applyEffect)
            controlsObservation = StateObservation(of: controls.state, apply: applyControls)
        }

        deinit {
            effectObservation.end()
            controlsObservation.end()
            interactor.stop()
            controls.stop()
        }
    }
}
