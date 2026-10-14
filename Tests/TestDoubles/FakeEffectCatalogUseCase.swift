import Domain
import TestSupport

/// `EffectCatalogUseCase` the test pushes states into, as the Interactor suites see it.
/// `publish(state)` is the catalog changing: every `observe()` stream yields it, and one
/// opened later starts with it, as the live stream starts from the current value (a fake
/// made without a state yields nothing until the first publish). `select` records the id
/// and answers the outcome the test set, `.prepared` unless told otherwise.
///
/// `run()` records its start and then does what the live one does: it runs until the
/// caller's task is cancelled (`suspendUntilCancelled`) and records that cancel, so a
/// test that stops the Interactor proves the task it owned was cancelled.
public final class FakeEffectCatalogUseCase: EffectCatalogUseCase, Sendable {
    private struct State {
        var current: EffectCatalogState?
        var continuations: [Int: AsyncStream<EffectCatalogState>.Continuation] = [:]
        var nextStream = 0
        var selectOutcome: EffectSelectionOutcome
    }

    private let state: Locked<State>
    /// One entry per `run()` call that has started.
    public let runs = Collector<Void>()
    /// One entry per `run()` that ended because its task was cancelled.
    public let runCancellations = Collector<Void>()
    /// One entry per `observe()` call.
    public let observations = Collector<Void>()
    /// One entry per observe stream that ended.
    public let observationTerminations = Collector<Void>()
    /// The ids `select` was called with, in call order.
    public let selections = Collector<EffectID>()
    /// One entry per `openEffectsFolder()` call.
    public let folderOpens = Collector<Void>()

    public init(state: EffectCatalogState? = nil, selectOutcome: EffectSelectionOutcome = .prepared) {
        self.state = Locked(State(current: state, selectOutcome: selectOutcome))
    }

    /// Makes `state` the current one: open streams yield it, later ones start with it.
    public func publish(_ state: EffectCatalogState) {
        self.state.withLock { locked in
            locked.current = state
            for continuation in locked.continuations.values { continuation.yield(state) }
        }
    }

    /// What `select` answers from now on.
    public func script(selectOutcome: EffectSelectionOutcome) {
        state.withLock { $0.selectOutcome = selectOutcome }
    }

    public func run() async {
        runs.append(())
        if await suspendUntilCancelled() { runCancellations.append(()) }
    }

    public func observe() -> AsyncStream<EffectCatalogState> {
        let (stream, continuation) = AsyncStream<EffectCatalogState>.makeStream()
        let id = state.withLock { locked -> Int in
            let id = locked.nextStream
            locked.nextStream += 1
            locked.continuations[id] = continuation
            locked.current.map { _ = continuation.yield($0) }
            return id
        }
        continuation.onTermination = { [weak self] _ in self?.end(id) }
        observations.append(())
        return stream
    }

    public func select(_ id: EffectID) async -> EffectSelectionOutcome {
        selections.append(id)
        return state.withLock { $0.selectOutcome }
    }

    public func openEffectsFolder() {
        folderOpens.append(())
    }

    private func end(_ id: Int) {
        state.withLock { _ = $0.continuations.removeValue(forKey: id) }
        observationTerminations.append(())
    }
}
