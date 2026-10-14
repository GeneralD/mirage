import Dependencies
import Domain

/// A catalog of one: the bundled default effect, ready. It lists once and then stays
/// as it was, since nothing watches; it knows no package; and it has no folder to
/// open. Registered as the host's live `EffectPackageRepository` until the real
/// Repository lands in this module (epic #42, D10), so the menu always has the effect
/// the runtime is already running.
public struct BundledOnlyCatalog: EffectPackageRepository, Sendable {
    @Dependency(\.bundledEffects) private var bundledEffects

    public init() {}

    public func catalog() -> AsyncStream<[EffectCatalogEntry]> {
        let entries = [entry(of: bundledEffects.defaultEffect)]
        return AsyncStream { $0.yield(entries) }
    }

    public func source(of id: EffectID) async -> Result<EffectSource, EffectPackageProblem> {
        let effect = bundledEffects.defaultEffect
        return id == Self.id(of: effect) ? .success(effect) : .failure(.sourceMissing)
    }

    public func openEffectsFolder() {}

    private func entry(of effect: EffectSource) -> EffectCatalogEntry {
        EffectCatalogEntry(id: Self.id(of: effect), displayName: effect.name, origin: .bundled, availability: .ready)
    }

    private static func id(of effect: EffectSource) -> EffectID {
        EffectID(origin: .bundled, key: effect.name)
    }
}
