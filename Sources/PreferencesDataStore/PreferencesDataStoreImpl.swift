import Dependencies
import Domain
import Foundation

/// What the user chose, kept in the user's defaults through `KeyValueStoreGateway` (epic #42,
/// D6): the chosen effect as one string under one key (`StoredEffectID` is its form), and the
/// records of disabled effects as one JSON string under another. The first DataStore, and the
/// only place that knows the keys and the forms.
///
/// Reading never writes. A stored string that does not decode is not an error and is left
/// where it is (another build may have written it, and may read it again), so a relaunch
/// starts from the bundled default; one developer-log line says it was ignored.
public struct PreferencesDataStoreImpl: Sendable {
    /// The defaults key the chosen effect lives under. Persisted, so never renamed.
    static let selectedEffectKey = "selectedEffect"
    /// The defaults key the disabled-effect records live under. Persisted, so never renamed.
    static let disabledEffectsKey = "disabledEffects.v1"

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

    /// The whole array decodes or none of it does: a value where only some records are readable is
    /// dropped as a whole, and left where it is like any other value that does not decode.
    public func disabledEffects() async -> [DisabledEffectRecord] {
        guard let stored = keyValueStore.string(forKey: Self.disabledEffectsKey) else { return [] }
        guard let records = try? JSONDecoder().decode([DisabledEffectRecord].self, from: Data(stored.utf8)) else {
            developerLog.record(.effect, "stored disabled effects do not decode, ignored")
            return []
        }
        return records
    }

    /// Stored sorted by origin and key, so the order the caller gives does not change the stored
    /// form. A failed encode writes nothing, so the records already stored are not replaced.
    public func setDisabledEffects(_ records: [DisabledEffectRecord]) async {
        let ordered = records.sorted { ($0.id.origin.rawValue, $0.id.key) < ($1.id.origin.rawValue, $1.id.key) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(ordered) else {
            developerLog.record(.effect, "disabled effects do not encode, not stored")
            return
        }
        keyValueStore.set(String(decoding: data, as: UTF8.self), forKey: Self.disabledEffectsKey)
    }
}
