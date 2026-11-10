import Domain
import TestSupport

/// The passes the health suites report and the waits they make. A pass is what the runtime reports once per `prepare`ed
/// effect, so `emit` reports it the way the runtime does: to every open outcome stream, in the order it is called.
extension EffectCatalogRig {
    /// A pass that took a millisecond: well inside the budget.
    static let fast = GPUTiming(gpuStart: 10, gpuEnd: 10.001)
    /// A pass that took half a second: over the budget.
    static let slow = GPUTiming(gpuStart: 10, gpuEnd: 10.5)

    /// Reports `result` as the outcome of a pass of `source`, `times` times over.
    func emit(_ result: Result<GPUTiming, EffectFailure>, of source: EffectSource, times: Int = 1) {
        for _ in 0..<times {
            runtime.report(EffectPassOutcome(fingerprint: .of(source), result: result))
        }
    }

    /// Watches the catalog, starts it, and answers its first `prepare` with success. Returns once the first state is out, and
    /// once the run has subscribed to the runtime's outcomes.
    func begin() async -> (run: Task<Void, Never>, watcher: Watcher) {
        let watcher = watch()
        let run = start()
        await runtime.outcomeStreams.waitForCount(1)
        await answer(1)
        await watcher.states.waitForCount(1)
        return (run, watcher)
    }

    /// The switched-off effects of the first state that has any, once it is out. A sentinel reported after the outcomes it
    /// follows ends the wait only once those outcomes are counted, because one stream delivers them in order.
    func firstDisabled(in watcher: Watcher) async -> [EffectID: EffectDisableReason] {
        let state = await watcher.states.waitFor(predicate: { !$0.disabled.isEmpty })
        return state?.disabled ?? [:]
    }
}
