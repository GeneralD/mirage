import Dependencies
import Domain

/// The chosen effect, kept in the user's defaults through `KeyValueStoreGateway` (epic #42,
/// D6): one string under one key (`StoredEffectID` is its form). The first DataStore, and the
/// only place that knows the key and the form.
///
/// Reading never writes. A stored string that does not decode is not an error and is left
/// where it is (another build may have written it, and may read it again), so a relaunch
/// starts from the bundled default; one developer-log line says it was ignored.
public struct PreferencesDataStoreImpl: Sendable {
    /// The defaults key the chosen effect lives under. Persisted, so never renamed.
    static let selectedEffectKey = "selectedEffect"

    @Dependency(\.keyValueStoreGateway) private var keyValueStore
    @Dependency(\.developerLog) private var developerLog

    public init() {}
}

extension PreferencesDataStoreImpl: Preferences {
    public func selectedEffect() async -> EffectID? {
        guard let stored = keyValueStore.string(forKey: Self.selectedEffectKey) else { return nil }
        guard let id = StoredEffectID.decode(stored) else {
            developerLog.record(.effect, "stored effect selection does not decode, ignored: \(stored)")
            return nil
        }
        return id
    }

    public func setSelectedEffect(_ id: EffectID) async {
        keyValueStore.set(StoredEffectID.encode(id), forKey: Self.selectedEffectKey)
    }
}
