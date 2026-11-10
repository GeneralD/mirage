import Dependencies

/// `PreferencesDataStore`: what the user chose, kept between launches, over
/// `KeyValueStoreGateway`. The first DataStore: persistence-shaped knowledge (the
/// key, the encoding of an `EffectID` in a string) that is neither a Gateway's thin
/// pass-through nor a DataSource's work against a changing world.
public protocol Preferences: Sendable {
    /// The effect chosen last time, `nil` when none was chosen or what was stored does
    /// not decode (a value written by another build is not an error).
    func selectedEffect() async -> EffectID?

    func setSelectedEffect(_ id: EffectID) async

    /// The records of disabled effects kept across launches, `[]` when none was stored or what was
    /// stored does not decode as a whole (a value written by another build is not an error).
    func disabledEffects() async -> [DisabledEffectRecord]

    /// Replaces every stored record with `records`; an empty array is stored as an empty array.
    func setDisabledEffects(_ records: [DisabledEffectRecord]) async

    /// Whether the global hotkeys are on, `true` when nothing was stored or what was stored does
    /// not decode (a value written by another build is not an error).
    func hotkeysEnabled() async -> Bool

    func setHotkeysEnabled(_ on: Bool) async
}

public enum PreferencesKey: TestDependencyKey {
    public static let testValue: any Preferences = UnimplementedPreferences()
}

extension DependencyValues {
    public var preferences: any Preferences {
        get { self[PreferencesKey.self] }
        set { self[PreferencesKey.self] = newValue }
    }
}

private struct UnimplementedPreferences: Preferences {
    func selectedEffect() async -> EffectID? {
        reportIssue("Preferences.selectedEffect not implemented")
        return nil
    }

    func setSelectedEffect(_ id: EffectID) async {
        reportIssue("Preferences.setSelectedEffect not implemented")
    }

    func disabledEffects() async -> [DisabledEffectRecord] {
        reportIssue("Preferences.disabledEffects not implemented")
        return []
    }

    func setDisabledEffects(_ records: [DisabledEffectRecord]) async {
        reportIssue("Preferences.setDisabledEffects not implemented")
    }

    func hotkeysEnabled() async -> Bool {
        reportIssue("Preferences.hotkeysEnabled not implemented")
        return true
    }

    func setHotkeysEnabled(_ on: Bool) async {
        reportIssue("Preferences.setHotkeysEnabled not implemented")
    }
}
