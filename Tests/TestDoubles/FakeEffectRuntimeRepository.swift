import Domain
import TestSupport

/// `EffectRuntimeRepository` whose every call suspends until the test completes
/// it: `prepare` until `completePrepare(_:with:)`, `apply` until
/// `completeApply(_:with:)` — each exactly once, with whatever result the test
/// chooses, in any order. "A slow compile overtaken by a newer one" and "a GPU
/// completion that lands after the next frame was captured" are therefore
/// sequences the test writes down. A caller whose task is cancelled is resumed
/// with `.failure(.internalError)`, so a stopped pipeline never leaks a
/// continuation into the suite's time limit.
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
        var cancelledBeforeSuspending: Set<Int> = []
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

    /// A request is recorded if and only if it was registered as waiting: both
    /// happen in one critical section, so a cancellation can never leave a
    /// recorded request that was already resumed, and a caller cancelled before
    /// it suspended is never recorded at all. (`Collector` takes its own lock and
    /// never calls back into `state`, so the nesting cannot deadlock.)
    private func suspend(_ id: Int, announce: @Sendable () -> Void) async -> Result<Void, EffectFailure> {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: Continuation) in
                let alreadyCancelled = state.withLock { state in
                    guard state.cancelledBeforeSuspending.remove(id) == nil else { return true }
                    state.waiting[id] = continuation
                    announce()
                    return false
                }
                guard !alreadyCancelled else { return continuation.resume(returning: .failure(.internalError)) }
            }
        } onCancel: {
            let continuation = state.withLock { state -> Continuation? in
                guard let waiting = state.waiting.removeValue(forKey: id) else {
                    state.cancelledBeforeSuspending.insert(id)
                    return nil
                }
                return waiting
            }
            continuation?.resume(returning: .failure(.internalError))
        }
    }

    private func resume(_ id: Int, with result: Result<Void, EffectFailure>) -> Bool {
        guard let continuation = state.withLock({ $0.waiting.removeValue(forKey: id) }) else { return false }
        continuation.resume(returning: result)
        return true
    }
}
