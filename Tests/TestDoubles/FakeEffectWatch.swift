import Domain
import TestSupport

/// `EffectWatch` the test fires by hand: every `changes(of:)` is a stream that yields
/// one element per `fire()` and nothing otherwise, so a subject re-listing "on a
/// change" is driven without a file, a gateway or a clock.
///
/// The stream is registered before `changes(of:)` returns, as the contract says the
/// watches are armed by then: a `fire()` made right after the call is delivered, not
/// lost. `requests` records the set each stream was made for; `terminations` records
/// (by request number, 0-based) each stream that ended, whether the consumer was
/// cancelled or stopped iterating, which is how a test proves the subject let go of
/// the watch it replaced.
public final class FakeEffectWatch: EffectWatch, Sendable {
    private struct State {
        var continuations: [AsyncStream<Void>.Continuation] = []
        var isActive: [Bool] = []
    }

    private let state = Locked(State())
    /// The set of every `changes(of:)` call, in order: request number n is element n.
    public let requests = Collector<EffectWatchSet>()
    /// The request number of every stream that ended, in the order they ended.
    public let terminations = Collector<Int>()

    public init() {}

    /// Yields one element on request number `request` (0-based), or on the latest request
    /// when omitted. `false` when that stream does not exist or has ended: nothing heard it.
    @discardableResult
    public func fire(request: Int? = nil) -> Bool {
        let target = state.withLock { state -> AsyncStream<Void>.Continuation? in
            guard let index = request ?? state.continuations.indices.last, state.isActive.indices.contains(index), state.isActive[index] else {
                return nil
            }
            return state.continuations[index]
        }
        return target.map { $0.yield(()) } != nil
    }

    /// The streams that have not ended.
    public var activeCount: Int { state.withLock { $0.isActive.filter { $0 }.count } }

    public func changes(of watchSet: EffectWatchSet) -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let index = state.withLock { state -> Int in
            state.continuations.append(continuation)
            state.isActive.append(true)
            return state.continuations.count - 1
        }
        continuation.onTermination = { [weak self] _ in self?.end(index) }
        requests.append(watchSet)
        return stream
    }

    private func end(_ index: Int) {
        state.withLock { $0.isActive[index] = false }
        terminations.append(index)
    }
}
