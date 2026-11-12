import Dependencies
import Foundation

/// `SupportLogDataSource`: the support report's raw material and where it is saved, behind one port.
/// It reads the lines this process wrote to the log (`LogStoreGateway`), keeps the newest of them in
/// time order, and writes a report into the diagnostics folder. What the report says and how the
/// lines are shown are decided above it.
public protocol SupportLogs: Sendable {
    /// The lines this process wrote under `ProductIdentity.logSubsystem`, oldest first, at most the
    /// newest 500. Lines with the same timestamp keep the order they were read in. `[]` when there
    /// are none. Throws what the log store throws.
    func entries() throws -> [SupportLogEntry]

    /// Writes `report` to `support-log.txt` in the diagnostics folder, replacing a file that is there
    /// already, opens the folder in Finder and returns the path written. Throws, and does not open
    /// Finder, when the folder cannot be made or the file cannot be written.
    func save(_ report: String) throws -> String
}

public enum SupportLogsKey: TestDependencyKey {
    public static let testValue: any SupportLogs = UnimplementedSupportLogs()
}

extension DependencyValues {
    public var supportLogs: any SupportLogs {
        get { self[SupportLogsKey.self] }
        set { self[SupportLogsKey.self] = newValue }
    }
}

private struct UnimplementedSupportLogs: SupportLogs {
    func entries() throws -> [SupportLogEntry] {
        reportIssue("SupportLogs.entries not implemented")
        return []
    }

    func save(_ report: String) throws -> String {
        reportIssue("SupportLogs.save not implemented")
        throw CocoaError(.fileWriteUnknown)
    }
}
