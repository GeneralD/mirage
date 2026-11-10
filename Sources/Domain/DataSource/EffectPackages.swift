import Dependencies

/// `EffectPackageDataSource`: the `.lens` packages in the effects folder (epic #42,
/// D1 / D2). It lists the folder, reads and validates each package's `manifest.json`
/// and `effect.metal`, and reports a package it cannot use as `.broken` with the
/// reason instead of leaving it out (D3); a ready package carries the thumbnail its
/// manifest names when that can be used (#12). Everything it needs from the world comes
/// through `FileSystemGateway`, `WorkspaceGateway` and `AppDirectoriesProvider`.
public protocol EffectPackages: Sendable {
    /// Every package in the effects folder, ready or broken, in no promised order,
    /// with what to watch to learn that the listing is stale. The first listing makes
    /// the folder when it is not there.
    func packages() async -> EffectPackageInventory

    /// One package read afresh, `nil` when the folder has none under that id. The
    /// source a `prepare` compiles comes from here, so a hot reload sees the edit. A
    /// ready package comes without its thumbnail, which travels with `packages()`.
    func package(_ id: EffectID) async -> EffectPackageListing?

    /// One package read afresh from `path`, wherever it is: a directory outside the effects
    /// folder is read where it is, and neither the folder nor the directory is made or opened.
    /// `nil` when `path` is not a directory, or its last component does not name a package
    /// (empty, or `/` alone). The id is the last component without its `.lens` (`EffectID(origin: .package, key:)`).
    /// A trailing `/` is ignored. A ready package comes without its thumbnail, as in `package(_:)`.
    func package(atPath path: String) async -> EffectPackageListing?

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

    func package(atPath path: String) async -> EffectPackageListing? {
        reportIssue("EffectPackages.package(atPath:) not implemented")
        return nil
    }

    func openFolder() {
        reportIssue("EffectPackages.openFolder not implemented")
    }
}
