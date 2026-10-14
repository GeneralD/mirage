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
}
