import Dependencies

/// `EffectPackageRepository`: the effects the user can choose from — the bundled
/// ones and the packages in the effects folder — as one catalog that keeps itself
/// current (epic #42, D3 / D4). It assembles `EffectCatalogEntry`s from the bundled
/// effects and the package listings, and listing again whenever `EffectWatch` reports
/// a change is its cache strategy. It does not know which entry is chosen.
public protocol EffectPackageRepository: Sendable {
    /// The catalog now, then again after every change, until the stream ends.
    ///
    /// - The first element comes at once (the folder is listed when this is iterated),
    ///   so a consumer never waits for a change to see the catalog.
    /// - The bundled effect is always first; packages follow by name, a broken one as
    ///   an entry with `.broken`, never left out.
    /// - Ending the stream ends the watch under it.
    func catalog() -> AsyncStream<[EffectCatalogEntry]>

    /// The source to compile for `id`, read afresh: the bundled effect's, or the
    /// package's `effect.metal`. A package that has become unusable, or an id the catalog
    /// no longer has, answers with the reason (`.sourceMissing` for an id nothing has).
    func source(of id: EffectID) async -> Result<EffectSource, EffectPackageProblem>

    /// Shows the effects folder to the user.
    func openEffectsFolder()
}

public enum EffectPackageRepositoryKey: TestDependencyKey {
    public static let testValue: any EffectPackageRepository = UnimplementedEffectPackageRepository()
}

extension DependencyValues {
    public var effectPackageRepository: any EffectPackageRepository {
        get { self[EffectPackageRepositoryKey.self] }
        set { self[EffectPackageRepositoryKey.self] = newValue }
    }
}

private struct UnimplementedEffectPackageRepository: EffectPackageRepository {
    func catalog() -> AsyncStream<[EffectCatalogEntry]> {
        reportIssue("EffectPackageRepository.catalog not implemented")
        return AsyncStream { $0.finish() }
    }

    func source(of id: EffectID) async -> Result<EffectSource, EffectPackageProblem> {
        reportIssue("EffectPackageRepository.source not implemented")
        return .failure(.sourceMissing)
    }

    func openEffectsFolder() {
        reportIssue("EffectPackageRepository.openEffectsFolder not implemented")
    }
}
