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
/// `setParameters` never suspends, as the live one does not wait for anything: every
/// write is recorded in `parameterWrites`, in call order, and nothing is applied.
/// `apply` reports nothing, because the test chooses what each pass ends in: it tells the
/// streams `outcomes()` opened what it likes with `report(_:)`, as the live runtime does for
/// every pass. Each `outcomes()` call opens a stream of its own, which replays nothing and keeps
/// the newest 64 outcomes it has not delivered.
/// `compilerMessage(of:)` answers with the value `answerCompilerMessage(_:)` set (nil by default) and is recorded in
/// `compilerMessageRequests`. After `holdCompilerMessages()` it suspends until `completeCompilerMessage(_:with:)`, the
/// same way `prepare` does; `pendingCount` counts those held queries too.
public final class FakeEffectRuntimeRepository: EffectRuntimeRepository, Sendable {
    public struct PrepareRequest: Sendable {
        public let id: Int
        public let effect: EffectSource
        public let parameters: EffectParameterBlock
        /// The repository that issued it: ids restart at 1 per instance, so the id alone cannot tell a stranger's request.
        fileprivate let origin: ObjectIdentifier
    }

    /// One `setParameters` call: the block and the effect it was addressed to.
    public struct ParameterWrite: Sendable, Hashable {
        public let block: EffectParameterBlock
        public let source: EffectSource

        public init(block: EffectParameterBlock, source: EffectSource) {
            self.block = block
            self.source = source
        }
    }

    public struct ApplyRequest: Sendable {
        public let id: Int
        public let input: FrameRef
        public let output: FrameRef
        public let frameContext: FrameContext
        fileprivate let origin: ObjectIdentifier
    }

    public struct CompilerMessageRequest: Sendable {
        public let id: Int
        public let effect: EffectSource
        /// The repository that issued it, as `PrepareRequest` carries: ids restart at 1 per instance.
        fileprivate let origin: ObjectIdentifier
    }

    private typealias Continuation = CheckedContinuation<Result<Void, EffectFailure>, Never>
    private typealias CompilerMessageContinuation = CheckedContinuation<String?, Never>

    private struct State {
        var nextID = 1
        var waiting: [Int: Continuation] = [:]
        var nextObserver = 1
        var observers: [Int: AsyncStream<EffectPassOutcome>.Continuation] = [:]
        var compilerMessageAnswer: String?
        var holdingCompilerMessages = false
        var waitingCompilerMessages: [Int: CompilerMessageContinuation] = [:]
    }

    private let state = Locked(State())
    public let prepareRequests = Collector<PrepareRequest>()
    public let parameterWrites = Collector<ParameterWrite>()
    public let applyRequests = Collector<ApplyRequest>()
    public let compilerMessageRequests = Collector<CompilerMessageRequest>()
    /// One element per `outcomes()` call, recorded once its stream is open: a caller that opens it on its
    /// own task can be waited for before the test reports, because a stream replays nothing.
    public let outcomeStreams = Collector<Void>()

    public init() {}

    /// Calls that are suspended right now.
    public var pendingCount: Int { state.current.waiting.count + state.current.waitingCompilerMessages.count }

    public func prepare(_ effect: EffectSource, parameters: EffectParameterBlock) async -> Result<Void, EffectFailure> {
        let id = nextID()
        return await suspend(id) {
            prepareRequests.append(PrepareRequest(id: id, effect: effect, parameters: parameters, origin: ObjectIdentifier(self)))
        }
    }

    public func setParameters(_ block: EffectParameterBlock, of source: EffectSource) {
        parameterWrites.append(ParameterWrite(block: block, source: source))
    }

    public func apply(input: FrameRef, output: FrameRef, frameContext: FrameContext) async -> Result<Void, EffectFailure> {
        let id = nextID()
        return await suspend(id) {
            applyRequests.append(ApplyRequest(id: id, input: input, output: output, frameContext: frameContext, origin: ObjectIdentifier(self)))
        }
    }

    public func outcomes() -> AsyncStream<EffectPassOutcome> {
        let (stream, continuation) = AsyncStream.makeStream(of: EffectPassOutcome.self, bufferingPolicy: .bufferingNewest(64))
        let id = state.withLock { state in
            defer { state.nextObserver += 1 }
            state.observers[state.nextObserver] = continuation
            return state.nextObserver
        }
        continuation.onTermination = { [state] _ in
            state.withLock { $0.observers[id] = nil }
        }
        outcomeStreams.append(())
        return stream
    }

    /// Tells `outcome` to every stream `outcomes()` has open, at once. The live runtime does so from its
    /// executor, a moment after the pass answers; a subject cannot see the difference, so it is not modelled.
    public func report(_ outcome: EffectPassOutcome) {
        let open = state.withLock { Array($0.observers.values) }
        for observer in open { observer.yield(outcome) }
    }

    /// Resumes the suspended `prepare`; `false` when it is unknown, came from another repository, or is already resumed.
    @discardableResult
    public func completePrepare(_ request: PrepareRequest, with result: Result<Void, EffectFailure>) -> Bool {
        guard request.origin == ObjectIdentifier(self) else { return false }
        return resume(request.id, with: result)
    }

    /// Resumes the suspended `apply`; `false` when it is unknown, came from another repository, or is already resumed.
    @discardableResult
    public func completeApply(_ request: ApplyRequest, with result: Result<Void, EffectFailure>) -> Bool {
        guard request.origin == ObjectIdentifier(self) else { return false }
        return resume(request.id, with: result)
    }

    /// The message the next `compilerMessage(of:)` answers with, unless it is held. Nil by default.
    public func answerCompilerMessage(_ message: String?) {
        state.withLock { $0.compilerMessageAnswer = message }
    }

    /// Suspends every `compilerMessage(of:)` from now on until `completeCompilerMessage` resumes it.
    public func holdCompilerMessages() {
        state.withLock { $0.holdingCompilerMessages = true }
    }

    /// Resumes the held `compilerMessage(of:)` with `message`; `false` when it is unknown, came from another repository, or is already resumed.
    @discardableResult
    public func completeCompilerMessage(_ request: CompilerMessageRequest, with message: String?) -> Bool {
        guard request.origin == ObjectIdentifier(self) else { return false }
        guard let continuation = state.withLock({ $0.waitingCompilerMessages.removeValue(forKey: request.id) }) else { return false }
        continuation.resume(returning: message)
        return true
    }

    public func compilerMessage(of effect: EffectSource) async -> String? {
        let id = nextID()
        return await withCheckedContinuation { (continuation: CompilerMessageContinuation) in
            // Recorded and registered in one critical section, as `suspend` does, so a recorded query can always be completed.
            state.withLock { state in
                compilerMessageRequests.append(CompilerMessageRequest(id: id, effect: effect, origin: ObjectIdentifier(self)))
                if state.holdingCompilerMessages {
                    state.waitingCompilerMessages[id] = continuation
                } else {
                    continuation.resume(returning: state.compilerMessageAnswer)
                }
            }
        }
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
