import Dependencies
import Domain
import Foundation

/// The effect catalog: the bundled effects and the `.lens` packages in the effects
/// folder, assembled into one list that lists itself again after every change (epic
/// #42, D3 / D4). It holds no state of its own: a listing is made from what `EffectPackages`
/// answers now, shown, and watched until something changes, and then made again. The one
/// thing a catalog remembers is what it logged about broken packages (*The log* below).
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
/// bundled effects first, in the order `BundledEffects.effects` gives them, then the
/// packages by display name — case-insensitive, numeric runs compared as numbers ("Effect 2"
/// before "Effect 10"), and the folder name as the tie-break, so two packages with one
/// manifest name keep a fixed order. The comparison does not consult the locale, so the menu
/// reads the same on every machine. A broken
/// package is listed under its folder name, as `.broken`, among the others.
///
/// **The log** says a broken package when it changes, not on every listing that shows it. Each
/// catalog stream remembers the problem every broken package had in its last listing, in its own
/// task: a package that was not broken then, or whose problem is not equal to the one it had
/// (its kind, or the reason it carries), is logged once, as an error when a file exists and cannot
/// be read and as a developer line otherwise; one that was broken and is ready now is logged once
/// as readable again; a package that stays as it was is not logged again, and one that left the
/// folder is forgotten without a line. A listing with no packages in it forgets them all the same
/// way, and that includes a folder that cannot be listed, which gives an empty listing too (the
/// DataSource logs why): the Repository cannot tell the two apart, so a broken package it hid is
/// logged again when the folder lists. A new stream starts with nothing remembered, so each run of
/// the menu logs what it finds once. `source(of:)` logs nothing, and neither does the DataSource
/// for a broken package.
///
/// **`source(of:)`** reads afresh on every call and caches nothing: a hot reload is the
/// UseCase comparing what this answers now with what it answered last. A bundled id
/// answers the first of `BundledEffects.effects` that has that id, and one none of them has
/// is `.sourceMissing`; a package is read through `EffectPackages.package(_:)`, which
/// answers `.ready` (its source), `.broken` (its problem) or nothing at all — a folder
/// that is gone — which is `.manifestMissing`, the first thing a package lacks.
///
/// **`check(packageAt:)`** reads the package at a path the author gave and compiles its shader through
/// `ShaderCompiler`, the port the runtime compiles through. A missing package is `.packageNotFound(path:)`
/// here, where `source(of:)` answers `.manifestMissing`: the path is what the author asked for, so the path
/// is what is missing. A successful compile is let go, and nothing is cached. **`scaffold(named:in:)`** is a
/// pass-through to `EffectPackages.scaffold`.
public struct EffectPackageRepositoryImpl: Sendable {
    @Dependency(\.effectPackages) private var effectPackages
    @Dependency(\.effectWatch) private var effectWatch
    @Dependency(\.bundledEffects) private var bundledEffects
    @Dependency(\.shaderCompiler) private var shaderCompiler
    @Dependency(\.errorLog) private var errorLog
    @Dependency(\.developerLog) private var developerLog

    public init() {}
}

extension EffectPackageRepositoryImpl: EffectPackageRepository {
    public func catalog() -> AsyncStream<[EffectCatalogEntry]> {
        let (stream, continuation) = AsyncStream<[EffectCatalogEntry]>.makeStream()
        let keepingCurrent = Task { [self] in
            var broken: [EffectID: EffectPackageProblem] = [:]
            while let listed = await listAndWatch(into: continuation, after: broken) { broken = listed }
            developerLog.record(.effect, "catalog ended")
            continuation.finish()
        }
        continuation.onTermination = { _ in keepingCurrent.cancel() }
        return stream
    }

