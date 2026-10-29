import Combine
import Dependencies
import Domain

/// The effects menu's display state (epic #42, D9): the rows, and a line about how the
/// last attempt to run the chosen effect went. It turns `EffectInteractor.state` into
/// `@Published` values a View draws; deciding the words and flags is its job, drawing
/// them is not (it imports neither AppKit nor SwiftUI).
///
/// The Presenter owns the Interactor's lifecycle for the menu: `start()` begins
/// observing and starts the Interactor, `stop()` ends both. Whoever builds the
/// Presenter (the Router) calls them; nothing starts on its own. A started Presenter that is
/// let go does what `stop()` does, since its observation task and the Interactor's run would
/// outlive the only object that knows about them.
///
/// The states reach the main actor through a `CatalogStateObservation`, which keeps the newest
/// state until it is applied and applies nothing after it ends.
@MainActor
public final class MenuBarPresenter: ObservableObject {
    /// The menu's rows, in the catalog's order (the bundled effect first); empty until the first state arrives.
    @Published public private(set) var items: [EffectMenuItem] = []
    /// One line about the chosen effect when the last attempt to run it failed
    /// (`"<name>: compile failed"`); `nil` when it is running or nothing was attempted.
    @Published public private(set) var status: String?

    @Dependency(\.effectInteractor) private var interactor
    /// What a started Presenter holds; `nil` when it was never started or has been stopped.
    /// Releasing it ends the observation and stops the Interactor, so `stop()` and letting the
    /// Presenter go are one path, and a Presenter that is not started asks nothing of the
    /// Interactor when it goes.
    private var running: Running?

    public init() {}

    /// Observes the Interactor's state, then starts the Interactor. Calling it again while
    /// started does nothing.
    public func start() {
        guard running == nil else { return }
        running = Running(over: interactor) { [weak self] state in self?.apply(state) }
        interactor.start()
    }

    /// Ends the observation and stops the Interactor. The rows stay as they were, even
    /// when a state had already been sent and not yet applied.
    public func stop() {
        guard running != nil else { return interactor.stop() }
        running = nil
    }

    public func select(_ id: EffectID) {
        interactor.select(id)
    }

    public func openEffectsFolder() {
        interactor.openEffectsFolder()
    }

    private func apply(_ state: EffectCatalogState) {
        let items = MenuBarText.items(of: state)
        let status = MenuBarText.status(of: state)
        if self.items != items { self.items = items }
        if self.status != status { self.status = status }
    }
}

extension MenuBarPresenter {
    /// A started Presenter's observation of the Interactor's states and the Interactor's run, ended
    /// together when this is released. Its own class rather than the Presenter's `deinit`: a main-actor
    /// class's `deinit` is not isolated, so it could not reach the Presenter's state, and `isolated deinit`
    /// is not available on the toolchain that builds the release. Releasing it on any thread is safe: ending
    /// an observation and `stop()` both are.
    private final class Running {
        private let observation: CatalogStateObservation
        private let interactor: any EffectInteractor

        @MainActor
        init(over interactor: any EffectInteractor, apply: @escaping @MainActor (EffectCatalogState) -> Void) {
            self.interactor = interactor
            observation = CatalogStateObservation(of: interactor.state, apply: apply)
        }

        deinit {
            observation.end()
            interactor.stop()
        }
    }
}
