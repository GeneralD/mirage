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
///
/// The live `run()` has teardown to finish once it is cancelled (it stops its file watch),
/// and a subject that starts the next run must wait for it. `holdCancelledRuns()` makes
/// a cancelled `run()` model that: it records the cancel and then stays in `run()`,
/// ignoring the cancellation as the other manual-completion fakes do, until
/// `releaseCancelledRuns()`. `heldRunCount` is how many are held right now; the cancel and
/// the hold are recorded in one step, so a test that has seen the cancel finds the run held.
/// `runEvents` records when each run began and returned, in one order, so a test can tell
/// "the next run began after the old one returned" from "while it was still returning".
public final class FakeEffectCatalogUseCase: EffectCatalogUseCase, Sendable {
    /// When a `run()` call began or returned, counting the calls from 1.
    public enum RunEvent: Equatable, Sendable {
        case started(Int)
        case ended(Int)
    }

    private typealias Held = CheckedContinuation<Void, Never>

    private struct State {
        var current: EffectCatalogState?
        var continuations: [Int: AsyncStream<EffectCatalogState>.Continuation] = [:]
        var nextStream = 0
        var selectOutcome: EffectSelectionOutcome
        var runCount = 0
        var holdsCancelledRuns = false
        var heldRuns: [Held] = []
    }

    private let state: Locked<State>
    /// One entry per `run()` call that has started.
    public let runs = Collector<Void>()
    /// The start and the return of every `run()`, in the order they happened. A start is
    /// recorded before `runs` counts it.
    public let runEvents = Collector<RunEvent>()
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
        let number = state.withLock { locked -> Int in
            locked.runCount += 1
            runEvents.append(.started(locked.runCount))
            runs.append(())
            return locked.runCount
        }
        if await suspendUntilCancelled() { await recordCancelAndHoldIfAsked() }
        runEvents.append(.ended(number))
    }

    /// The runs that are cancelled and held right now.
    public var heldRunCount: Int { state.current.heldRuns.count }

    /// From now on a `run()` that is cancelled stays in `run()`, after recording the cancel,
    /// until `releaseCancelledRuns()`.
    public func holdCancelledRuns() {
        state.withLock { $0.holdsCancelledRuns = true }
    }

    /// Lets every held run return and ends the holding: a run cancelled afterwards returns at once.
    public func releaseCancelledRuns() {
        let held = state.withLock { locked -> [Held] in
            locked.holdsCancelledRuns = false
            let held = locked.heldRuns
            locked.heldRuns = []
            return held
        }
        for run in held { run.resume() }
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

    /// Records the cancel, then waits for `releaseCancelledRuns()` when the holding is on. The
    /// record and the registration are one critical section, so a release cannot slip between the
    /// check and the wait, and a test that has seen the cancel finds the run held.
    private func recordCancelAndHoldIfAsked() async {
        await withCheckedContinuation { (continuation: Held) in
            let held = state.withLock { locked -> Bool in
                runCancellations.append(())
                guard locked.holdsCancelledRuns else { return false }
                locked.heldRuns.append(continuation)
                return true
            }
            if !held { continuation.resume() }
        }
    }

    private func end(_ id: Int) {
        state.withLock { _ = $0.continuations.removeValue(forKey: id) }
        observationTerminations.append(())
    }
}
