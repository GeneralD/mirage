import Combine

/// One subscription to a publisher of values and the main-actor task that applies them: the generic
/// form of `StateObservation`, for a publisher whose values are not an Interactor's state. It only
/// observes: starting and stopping whatever publishes is not its business.
///
/// The values reach the main actor through a `@MainActor` task over an `AsyncStream`, not through
/// `receive(on: DispatchQueue.main)` (so a test waits with `settle`, and the physical-symbol lint finds
/// no queue). The stream is fed by a `sink`, which takes every value the publisher sends and keeps the
/// newest until the task has applied it: `publisher.values` would not do, because an `AsyncPublisher`
/// asks for one value at a time and a value sent while the task is still applying the last one is
/// dropped. The sink runs on whatever thread the publisher sends from and only hands the value to the stream.
///
/// `end()` drops the value that is waiting or on its way, too: after it nothing is applied. An
/// observation that is let go ends itself, on whatever thread releases it (ending is safe on any thread,
/// and any number of times).
final class PublisherObservation<Value: Sendable> {
    private let subscription: AnyCancellable
    private let task: Task<Void, Never>
    private let stream: AsyncStream<Value>.Continuation

    @MainActor
    init(of publisher: AnyPublisher<Value, Never>, apply: @escaping @MainActor (Value) -> Void) {
        let (stream, continuation) = AsyncStream<Value>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.stream = continuation
        subscription = publisher.sink { @Sendable value in continuation.yield(value) }
        task = Task { @MainActor in
            for await value in stream {
                // A value the stream already handed to this task is still delivered after `end()`:
                // `finish()` only stops what comes next. `end()` cancelled the task before the
                // delivery can run, so this is where it is dropped.
                guard !Task.isCancelled else { return }
                apply(value)
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
