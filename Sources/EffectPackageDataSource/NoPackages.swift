import Domain

/// The effects folder with nothing in it: no listing, no package, nothing to open.
/// Registered as the host's live `EffectPackages` until the real DataSource lands in
/// this module, so a PR merged ahead of it never leaves the host without one (epic
/// #42, D10; the same course `PassthroughEffectRuntimeRepository` took in #14, D18).
public struct NoPackages: EffectPackages, Sendable {
    public init() {}

    public func packages() async -> EffectPackageInventory { .empty }

    public func package(_ id: EffectID) async -> EffectPackageListing? { nil }

    public func openFolder() {}
}
