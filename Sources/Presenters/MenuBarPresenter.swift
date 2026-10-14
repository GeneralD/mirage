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
/// Presenter (the Router) calls them; nothing starts on its own.
///
/// The states reach the main actor through a `@MainActor` task over an `AsyncStream`, not
/// through `receive(on: DispatchQueue.main)` (so a test waits with `settle`, and the
/// physical-symbol lint finds no queue). The stream is fed by a `sink`, which takes every
/// state the publisher sends and keeps the newest until the task has applied it:
/// `publisher.values` would not do, because an `AsyncPublisher` asks for one value at a
/// time and a state sent while the task is still applying the last one is dropped, which
/// could leave the menu on a state that is no longer current.
@MainActor
public final class MenuBarPresenter: ObservableObject {
    /// The menu's rows, in the catalog's order (the bundled effect first); empty until the first state arrives.
    @Published public private(set) var items: [EffectMenuItem] = []
    /// One line about the chosen effect when the last attempt to run it failed
    /// (`"<name>: compile failed"`); `nil` when it is running or nothing was attempted.
    @Published public private(set) var status: String?

    @Dependency(\.effectInteractor) private var interactor
    private var observation: StateObservation?

    public init() {}

    /// Observes the Interactor's state, then starts the Interactor. Calling it again while
    /// started does nothing.
    public func start() {
        guard observation == nil else { return }
        observation = StateObservation(of: interactor.state) { [weak self] state in self?.apply(state) }
        interactor.start()
    }

    /// Ends the observation and stops the Interactor. The rows stay as they were.
    public func stop() {
        observation?.end()
        observation = nil
        interactor.stop()
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
    /// One subscription to the Interactor's states and the main-actor task that applies them.
    /// The sink runs on whatever thread the publisher sends from and only hands the state to
    /// the stream, which keeps the newest one.
    private struct StateObservation {
        private let subscription: AnyCancellable
        private let task: Task<Void, Never>
        private let stream: AsyncStream<EffectCatalogState>.Continuation

        @MainActor
        init(of states: AnyPublisher<EffectCatalogState, Never>, apply: @escaping @MainActor (EffectCatalogState) -> Void) {
            let (stream, continuation) = AsyncStream<EffectCatalogState>.makeStream(bufferingPolicy: .bufferingNewest(1))
            self.stream = continuation
            subscription = states.sink { @Sendable state in continuation.yield(state) }
            task = Task { @MainActor in
                for await state in stream { apply(state) }
            }
        }

        /// Drops the state that is waiting, too: after this nothing is applied.
        func end() {
            subscription.cancel()
            task.cancel()
            stream.finish()
        }
    }
}
