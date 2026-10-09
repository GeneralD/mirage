import Domain
import TestSupport

/// `GPURenderer` as the Repository suites drive it (#19): every `render` is
/// recorded and suspends until the test completes it with whatever result it
/// chooses — exactly once, in any order — so "the GPU answers after the next
/// frame was captured" is a sequence the test writes down. `respond(with:)`
/// scripts an immediate answer instead (still recorded) for suites that do not
/// care about timing. A caller whose task is cancelled while suspended is
/// resumed with `.failure(.internalError)`, so a stopped pipeline never leaks a
/// continuation into the suite's time limit.
public final class FakeGPURenderer: GPURenderer, Sendable {
    public struct Request: Sendable {
        public let id: Int
        public let library: any LibraryHandle
        public let input: SurfaceToken
        public let output: SurfaceToken
        public let uniforms: EffectUniforms
    }

    public typealias Answer = Result<GPUTiming, EffectFailure>
    private typealias Continuation = CheckedContinuation<Answer, Never>

    private struct State {
        var nextID = 1
        var scripted: Answer?
        var waiting: [Int: Continuation] = [:]
        var cancelledBeforeSuspending: Set<Int> = []
    }

    private let state = Locked(State())
    /// Every render handed in, in call order, answered or not.
    public let requests = Collector<Request>()

    public init() {}

    /// Renders suspended right now.
    public var pendingCount: Int { state.current.waiting.count }

    /// Makes every later `render` answer at once with `answer`; `nil` returns to
    /// suspending until `complete(_:with:)`.
    public func respond(with answer: Answer?) {
        state.withLock { $0.scripted = answer }
    }

    public func render(library: any LibraryHandle, input: SurfaceToken, output: SurfaceToken, uniforms: EffectUniforms) async -> Answer {
        let (id, scripted) = state.withLock { state in
            defer { state.nextID += 1 }
            return (state.nextID, state.scripted)
        }
        let request = Request(id: id, library: library, input: input, output: output, uniforms: uniforms)
        guard let scripted else { return await suspend(request) }
        requests.append(request)
        return scripted
    }

    /// Resumes the suspended `render`; `false` when it is unknown or already answered.
    @discardableResult
    public func complete(_ request: Request, with answer: Answer) -> Bool {
        guard let continuation = state.withLock({ $0.waiting.removeValue(forKey: request.id) }) else { return false }
        continuation.resume(returning: answer)
        return true
    }

    /// A request is recorded if and only if it was registered as waiting, in one
    /// critical section, so a cancellation never leaves a recorded request that was
    /// already resumed, and a caller cancelled before it suspended is never recorded.
    /// (`Collector` takes its own lock and never calls back into `state`.)
    private func suspend(_ request: Request) async -> Answer {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: Continuation) in
                let alreadyCancelled = state.withLock { state in
                    guard state.cancelledBeforeSuspending.remove(request.id) == nil else { return true }
                    state.waiting[request.id] = continuation
                    requests.append(request)
                    return false
                }
                guard !alreadyCancelled else { return continuation.resume(returning: .failure(.internalError)) }
            }
        } onCancel: {
            let continuation = state.withLock { state -> Continuation? in
                guard let waiting = state.waiting.removeValue(forKey: request.id) else {
                    state.cancelledBeforeSuspending.insert(request.id)
                    return nil
                }
                return waiting
            }
            continuation?.resume(returning: .failure(.internalError))
        }
    }
}
