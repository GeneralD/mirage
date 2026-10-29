import Combine
import Domain

/// One subscription to the `EffectInteractor`'s states and the main-actor task that applies them,
/// shared by the Presenters that draw the catalog (the menu's and the picker's). It only observes:
/// starting and stopping the Interactor is not its business.
///
/// The states reach the main actor through a `@MainActor` task over an `AsyncStream`, not
/// through `receive(on: DispatchQueue.main)` (so a test waits with `settle`, and the
/// physical-symbol lint finds no queue). The stream is fed by a `sink`, which takes every
/// state the publisher sends and keeps the newest until the task has applied it:
/// `publisher.values` would not do, because an `AsyncPublisher` asks for one value at a
/// time and a state sent while the task is still applying the last one is dropped, which
/// could leave a Presenter on a state that is no longer current. The sink runs on whatever
/// thread the publisher sends from and only hands the state to the stream.
///
/// `end()` drops the state that is waiting or on its way, too: after it nothing is applied. An
/// observation that is let go ends itself, on whatever thread releases it (ending is safe on any).
final class CatalogStateObservation {
    private let subscription: AnyCancellable
    private let task: Task<Void, Never>
    private let stream: AsyncStream<EffectCatalogState>.Continuation

    @MainActor
    init(of states: AnyPublisher<EffectCatalogState, Never>, apply: @escaping @MainActor (EffectCatalogState) -> Void) {
        let (stream, continuation) = AsyncStream<EffectCatalogState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.stream = continuation
        subscription = states.sink { @Sendable state in continuation.yield(state) }
        task = Task { @MainActor in
            for await state in stream {
                // A state the stream already handed to this task is still delivered after `end()`:
                // `finish()` only stops what comes next. `end()` cancelled the task before the
                // delivery can run, so this is where it is dropped.
                guard !Task.isCancelled else { return }
                apply(state)
            }
        }
    }

    deinit {
        end()
    }

    func end() {
        subscription.cancel()
        task.cancel()
        stream.finish()
    }
}
