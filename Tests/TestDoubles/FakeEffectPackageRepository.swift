import Dependencies
import Domain
import TestSupport

/// `EffectPackageRepository` the test pushes catalogs into: `publish(entries)` is the
/// folder changing under the subject. Like the live port, a `catalog()` stream starts
/// at once with the catalog as it stands (the last one published, or the one the fake
/// was made with), then yields every publish, an identical catalog included (the live
/// port lists again after every change, and a shader edit changes no row); a fake that
/// was given nothing yields nothing until the first publish. `source(of:)` answers what
/// `script(_:for:)` set, and an id nobody scripted is a reported issue answering
/// `.sourceMissing`. `check(packageAt:)` answers what `scriptCheck(_:for:)` set for its path, and
/// `scaffold(named:in:)` what `scriptScaffold(_:)` set; each records its call, and a call nobody scripted is a
/// reported issue answering `.packageNotFound(path:)` or `.unwritable(path:)`.
///
/// `source(of:)` answers at once unless the test asked to hold the reads
/// (`holdSources()`): then each one suspends, like a read of files that are still being
/// written, until the test completes it (`completeSource(_:with:)`), in any order. That
/// is how "something else happens while the subject waits for a source" is a sequence
/// the test writes down. Like the live Repository it ignores the caller's cancellation:
/// a cancelled read stays parked until the test completes it.
public final class FakeEffectPackageRepository: EffectPackageRepository, Sendable {
    /// One `source(of:)` call that is parked until the test completes it.
    public struct SourceRequest: Sendable {
        public let id: Int
        public let effect: EffectID
        /// What the files said when the read began: the scripted answer of that moment, which is what
        /// completing the request answers unless the test says otherwise.
        public let result: Result<EffectSource, EffectPackageProblem>
        /// The repository that issued it: ids restart at 1 per instance, so the id alone cannot tell a stranger's request.
        fileprivate let origin: ObjectIdentifier
    }

    /// One `scaffold(named:in:)` call: the name and the folder it was asked for.
    public struct ScaffoldRequest: Sendable, Equatable {
        public let name: String
        public let folder: String

        public init(name: String, folder: String) {
            self.name = name
            self.folder = folder
        }
    }

    private typealias SourceContinuation = CheckedContinuation<Result<EffectSource, EffectPackageProblem>, Never>

    private struct State {
        var latest: [EffectCatalogEntry]?
        var continuations: [Int: AsyncStream<[EffectCatalogEntry]>.Continuation] = [:]
        var nextStream = 0
        var sources: [EffectID: Result<EffectSource, EffectPackageProblem>] = [:]
        var holding = false
        var nextSource = 1
        var parked: [Int: SourceContinuation] = [:]
        var checks: [String: Result<EffectSource, AuthoringFailure>] = [:]
        var scaffoldResult: Result<String, ScaffoldProblem>? = nil
    }

    private let state: Locked<State>
    /// One entry per `catalog()` call.
    public let catalogRequests = Collector<Void>()
    /// One entry per catalog stream that ended (its consumer was cancelled or stopped iterating).
    public let terminations = Collector<Void>()
    /// The ids `source(of:)` was asked for, in call order, held or not.
    public let sourceRequests = Collector<EffectID>()
    /// The reads that were parked (`holdSources()`), in call order. A request is recorded in the
    /// same step that parks it, so a test that sees one can always complete it.
    public let heldSources = Collector<SourceRequest>()
    /// One entry per `openEffectsFolder()` call.
    public let folderOpens = Collector<Void>()
    /// The paths `check(packageAt:)` was asked for, in call order.
    public let checkRequests = Collector<String>()
    /// The name and folder each `scaffold(named:in:)` call was asked for, in call order.
    public let scaffoldRequests = Collector<ScaffoldRequest>()

    public init(entries: [EffectCatalogEntry]? = nil) {
        state = Locked(State(latest: entries))
    }

    /// Reads that are parked right now.
    public var pendingSourceCount: Int { state.current.parked.count }

