import Domain
import TestSupport

/// `ShaderCompiler` whose every `compile` suspends until the test completes it
/// with whatever result it chooses — a handle or diagnostics — exactly once and
/// in any order, so "a slow compile overtaken by a newer one" is a sequence the
/// test writes down (`EffectRuntimeRepository`'s newest-wins). `succeed(_:)` is
/// the common completion: a fresh `FakeLibraryHandle` of the request's source,
/// which `FakeGPUGateway` accepts. A caller whose task is cancelled is resumed
/// with `FakeShaderCompiler.cancelled`, so a stopped caller never leaks a
/// continuation into the suite's time limit; one cancelled before it suspended
/// is never recorded.
public final class FakeShaderCompiler: ShaderCompiler, Sendable {
    public struct Request: Sendable {
        public let id: Int
        public let effect: EffectSource
    }

    /// What a cancelled caller receives.
    public static let cancelled = ShaderDiagnostics(message: "FakeShaderCompiler: caller cancelled", code: -1)

    private typealias Continuation = CheckedContinuation<Result<any LibraryHandle, ShaderDiagnostics>, Never>

    private struct State {
        var nextID = 1
        var waiting: [Int: Continuation] = [:]
        var cancelledBeforeSuspending: Set<Int> = []
    }

    private let state = Locked(State())
    /// Every compile that suspended, in call order, completed or not.
    public let requests = Collector<Request>()

    public init() {}

    /// Compiles that are suspended right now.
    public var pendingCount: Int { state.current.waiting.count }

    public func compile(_ effect: EffectSource) async -> Result<any LibraryHandle, ShaderDiagnostics> {
        let id = state.withLock { state in
            defer { state.nextID += 1 }
            return state.nextID
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: Continuation) in
                // Recorded if and only if registered as waiting, in one critical section.
                let alreadyCancelled = state.withLock { state in
                    guard state.cancelledBeforeSuspending.remove(id) == nil else { return true }
                    state.waiting[id] = continuation
                    requests.append(Request(id: id, effect: effect))
                    return false
                }
                guard !alreadyCancelled else { return continuation.resume(returning: .failure(Self.cancelled)) }
            }
        } onCancel: {
            let continuation = state.withLock { state -> Continuation? in
                guard let waiting = state.waiting.removeValue(forKey: id) else {
                    state.cancelledBeforeSuspending.insert(id)
                    return nil
                }
                return waiting
            }
            continuation?.resume(returning: .failure(Self.cancelled))
        }
    }

    /// Resumes the suspended compile with `result`; `false` when the request is
    /// unknown or was already completed.
    @discardableResult
    public func complete(_ request: Request, with result: Result<any LibraryHandle, ShaderDiagnostics>) -> Bool {
        guard let continuation = state.withLock({ $0.waiting.removeValue(forKey: request.id) }) else { return false }
        continuation.resume(returning: result)
        return true
    }

    /// Completes the request with a fresh `FakeLibraryHandle` of its source and
    /// options and returns that handle; `nil` when the request is unknown or was
    /// already completed.
    @discardableResult
    public func succeed(_ request: Request) -> FakeLibraryHandle? {
        let handle = FakeLibraryHandle(source: request.effect.source, options: request.effect.options)
        return complete(request, with: .success(handle)) ? handle : nil
    }
}
