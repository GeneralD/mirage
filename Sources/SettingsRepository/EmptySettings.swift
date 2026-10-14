import Domain

/// Settings that remember nothing, as `EmptyPreferences` does one layer down.
/// Registered as the host's live `SettingsRepository` until the real Repository lands
/// in this module (epic #42, D10).
public struct EmptySettings: SettingsRepository, Sendable {
    public init() {}

    public func selectedEffect() async -> EffectID? { nil }

    public func setSelectedEffect(_ id: EffectID) async {}
}
