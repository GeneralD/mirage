import Domain
import TestSupport

/// `SupportLogRepository` over a fixed snapshot. `save(_:)` records the report it was given before it
/// throws `saveFailure`, so a subject that saved is asserted to have saved even when the write fails.
public final class FakeSupportLogRepository: SupportLogRepository, Sendable {
    /// The reports `save(_:)` was called with, in call order.
    public let saved = Collector<String>()
    private let held: SupportLogSnapshot
    private let savedPath: String
    private let saveFailure: (any Error)?

    public init(
        snapshot: SupportLogSnapshot,
        savedPath: String = "/fake/support-log.txt",
        saveFailure: (any Error)? = nil
    ) {
        held = snapshot
        self.savedPath = savedPath
        self.saveFailure = saveFailure
    }

    public func snapshot() -> SupportLogSnapshot {
        held
    }

    public func save(_ report: String) throws -> String {
        saved.append(report)
        if let saveFailure { throw saveFailure }
        return savedPath
    }
}
