import Dependencies
import Foundation

/// `SupportLogRepository`: the support report's material as one value, over `SupportLogs` (the log lines
/// and the report file) and `HostEnvironmentProvider` (the versions). An unreadable log does not stop the
/// report: `snapshot()` never throws, and says why the lines are missing instead.
public protocol SupportLogRepository: Sendable {
    /// Never throws. When the log cannot be read, `entries` is empty and `logError` holds the reason.
    func snapshot() -> SupportLogSnapshot

    /// Writes `report` as the support log file and returns the path written. Throws what `SupportLogs.save` throws.
    func save(_ report: String) throws -> String
}

public enum SupportLogRepositoryKey: TestDependencyKey {
    public static let testValue: any SupportLogRepository = UnimplementedSupportLogRepository()
}

extension DependencyValues {
    public var supportLogRepository: any SupportLogRepository {
        get { self[SupportLogRepositoryKey.self] }
        set { self[SupportLogRepositoryKey.self] = newValue }
    }
}

private struct UnimplementedSupportLogRepository: SupportLogRepository {
    func snapshot() -> SupportLogSnapshot {
        reportIssue("SupportLogRepository.snapshot not implemented")
        let environment = HostEnvironmentInfo(appVersion: nil, buildNumber: nil, systemVersion: SystemVersion(major: 0, minor: 0, patch: 0))
        return SupportLogSnapshot(environment: environment, entries: [], logError: "unimplemented")
    }

    func save(_ report: String) throws -> String {
        reportIssue("SupportLogRepository.save not implemented")
        throw CocoaError(.fileWriteUnknown)
    }
}