    public func source(of id: EffectID) async -> Result<EffectSource, EffectPackageProblem> {
        switch id.origin {
        case .bundled:
            guard let effect = bundledEffects.effects.first(where: { Self.id(of: $0) == id }) else { return .failure(.sourceMissing) }
            return .success(effect)
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

    public func check(packageAt path: String) async -> Result<EffectSource, AuthoringFailure> {
        switch await effectPackages.package(atPath: path) {
        case .ready(let package):
            switch await shaderCompiler.compile(package.source) {
            case .success: return .success(package.source)
            case .failure(let diagnostics): return .failure(.compile(message: diagnostics.message))
            }
        case .broken(_, let problem): return .failure(.package(problem))
        case nil: return .failure(.packageNotFound(path: path))
        }
    }

    public func scaffold(named name: String, in folder: String) async -> Result<String, ScaffoldProblem> {
        await effectPackages.scaffold(named: name, in: folder)
    }
}

extension EffectPackageRepositoryImpl {
    /// One round: list the folder, arm the watch for what was listed, log what changed about the
    /// broken packages since `broken` (the last round's), show the catalog, and wait for the watch
    /// to hear something. The answer is the broken packages of this listing when the watch did (list
    /// again, with them to compare against); `nil` when there is nothing more to do: the consumer let
    /// go, or the watch ended by itself — which its contract never does, so the catalog would silently
    /// stop being kept current if this went on listening, and its stream ends instead.
    /// The watch is let go before this returns, so the next round starts without one.
    private func listAndWatch(
        into continuation: AsyncStream<[EffectCatalogEntry]>.Continuation, after broken: [EffectID: EffectPackageProblem]
    ) async -> [EffectID: EffectPackageProblem]? {
        let inventory = await effectPackages.packages()
        guard !Task.isCancelled else { return nil }
        let changes = effectWatch.changes(of: inventory.watchSet)
        let listed = logChanges(in: inventory.listings, since: broken)
        let packages = inventory.listings.map(Self.entry(of:)).sorted(by: Self.inMenuOrder)
        let entries = bundledEffects.effects.map(Self.entry(of:)) + packages
        developerLog.record(.effect, "catalog listed: \(entries.count) entries, \(packages.filter { $0.availability != .ready }.count) broken")
        continuation.yield(entries)
        for await _ in changes { return listed }
        if !Task.isCancelled {
            errorLog.record(.effect, "effect watch ended on its own: the catalog is no longer kept current")
        }
        return nil
    }

    /// Logs the transitions of the broken packages between the last listing and this one (see *The log*
    /// above), and answers this listing's broken packages, the memory the next round compares with.
    private func logChanges(
        in listings: [EffectPackageListing], since broken: [EffectID: EffectPackageProblem]
    ) -> [EffectID: EffectPackageProblem] {
        for listing in listings {
            switch listing {
            case .broken(let id, let problem) where broken[id] != problem:
                report(problem, of: id)
            case .ready(let package) where broken[package.id] != nil:
                developerLog.record(.effect, "package \(package.id.key) is readable again")
            case .broken, .ready:
                break
            }
        }
        return listings.reduce(into: [EffectID: EffectPackageProblem]()) { memory, listing in
            if case .broken(let id, let problem) = listing { memory[id] = problem }
        }
    }

    /// A broken package's reason: an operational failure (a file that exists and cannot be read) is an
    /// error, every other reason a developer line.
    private func report(_ problem: EffectPackageProblem, of id: EffectID) {
        switch problem {
        case .unreadable(let message): errorLog.record(.effect, "package \(id.key): \(message)")
        case .manifestMissing, .manifestInvalid, .unsupportedFormatVersion, .sourceMissing:
            developerLog.record(.effect, "package \(id.key) is broken: \(problem)")
        }
    }

    private static func id(of effect: EffectSource) -> EffectID {
        EffectID(origin: .bundled, key: effect.name)
    }

    private static func entry(of effect: EffectSource) -> EffectCatalogEntry {
        EffectCatalogEntry(id: id(of: effect), displayName: effect.name, origin: .bundled, availability: .ready)
    }

    /// A package shows its manifest's `name`, `author` and `description`, and the thumbnail it was
    /// read with; a broken one has none of them, so it shows its folder name, no author, no
    /// description and no thumbnail.
    private static func entry(of listing: EffectPackageListing) -> EffectCatalogEntry {
        switch listing {
        case .ready(let package):
            EffectCatalogEntry(
                id: package.id, displayName: package.manifest.name, origin: package.id.origin, availability: .ready,
                author: package.manifest.author, thumbnail: package.thumbnail, description: package.manifest.description)
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
