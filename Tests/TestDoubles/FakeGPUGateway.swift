import Dependencies
import Domain
import TestSupport

/// The context `FakeGPUGateway` mints; identity is the object itself.
public final class FakeGPUContextHandle: GPUContextHandle, Sendable {
    public init() {}

    public var backing: AnyObject { self }
}

/// `GPUGateway` as the test drives it: every `encodeAndCommit` is recorded as a
/// `Submission` and stays pending until the test completes it with any
/// `GPUCompletion`, in any order — so "the second pass finishes first" and "a
/// completion carries a raw page-fault code" are sequences the test writes
/// down, never provoked. Handles must be the fakes' (`FakeGPUContextHandle`,
/// `FakeLibraryHandle`, `FakeTextureHandle`); anything else is
/// `GPUError.foreignHandle` before anything is recorded, as with the live gateway.
public final class FakeGPUGateway: GPUGateway, Sendable {
    public struct Submission: Sendable {
        public let id: Int
        public let pass: ComputePass
    }

    private struct State {
        var nextID = 1
        var contextCount = 0
        var pending: [Int: @Sendable (GPUCompletion) -> Void] = [:]
        var makeContextError: GPUError?
        var encodeError: GPUError?
    }

    private let state = Locked(State())
    /// Every pass handed in, in submission order, completed or not.
    public let submissions = Collector<Submission>()

    public init() {}

    public var contextCount: Int { state.current.contextCount }

    /// The submissions not yet completed, in submission order.
    public var pending: [Submission] {
        let ids = state.current.pending
        return submissions.values.filter { ids[$0.id] != nil }
    }

    public func failMakeContext(with error: GPUError?) {
        state.withLock { $0.makeContextError = error }
    }

    public func failEncode(with error: GPUError?) {
        state.withLock { $0.encodeError = error }
    }

    public func makeContext() throws -> any GPUContextHandle {
        try state.withLock { state in
            if let error = state.makeContextError { throw error }
            state.contextCount += 1
            return FakeGPUContextHandle()
        }
    }

    public func encodeAndCommit(
        _ pass: ComputePass, on context: any GPUContextHandle, completion: @escaping @Sendable (GPUCompletion) -> Void
    ) throws {
        _ = try (context as? FakeGPUContextHandle).orThrow(GPUError.foreignHandle)
        _ = try (pass.kernel as? FakeLibraryHandle).orThrow(GPUError.foreignHandle)
        _ = try pass.textures.map { try ($0 as? FakeTextureHandle).orThrow(GPUError.foreignHandle) }
        let submission = try state.withLock { state in
            if let error = state.encodeError { throw error }
            let id = state.nextID
            state.nextID += 1
            state.pending[id] = completion
            return Submission(id: id, pass: pass)
        }
        submissions.append(submission)
    }

    /// Delivers `completion` to the pass's handler, once. `false` when the
    /// submission is unknown or was already completed — a double completion is
    /// a bug in the test, and it is reported as one.
    @discardableResult
    public func complete(_ submission: Submission, with completion: GPUCompletion) -> Bool {
        guard let handler = state.withLock({ $0.pending.removeValue(forKey: submission.id) }) else {
            reportIssue("FakeGPUGateway: submission \(submission.id) completed twice or never submitted")
            return false
        }
        handler(completion)
        return true
    }
}
