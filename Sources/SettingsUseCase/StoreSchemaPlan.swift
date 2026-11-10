import Domain

/// The schema version this build writes the stored values with.
let currentStoreSchemaVersion = 1

/// What `prepareStore()` does with the stored schema version.
enum StoreSchemaStep: Equatable {
    /// Nothing is stored, or an older build wrote the values: stamp the current version.
    case stamp
    /// A newer build wrote the values, they cannot be read, or they already match: touch nothing.
    case leaveAlone
}

/// The step for one stored schema version. Pure, so the policy is tested as a table. An older
/// layout that needs converting gets its conversion here, before the version is stamped.
func storeSchemaStep(for stored: StoredSchemaVersion, current: Int) -> StoreSchemaStep {
    switch stored {
    case .missing:
        .stamp
    case .version(let version) where version < current:
        .stamp
    case .version:
        .leaveAlone
    case .unreadable:
        .leaveAlone
    }
}
