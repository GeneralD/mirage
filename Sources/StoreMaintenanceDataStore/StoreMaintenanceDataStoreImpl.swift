import Dependencies
import Domain

/// What the stored values were written with, and the reset that removes them, over
/// `KeyValueStoreGateway` (epic E6, D6): the schema version as one string under one key, and the reset
/// as the gateway's `removeAll`. The only place that knows the key and the form of the version.
///
/// Reading never writes. A stored string that does not read as a version is not an error and is left
/// where it is (another build may have written it, and may read it again); one developer-log line says
/// it was ignored.
public struct StoreMaintenanceDataStoreImpl: Sendable {
    /// The defaults key the schema version lives under. Persisted, so never renamed.
    static let schemaVersionKey = "storeSchemaVersion"

    @Dependency(\.keyValueStoreGateway) private var keyValueStore
    @Dependency(\.developerLog) private var developerLog

    public init() {}
}

extension StoreMaintenanceDataStoreImpl: StoreMaintenance {
    public func schemaVersion() async -> StoredSchemaVersion {
        guard let stored = keyValueStore.string(forKey: Self.schemaVersionKey) else { return .missing }
        guard let version = Int(stored), version >= 1 else {
            developerLog.record(.app, "stored schema version does not decode, ignored: \(stored)")
            return .unreadable
        }
        return .version(version)
    }

    public func stampSchemaVersion(_ version: Int) async {
        keyValueStore.set(String(version), forKey: Self.schemaVersionKey)
    }

    public func resetAll() async {
        keyValueStore.removeAll()
        developerLog.record(.app, "store reset")
    }
}
