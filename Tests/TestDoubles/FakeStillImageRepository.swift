import Dependencies
import Domain
import TestSupport

/// `StillImageRepository` answering from what the test scripted: `read(path)` the result scripted for that path.
/// A path with no script is reported as an issue and answers `.unreadable(path:)`. `write` answers success,
/// or the problem `failWrites(with:)` set. Every read and write is recorded, failing ones included.
public final class FakeStillImageRepository: StillImageRepository, Sendable {
    /// One `write` call: the path and the image it was asked to write.
    public struct Write: Sendable, Equatable {
        public let path: String
        public let image: StillImage

        public init(path: String, image: StillImage) {
            self.path = path
            self.image = image
        }
    }

    private struct State {
        var results: [String: Result<StillImage, StillImageProblem>] = [:]
        var writeFailure: StillImageProblem?
    }

    private let state = Locked(State())
    /// The paths `read` was asked for, in call order.
    public let reads = Collector<String>()
    /// The `write` calls, in call order, failing ones included.
    public let writes = Collector<Write>()

    public init() {}

    /// Makes `read(path)` answer `result`; a later script for the same path replaces it.
    public func script(_ result: Result<StillImage, StillImageProblem>, for path: String) {
        state.withLock { $0.results[path] = result }
    }

    /// Makes every `write` fail with `problem` until the next call with `nil`, which makes them succeed again.
    public func failWrites(with problem: StillImageProblem?) {
        state.withLock { $0.writeFailure = problem }
    }

    public func read(_ path: String) async -> Result<StillImage, StillImageProblem> {
        reads.append(path)
        guard let result = state.withLock({ $0.results[path] }) else {
            reportIssue("FakeStillImageRepository: no image scripted for \(path)")
            return .failure(.unreadable(path: path))
        }
        return result
    }

    public func write(_ image: StillImage, to path: String) async -> Result<Void, StillImageProblem> {
        writes.append(Write(path: path, image: image))
        if let problem = state.withLock({ $0.writeFailure }) {
            return .failure(problem)
        }
        return .success(())
    }
}
