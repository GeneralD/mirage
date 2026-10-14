import Dependencies
import Domain
import Foundation

/// The effect catalog: the bundled effect and the `.lens` packages in the effects
/// folder, assembled into one list that lists itself again after every change (epic
/// #42, D3 / D4). It holds no state: a listing is made from what `EffectPackages`
/// answers now, shown, and watched until something changes, and then made again.
///
/// **`catalog()`** is eager. Making the stream starts a task of its own, off the frame
/// path, that lists the folder, arms the watch the inventory asks for
/// (`EffectWatch.changes(of:)`), shows the catalog, and waits for the watch. An element
/// from the watch ends that round: the old watch is let go, the folder is listed again
/// and the next round arms a watch for the *new* inventory's set, since a package that
/// arrived or went away changes what there is to watch. The watch is armed before the
/// catalog is shown, so the first change after any catalog a consumer has seen is heard.
/// A re-listing itself is not watched: its set comes from the listing, so an edit that
/// lands after a file was read and before the next watch is armed is heard only with
/// the change after it. Every element is a listing and every listing is shown, even when
/// it equals the one before: coalescing a burst is the watch's (`EffectWatchDataSource`
/// folds events on the injected clock), and a listing that looks the same may still be
/// a package whose `effect.metal` changed, which is what the UseCase re-reads to find
/// out. Ending the stream (the consumer lets go) cancels the task, which lets go of
/// the watch it armed. When its work is over the task records that the catalog ended,
/// on whichever side the end came from: the consumer, or the watch.
///
/// **The order** is decided here, not by the DataSource, which promises none: the
/// bundled effect first, then the packages by display name — case-insensitive, numeric
/// runs compared as numbers ("Effect 2" before "Effect 10"), and the folder name as the
/// tie-break, so two packages with one manifest name keep a fixed order. The comparison
/// does not consult the locale, so the menu reads the same on every machine. A broken
/// package is listed under its folder name, as `.broken`, among the others.
///
/// **`source(of:)`** reads afresh on every call and caches nothing: a hot reload is the
/// UseCase comparing what this answers now with what it answered last. The bundled
/// effect's id answers `BundledEffects.defaultEffect`; another bundled id is
/// `.sourceMissing`; a package is read through `EffectPackages.package(_:)`, which
/// answers `.ready` (its source), `.broken` (its problem) or nothing at all — a folder
/// that is gone — which is `.manifestMissing`, the first thing a package lacks.
public struct EffectPackageRepositoryImpl: Sendable {
    @Dependency(\.effectPackages) private var effectPackages
    @Dependency(\.effectWatch) private var effectWatch
    @Dependency(\.bundledEffects) private var bundledEffects
    @Dependency(\.errorLog) private var errorLog
    @Dependency(\.developerLog) private var developerLog

    public init() {}
}

extension EffectPackageRepositoryImpl: EffectPackageRepository {
    public func catalog() -> AsyncStream<[EffectCatalogEntry]> {
        let (stream, continuation) = AsyncStream<[EffectCatalogEntry]>.makeStream()
        let keepingCurrent = Task { [self] in
            while await listAndWatch(into: continuation) {}
            developerLog.record(.effect, "catalog ended")
            continuation.finish()
        }
        continuation.onTermination = { _ in keepingCurrent.cancel() }
        return stream
    }

    public func source(of id: EffectID) async -> Result<EffectSource, EffectPackageProblem> {
        switch id.origin {
        case .bundled:
            let effect = bundledEffects.defaultEffect
            return id == Self.id(of: effect) ? .success(effect) : .failure(.sourceMissing)
        case .package:
            switch await effectPackages.package(id) {
            case .ready(let package): return .success(package.source)
            case .broken(_, let problem): return .failure(problem)
            case nil: return .failure(.manifestMissing)
            }
        }
    }

    public func openEffectsFolder() {
        effectPackages.openFolder()
    }
}

extension EffectPackageRepositoryImpl {
    /// One round: list the folder, arm the watch for what was listed, show the catalog,
    /// and wait for the watch to hear something. `true` when it did (list again);
    /// `false` when there is nothing more to do: the consumer let go, or the watch ended
    /// by itself — which its contract never does, so the catalog would silently stop
    /// being kept current if this went on listening, and its stream ends instead.
    /// The watch is let go before this returns, so the next round starts without one.
    private func listAndWatch(into continuation: AsyncStream<[EffectCatalogEntry]>.Continuation) async -> Bool {
        let inventory = await effectPackages.packages()
        guard !Task.isCancelled else { return false }
        let changes = effectWatch.changes(of: inventory.watchSet)
        let packages = inventory.listings.map(Self.entry(of:)).sorted(by: Self.inMenuOrder)
        let entries = [Self.entry(of: bundledEffects.defaultEffect)] + packages
        developerLog.record(.effect, "catalog listed: \(entries.count) entries, \(packages.filter { $0.availability != .ready }.count) broken")
        continuation.yield(entries)
        for await _ in changes { return true }
        if !Task.isCancelled {
            errorLog.record(.effect, "effect watch ended on its own: the catalog is no longer kept current")
        }
        return false
    }

    private static func id(of effect: EffectSource) -> EffectID {
        EffectID(origin: .bundled, key: effect.name)
    }

    private static func entry(of effect: EffectSource) -> EffectCatalogEntry {
        EffectCatalogEntry(id: id(of: effect), displayName: effect.name, origin: .bundled, availability: .ready)
    }

    /// A package shows its manifest's `name`; one whose manifest cannot be read has
    /// none, so it shows its folder name.
    private static func entry(of listing: EffectPackageListing) -> EffectCatalogEntry {
        switch listing {
        case .ready(let package):
            EffectCatalogEntry(id: package.id, displayName: package.manifest.name, origin: package.id.origin, availability: .ready)
        case .broken(let id, let problem):
            EffectCatalogEntry(id: id, displayName: id.key, origin: id.origin, availability: .broken(problem))
        }
    }

    private static func inMenuOrder(_ lhs: EffectCatalogEntry, _ rhs: EffectCatalogEntry) -> Bool {
        switch lhs.displayName.compare(rhs.displayName, options: [.caseInsensitive, .numeric]) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: lhs.id.key < rhs.id.key
        }
    }
}
