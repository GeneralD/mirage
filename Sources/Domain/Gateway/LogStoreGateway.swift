import Dependencies
import Foundation

/// Thin pass-through to the OS log store (live: `OSLogStore`, scoped to this process), reading
/// the lines this process wrote under one subsystem. It answers what the store still holds,
/// oldest first, and does not filter by level, sort or page: those are decided above it.
/// It throws when the store cannot be opened or read.
public protocol LogStoreGateway: Sendable {
    func entries(subsystem: String) throws -> [SupportLogEntry]
}

public enum LogStoreGatewayKey: TestDependencyKey {
    public static let testValue: any LogStoreGateway = UnimplementedLogStoreGateway()
}

extension DependencyValues {
    public var logStoreGateway: any LogStoreGateway {
        get { self[LogStoreGatewayKey.self] }
        set { self[LogStoreGatewayKey.self] = newValue }
    }
}

private struct UnimplementedLogStoreGateway: LogStoreGateway {
    func entries(subsystem: String) throws -> [SupportLogEntry] {
        reportIssue("LogStoreGateway.entries not implemented")
        throw CocoaError(.fileReadUnknown)
    }
}
