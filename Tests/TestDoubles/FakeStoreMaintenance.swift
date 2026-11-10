import Domain
import TestSupport

/// `StoreMaintenance` holding the schema version in memory: `schemaVersion()` answers what it was made
/// with or last stamped, or `.missing` after a reset. `stamps` records every `stampSchemaVersion` version
/// in call order, and `resets` one entry per `resetAll()`, so a subject that must not reset is asserted
/// to have reset nothing.
public final class FakeStoreMaintenance: StoreMaintenance, Sendable {
    private let held: Locked<StoredSchemaVersion>
    /// The versions `stampSchemaVersion` was called with, in call order.
    public let stamps = Collector<Int>()
    /// One entry per `resetAll()` call, in call order.
    public let resets = Collector<Void>()

    public init(version: StoredSchemaVersion = .missing) {
        held = Locked(version)
    }

    public func schemaVersion() async -> StoredSchemaVersion {
        held.current
    }

    public func stampSchemaVersion(_ version: Int) async {
        held.set(.version(version))
        stamps.append(version)
    }

    public func resetAll() async {
        held.set(.missing)
        resets.append(())
    }
}
