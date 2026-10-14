import Combine
import Domain

/// The state the effects menu observes, shared by every observer. `EffectCatalogSession`
/// decides and publishes here; `observe()` hands each caller its own stream.
///
/// A `CurrentValueSubject` is what lets `observe()` stay synchronous, which the port
/// requires: the stream is subscribed while it is being built, before `observe()`
/// returns, so a state published right after is never missed, and the state now is
/// delivered at once. The lock above the Gateway is forbidden to the UseCases; the
/// subject carries its own, and every `send` comes from the one session actor.
///
/// Nothing is ever completed. A run that ends tells the open streams so (`endObservations`)
/// and forgets the state, and the next run publishes on the same subjects.
final class EffectCatalogBroadcast: @unchecked Sendable {
    private let states = CurrentValueSubject<EffectCatalogState?, Never>(nil)
    private let ends = PassthroughSubject<Void, Never>()

    /// The state `observe()` would start from, `nil` while there is none.
    var current: EffectCatalogState? { states.value }

    func publish(_ state: EffectCatalogState) {
        states.send(state)
    }

    /// Finishes every stream opened so far, then forgets the state so that a stream opened
    /// after this waits for the next run's first one.
    func endObservations() {
        ends.send()
        states.send(nil)
    }

    /// The current state (if any), then every state published after, until the consumer lets
    /// go or the run ends. Any number of streams may be open at once.
    func observe() -> AsyncStream<EffectCatalogState> {
        AsyncStream { continuation in
            let following = states.compactMap { $0 }.sink { continuation.yield($0) }
            let ending = ends.sink { continuation.finish() }
            let subscription = Subscription(following, ending)
            continuation.onTermination = { _ in subscription.cancel() }
        }
    }

    /// The two Combine subscriptions behind one stream, cancelled together when it ends.
    /// `AnyCancellable` is not marked `Sendable`, but `cancel()` is safe from any thread, which
    /// is all the stream's termination handler (it runs wherever the consumer let go) does.
    private final class Subscription: @unchecked Sendable {
        private let cancellables: [AnyCancellable]

        init(_ cancellables: AnyCancellable...) {
            self.cancellables = cancellables
        }

        func cancel() {
            for cancellable in cancellables { cancellable.cancel() }
        }
    }
}
