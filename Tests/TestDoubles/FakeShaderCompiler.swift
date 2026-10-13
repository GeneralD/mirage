import Domain
import TestSupport

/// `ShaderCompiler` whose every `compile` suspends until the test completes it
/// with whatever result it chooses — a handle or diagnostics — exactly once and
/// in any order, so "a slow compile overtaken by a newer one" is a sequence the
/// test writes down (`EffectRuntimeStateDataSource`'s newest-wins). `succeed(_:)` is
/// the common completion: a fresh `FakeLibraryHandle` of the request's source,
/// which `FakeGPUGateway` accepts.
///
/// Cancellation is the port's contract, as live: a cancelled caller is neither
/// resumed early nor dropped. It stays suspended until the test completes its
/// request and then receives that result, so "the old compile succeeds after
/// its caller was cancelled" can be written down too. Every request a test
/// starts must therefore be completed; one left pending is reported by the
/// suite's time limit, never hidden. A request is completed only by the
/// compiler that issued it: another instance refuses it, even with a matching id.
public final class FakeShaderCompiler: ShaderCompiler, Sendable {
    public struct Request: Sendable {
        public let id: Int
        public let effect: EffectSource
        /// The compiler that issued it: ids restart at 1 per instance, so the id alone cannot tell a stranger's request.
        fileprivate let origin: ObjectIdentifier
    }

    private typealias Continuation = CheckedContinuation<Result<any LibraryHandle, ShaderDiagnostics>, Never>

    private struct State {
        var nextID = 1
        var waiting: [Int: Continuation] = [:]
    }

    private let state = Locked(State())
    /// Every compile that suspended, in call order, completed or not.
    public let requests = Collector<Request>()

    public init() {}

    /// Compiles that are suspended right now.
    public var pendingCount: Int { state.current.waiting.count }

    public func compile(_ effect: EffectSource) async -> Result<any LibraryHandle, ShaderDiagnostics> {
        await withCheckedContinuation { (continuation: Continuation) in
            // Registered as waiting and recorded in one critical section, so a test
            // that sees the request can always complete it.
            state.withLock { state in
                let id = state.nextID
                state.nextID += 1
                state.waiting[id] = continuation
                requests.append(Request(id: id, effect: effect, origin: ObjectIdentifier(self)))
            }
        }
    }

    /// Resumes the suspended compile with `result`; `false` when the request is
    /// unknown, came from another compiler, or was already completed.
    @discardableResult
    public func complete(_ request: Request, with result: Result<any LibraryHandle, ShaderDiagnostics>) -> Bool {
        guard request.origin == ObjectIdentifier(self) else { return false }
        guard let continuation = state.withLock({ $0.waiting.removeValue(forKey: request.id) }) else { return false }
        continuation.resume(returning: result)
        return true
    }

    /// Completes the request with a fresh `FakeLibraryHandle` of its source and
    /// options and returns that handle; `nil` when the request is unknown, came
    /// from another compiler, or was already completed.
    @discardableResult
    public func succeed(_ request: Request) -> FakeLibraryHandle? {
        let handle = FakeLibraryHandle(source: request.effect.source, options: request.effect.options)
        return complete(request, with: .success(handle)) ? handle : nil
    }
}
