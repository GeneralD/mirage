import Domain
import TestSupport

/// `SupportLogs` over fixed values: `entries()` hands back what it was made with, or throws `entriesFailure`;
/// `save(_:)` records the report it was given and returns `savedPath`, or throws `saveFailure`. `saved` records
/// every report in call order, and a report is recorded before `saveFailure` is thrown, so a subject that saved
/// is asserted to have saved even when the write fails.
public final class FakeSupportLogs: SupportLogs, Sendable {
    /// The reports `save(_:)` was called with, in call order.
    public let saved = Collector<String>()
    private let held: [SupportLogEntry]
    private let entriesFailure: (any Error)?
    private let savedPath: String
    private let saveFailure: (any Error)?

    public init(
        entries: [SupportLogEntry] = [],
        entriesFailure: (any Error)? = nil,
        savedPath: String = "/fake/support-log.txt",
        saveFailure: (any Error)? = nil
    ) {
        held = entries
        self.entriesFailure = entriesFailure
        self.savedPath = savedPath
        self.saveFailure = saveFailure
    }

    public func entries() throws -> [SupportLogEntry] {
        if let entriesFailure { throw entriesFailure }
        return held
    }

    public func save(_ report: String) throws -> String {
        saved.append(report)
        if let saveFailure { throw saveFailure }
        return savedPath
    }
}
