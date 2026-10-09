import Domain
import TestSupport

/// `EffectRuntimeRepository` whose every call suspends until the test completes
/// it: `prepare` until `completePrepare(_:with:)`, `apply` until
/// `completeApply(_:with:)` — each exactly once, with whatever result the test
/// chooses, in any order. "A slow compile overtaken by a newer one" and "a GPU
/// completion that lands after the next frame was captured" are therefore
/// sequences the test writes down. Like the live runtime, it ignores the
/// caller's cancellation: a cancelled call is still recorded and still waits
/// for its completion, so a suite that stops the pipeline mid-pass completes
/// the pending request itself (`pendingCount` tells what is left).
public final class FakeEffectRuntimeRepository: EffectRuntimeRepository, Sendable {
    public struct PrepareRequest: Sendable {
        public let id: Int
        public let effect: EffectSource
    }

    public struct ApplyRequest: Sendable {
        public let id: Int
        public let input: FrameRef
        public let output: FrameRef
        public let frameContext: FrameContext
    }

    private typealias Continuation = CheckedContinuation<Result<Void, EffectFailure>, Never>

    private struct State {
        var nextID = 1
        var waiting: [Int: Continuation] = [:]
    }

    private let state = Locked(State())
    public let prepareRequests = Collector<PrepareRequest>()
    public let applyRequests = Collector<ApplyRequest>()

    public init() {}

    /// Calls that are suspended right now.
    public var pendingCount: Int { state.current.waiting.count }

    public func prepare(_ effect: EffectSource) async -> Result<Void, EffectFailure> {
        let id = nextID()
        return await suspend(id) { prepareRequests.append(PrepareRequest(id: id, effect: effect)) }
    }

    public func apply(input: FrameRef, output: FrameRef, frameContext: FrameContext) async -> Result<Void, EffectFailure> {
        let id = nextID()
        return await suspend(id) { applyRequests.append(ApplyRequest(id: id, input: input, output: output, frameContext: frameContext)) }
    }

    /// Resumes the suspended `prepare`; `false` when it is unknown or already resumed.
    @discardableResult
    public func completePrepare(_ request: PrepareRequest, with result: Result<Void, EffectFailure>) -> Bool {
        resume(request.id, with: result)
    }

    /// Resumes the suspended `apply`; `false` when it is unknown or already resumed.
    @discardableResult
    public func completeApply(_ request: ApplyRequest, with result: Result<Void, EffectFailure>) -> Bool {
        resume(request.id, with: result)
    }

    private func nextID() -> Int {
        state.withLock { state in
            defer { state.nextID += 1 }
            return state.nextID
        }
    }

    /// The request is registered as waiting and recorded in one critical
    /// section, so a test that sees a recorded request can always complete it.
    /// (`Collector` takes its own lock and never calls back into `state`, so the
    /// nesting cannot deadlock.)
    private func suspend(_ id: Int, announce: @Sendable () -> Void) async -> Result<Void, EffectFailure> {
        await withCheckedContinuation { (continuation: Continuation) in
            state.withLock { state in
                state.waiting[id] = continuation
                announce()
            }
        }
    }

    private func resume(_ id: Int, with result: Result<Void, EffectFailure>) -> Bool {
        guard let continuation = state.withLock({ $0.waiting.removeValue(forKey: id) }) else { return false }
        continuation.resume(returning: result)
        return true
    }
}
