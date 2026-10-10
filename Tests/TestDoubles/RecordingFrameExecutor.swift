import Domain
import TestSupport

/// `ManualFrameExecutor` that also records every enqueue, so a test can await a
/// subject's hop onto the executor instead of polling for it: the subject's task
/// queues its work at a moment the test cannot see, and `enqueued` is that moment.
/// Shared by the suites whose subject hops from its own task
/// (`GPURenderDataSource`, `EffectRuntimeRepository`).
public final class RecordingFrameExecutor: FrameExecutor, Sendable {
    private let manual = ManualFrameExecutor()
    /// One element per `run`, recorded after the work is queued.
    public let enqueued = Collector<Void>()

    public init() {}

    public var pendingCount: Int { manual.pendingCount }

    public func run(_ work: @escaping @Sendable () -> Void) {
        manual.run(work)
        enqueued.append(())
    }

    /// Runs queued work until the queue is empty, as `ManualFrameExecutor.drain()` does.
    @discardableResult
    public func drain() -> Int {
        manual.drain()
    }
}
