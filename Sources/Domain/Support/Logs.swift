import Dependencies

/// Always-on operational errors (a dropped connection, a refused send). The
/// live value is `UnifiedLog`; tests record into `RecordingLog`.
public protocol ErrorLog: Sendable {
    func record(_ subsystem: LogSubsystem, _ message: String)
}

/// Developer tracing (state transitions, per-second frame stats). Same shape as
/// `ErrorLog` so a message can be routed to either without reformatting.
public protocol DeveloperLog: Sendable {
    func record(_ subsystem: LogSubsystem, _ message: String)
}

public enum ErrorLogKey: TestDependencyKey {
    /// Logging is a pure sink: discarding is the safe default in tests.
    public static let testValue: any ErrorLog = DiscardingLog()
}

public enum DeveloperLogKey: TestDependencyKey {
    public static let testValue: any DeveloperLog = DiscardingLog()
}

extension DependencyValues {
    public var errorLog: any ErrorLog {
        get { self[ErrorLogKey.self] }
        set { self[ErrorLogKey.self] = newValue }
    }

    public var developerLog: any DeveloperLog {
        get { self[DeveloperLogKey.self] }
        set { self[DeveloperLogKey.self] = newValue }
    }
}

private struct DiscardingLog: ErrorLog, DeveloperLog {
    func record(_ subsystem: LogSubsystem, _ message: String) {}
}
