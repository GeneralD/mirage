import Dependencies

/// `EffectPackageDataSource`: the `.lens` packages in the effects folder (epic #42,
/// D1 / D2). It lists the folder, reads and validates each package's `manifest.json`
/// and `effect.metal`, and reports a package it cannot use as `.broken` with the
/// reason instead of leaving it out (D3). Everything it needs from the world comes
/// through `FileSystemGateway`, `WorkspaceGateway` and `AppDirectoriesProvider`.
public protocol EffectPackages: Sendable {
    /// Every package in the effects folder, ready or broken, in no promised order,
    /// with what to watch to learn that the listing is stale. The first listing makes
    /// the folder when it is not there.
    func packages() async -> EffectPackageInventory

    /// One package read afresh, `nil` when the folder has none under that id. The
    /// source a `prepare` compiles comes from here, so a hot reload sees the edit.
    func package(_ id: EffectID) async -> EffectPackageListing?

    /// Shows the effects folder to the user (Finder), making it first when it is not there.
    func openFolder()
}

public enum EffectPackagesKey: TestDependencyKey {
    public static let testValue: any EffectPackages = UnimplementedEffectPackages()
}

extension DependencyValues {
    public var effectPackages: any EffectPackages {
        get { self[EffectPackagesKey.self] }
        set { self[EffectPackagesKey.self] = newValue }
    }
}

private struct UnimplementedEffectPackages: EffectPackages {
    func packages() async -> EffectPackageInventory {
        reportIssue("EffectPackages.packages not implemented")
        return .empty
    }

    func package(_ id: EffectID) async -> EffectPackageListing? {
        reportIssue("EffectPackages.package not implemented")
        return nil
    }

    func openFolder() {
        reportIssue("EffectPackages.openFolder not implemented")
    }
}
