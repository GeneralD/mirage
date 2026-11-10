import Dependencies
import Domain
import Foundation

/// The support log's Repository: bundles the host environment (`HostEnvironmentProvider`) and the log lines
/// and report file (`SupportLogs`) into one `SupportLogSnapshot`. It does not let an unreadable log stop the
/// report: a failed read becomes empty `entries` with the reason in `logError`. Caching and retries are not
/// needed here, so none are made.
public struct SupportLogRepositoryImpl: Sendable {
    @Dependency(\.supportLogs) private var logs
    @Dependency(\.hostEnvironment) private var hostEnvironment

    public init() {}
}

extension SupportLogRepositoryImpl: SupportLogRepository {
    public func snapshot() -> SupportLogSnapshot {
        let environment = hostEnvironment.info
        switch Result(catching: { try logs.entries() }) {
        case .success(let entries):
            return SupportLogSnapshot(environment: environment, entries: entries, logError: nil)
        case .failure(let error):
            return SupportLogSnapshot(environment: environment, entries: [], logError: error.localizedDescription)
        }
    }

    public func save(_ report: String) throws -> String {
        try logs.save(report)
    }
}
