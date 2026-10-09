import Domain
import TestSupport

/// `GPURenderer` as the Repository suites drive it (#19): every `render` is
/// recorded and suspends until the test completes it with whatever result it
/// chooses — exactly once, in any order — so "the GPU answers after the next
/// frame was captured" is a sequence the test writes down. `respond(with:)`
/// scripts an immediate answer instead (still recorded) for suites that do not
/// care about timing.
///
/// Like the live `GPURenderDataSource`, it does not observe task cancellation:
/// a cancelled caller (even one cancelled before the call) is recorded and keeps
/// waiting for `complete(_:with:)`, then receives that answer. A suite that
/// cancels a render must therefore complete it before it ends, or the suite's
/// time limit reports the leak.
public final class FakeGPURenderer: GPURenderer, Sendable {
    public struct Request: Sendable {
        /// Call order: 1 for the first render that reached the fake, and so on.
        public let id: Int
        public let library: any LibraryHandle
        public let input: SurfaceToken
        public let output: SurfaceToken
        public let uniforms: EffectUniforms
        /// The renderer that issued it: ids restart at 1 per instance, so the id alone cannot tell a stranger's request.
        fileprivate let origin: ObjectIdentifier
    }

    public typealias Answer = Result<GPUTiming, EffectFailure>
    private typealias Continuation = CheckedContinuation<Answer, Never>

    private struct State {
        var nextID = 1
        var scripted: Answer?
        var waiting: [Int: Continuation] = [:]
    }

    private let state = Locked(State())
    /// Every render, answered or not, in the order it reached the fake (its `id`
    /// order). Concurrent callers reach it in the scheduler's order, so a test
    /// that depends on which request is which starts them one at a time
    /// (`requests.waitForCount(n)` between them).
    public let requests = Collector<Request>()

    public init() {}

    /// Renders suspended right now.
    public var pendingCount: Int { state.current.waiting.count }

    /// Makes every later `render` answer at once with `answer`; `nil` returns to
    /// suspending until `complete(_:with:)`.
    public func respond(with answer: Answer?) {
        state.withLock { $0.scripted = answer }
    }

    /// Numbering, recording and registering happen in one critical section, so the
    /// recording order is the `id` order and a recorded request is always either
    /// answered at once or waiting. (`Collector` takes its own lock and never calls
    /// back into `state`, so the nesting cannot deadlock.)
    public func render(
        library: any LibraryHandle, input: SurfaceToken, output: SurfaceToken, uniforms: EffectUniforms
    ) async -> Answer {
        let origin = ObjectIdentifier(self)
        return await withCheckedContinuation { (continuation: Continuation) in
            let scripted = state.withLock { state -> Answer? in
                let request = Request(
                    id: state.nextID, library: library, input: input, output: output, uniforms: uniforms, origin: origin)
                state.nextID += 1
                requests.append(request)
                guard let answer = state.scripted else {
                    state.waiting[request.id] = continuation
                    return nil
                }
                return answer
            }
            if let scripted { continuation.resume(returning: scripted) }
        }
    }

    /// Resumes the suspended `render`; `false` when it is unknown, came from another renderer, or is already answered.
    @discardableResult
    public func complete(_ request: Request, with answer: Answer) -> Bool {
        guard request.origin == ObjectIdentifier(self) else { return false }
        guard let continuation = state.withLock({ $0.waiting.removeValue(forKey: request.id) }) else { return false }
        continuation.resume(returning: answer)
        return true
    }
}
