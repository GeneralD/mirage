import Dependencies
import Domain
import TestSupport

/// `EffectPackageRepository` the test pushes catalogs into: `publish(entries)` is the
/// folder changing under the subject. Like the live port, a `catalog()` stream starts
/// at once with the catalog as it stands (the last one published, or the one the fake
/// was made with), then yields every publish; a fake that was given nothing yields
/// nothing until the first publish. `source(of:)` answers what `script(_:for:)` set,
/// and an id nobody scripted is a reported issue answering `.sourceMissing`.
public final class FakeEffectPackageRepository: EffectPackageRepository, Sendable {
    private struct State {
        var latest: [EffectCatalogEntry]?
        var continuations: [Int: AsyncStream<[EffectCatalogEntry]>.Continuation] = [:]
        var nextStream = 0
        var sources: [EffectID: Result<EffectSource, EffectPackageProblem>] = [:]
    }

    private let state: Locked<State>
    /// One entry per `catalog()` call.
    public let catalogRequests = Collector<Void>()
    /// One entry per catalog stream that ended (its consumer was cancelled or stopped iterating).
    public let terminations = Collector<Void>()
    /// The ids `source(of:)` was asked for, in call order.
    public let sourceRequests = Collector<EffectID>()
    /// One entry per `openEffectsFolder()` call.
    public let folderOpens = Collector<Void>()

    public init(entries: [EffectCatalogEntry]? = nil) {
        state = Locked(State(latest: entries))
    }

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
        guard let result = state.withLock({ $0.sources[id] }) else {
            reportIssue("FakeEffectPackageRepository: no source scripted for \(id)")
            return .failure(.sourceMissing)
        }
        return result
    }

    public func openEffectsFolder() {
        folderOpens.append(())
    }

    private func end(_ id: Int) {
        state.withLock { _ = $0.continuations.removeValue(forKey: id) }
        terminations.append(())
    }
}
