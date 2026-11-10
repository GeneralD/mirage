import Dependencies

/// `StoreMaintenance`: the schema version the stored values were written with, and the reset that
/// removes every value the app has stored. The DataStore holds the key and the form; the layers above
/// see only these three calls.
public protocol StoreMaintenance: Sendable {
    /// What the stored schema version says: `.missing` when nothing was ever stamped, `.unreadable`
    /// when a value is stored but does not read as a version of 1 or more. Reading never writes, so an
    /// unreadable value is left where it is.
    func schemaVersion() async -> StoredSchemaVersion

    /// Stores `version` as the schema version the stored values are written with.
    func stampSchemaVersion(_ version: Int) async

    /// Removes every value the app has stored, the schema version included, and nothing else.
    func resetAll() async
}

public enum StoreMaintenanceKey: TestDependencyKey {
    public static let testValue: any StoreMaintenance = UnimplementedStoreMaintenance()
}

extension DependencyValues {
    public var storeMaintenance: any StoreMaintenance {
        get { self[StoreMaintenanceKey.self] }
        set { self[StoreMaintenanceKey.self] = newValue }
    }
}

private struct UnimplementedStoreMaintenance: StoreMaintenance {
    func schemaVersion() async -> StoredSchemaVersion {
        reportIssue("StoreMaintenance.schemaVersion not implemented")
        return .unreadable
    }

    func stampSchemaVersion(_ version: Int) async {
        reportIssue("StoreMaintenance.stampSchemaVersion not implemented")
    }

    func resetAll() async {
        reportIssue("StoreMaintenance.resetAll not implemented")
    }
}
