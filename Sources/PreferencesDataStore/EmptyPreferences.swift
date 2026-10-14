import Domain

/// Preferences that remember nothing: no effect was ever chosen, and choosing one is
/// not kept. Registered as the host's live `Preferences` until the real DataStore
/// lands in this module (epic #42, D10), so a relaunch simply starts from the bundled
/// default.
public struct EmptyPreferences: Preferences, Sendable {
    public init() {}

    public func selectedEffect() async -> EffectID? { nil }

    public func setSelectedEffect(_ id: EffectID) async {}
}
