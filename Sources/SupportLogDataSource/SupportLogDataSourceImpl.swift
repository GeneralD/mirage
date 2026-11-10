import Dependencies
import Domain
import Foundation

/// The support log's DataSource (`SupportLogs`): the lines the log store holds for this process, in time
/// order and capped to the newest, and the report written to the diagnostics folder. The order, the cap
/// and the file name are persistence-shaped knowledge, so they live here; the gateways it calls stay thin
/// and are proven against their fakes.
public struct SupportLogDataSourceImpl: Sendable {
    @Dependency(\.logStoreGateway) private var logStore
    @Dependency(\.fileSystemGateway) private var fileSystem
    @Dependency(\.workspaceGateway) private var workspace
    @Dependency(\.appDirectories) private var appDirectories
    @Dependency(\.developerLog) private var developerLog

    public init() {}
}

/// The most lines `entries()` answers with: the newest ones, so a long-running process does not fill the report.
private let maximumEntries = 500

/// The file a report is written to inside the diagnostics folder. A fixed name, so a second save replaces the first.
private let reportFileName = "support-log.txt"

extension SupportLogDataSourceImpl: SupportLogs {
    public func entries() throws -> [SupportLogEntry] {
        let read = try logStore.entries(subsystem: ProductIdentity.logSubsystem)
        // The read position is the second key: lines with the same timestamp keep the order they were read in,
        // without relying on `sorted` being stable.
        let ordered = Array(read.enumerated())
            .sorted { ($0.element.timestamp, $0.offset) < ($1.element.timestamp, $1.offset) }
            .map(\.element)
        return Array(ordered.suffix(maximumEntries))
    }

    public func save(_ report: String) throws -> String {
        let directory = appDirectories.diagnosticsDirectory
        try fileSystem.createDirectory(directory)
        let path = URL(fileURLWithPath: directory, isDirectory: true).appending(path: reportFileName).path
        try fileSystem.writeString(report, to: path)
        workspace.open(directory)
        developerLog.record(.app, "support log saved")
        return path
    }
}