    /// Makes `entries` the catalog: every open stream yields it, and a stream opened
    /// later starts with it.
    public func publish(_ entries: [EffectCatalogEntry]) {
        state.withLock { state in
            state.latest = entries
            for continuation in state.continuations.values { continuation.yield(entries) }
        }
    }

    /// Makes `source(of: id)` answer `result`.
    public func script(_ result: Result<EffectSource, EffectPackageProblem>, for id: EffectID) {
        state.withLock { $0.sources[id] = result }
    }

    /// From now on every `source(of:)` suspends until `completeSource(_:with:)`; `holdSources(false)` goes
    /// back to answering at once (reads already parked stay parked).
    public func holdSources(_ holding: Bool = true) {
        state.withLock { $0.holding = holding }
    }

    /// Resumes the parked read with `result`, or with what was scripted when the read began; `false` when
    /// it is unknown, came from another repository, or is already resumed.
    @discardableResult
    public func completeSource(_ request: SourceRequest, with result: Result<EffectSource, EffectPackageProblem>? = nil) -> Bool {
        guard request.origin == ObjectIdentifier(self) else { return false }
        guard let continuation = state.withLock({ $0.parked.removeValue(forKey: request.id) }) else { return false }
        continuation.resume(returning: result ?? request.result)
        return true
    }

    public func catalog() -> AsyncStream<[EffectCatalogEntry]> {
        let (stream, continuation) = AsyncStream<[EffectCatalogEntry]>.makeStream()
        let id = state.withLock { state -> Int in
            let id = state.nextStream
            state.nextStream += 1
            state.continuations[id] = continuation
            state.latest.map { _ = continuation.yield($0) }
            return id
        }
        continuation.onTermination = { [weak self] _ in self?.end(id) }
        catalogRequests.append(())
        return stream
    }

    public func source(of id: EffectID) async -> Result<EffectSource, EffectPackageProblem> {
        sourceRequests.append(id)
        let result = scriptedSource(for: id)
        return await withCheckedContinuation { (continuation: SourceContinuation) in
            state.withLock { state in
                guard state.holding else { return continuation.resume(returning: result) }
                let requestID = state.nextSource
                state.nextSource += 1
                state.parked[requestID] = continuation
                heldSources.append(SourceRequest(id: requestID, effect: id, result: result, origin: ObjectIdentifier(self)))
            }
        }
    }

    public func openEffectsFolder() {
        folderOpens.append(())
    }

    /// Makes `check(packageAt: path)` answer `result`.
    public func scriptCheck(_ result: Result<EffectSource, AuthoringFailure>, for path: String) {
        state.withLock { $0.checks[path] = result }
    }

    /// Makes `scaffold(named:in:)` answer `result` from now on, until it is scripted again.
    public func scriptScaffold(_ result: Result<String, ScaffoldProblem>) {
        state.withLock { $0.scaffoldResult = result }
    }

    public func check(packageAt path: String) async -> Result<EffectSource, AuthoringFailure> {
        checkRequests.append(path)
        guard let result = state.withLock({ $0.checks[path] }) else {
            reportIssue("FakeEffectPackageRepository: no check scripted for \(path)")
            return .failure(.packageNotFound(path: path))
        }
        return result
    }

    public func scaffold(named name: String, in folder: String) async -> Result<String, ScaffoldProblem> {
        scaffoldRequests.append(ScaffoldRequest(name: name, folder: folder))
        guard let result = state.withLock({ $0.scaffoldResult }) else {
            reportIssue("FakeEffectPackageRepository: no scaffold result scripted")
            return .failure(.unwritable(path: folder))
        }
        return result
    }

    private func scriptedSource(for id: EffectID) -> Result<EffectSource, EffectPackageProblem> {
        guard let result = state.withLock({ $0.sources[id] }) else {
            reportIssue("FakeEffectPackageRepository: no source scripted for \(id)")
            return .failure(.sourceMissing)
        }
        return result
    }

    private func end(_ id: Int) {
        state.withLock { _ = $0.continuations.removeValue(forKey: id) }
        terminations.append(())
    }
}
