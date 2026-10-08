import Domain
import TestSupport

public struct LogEntry: Equatable, Sendable {
    public let subsystem: LogSubsystem
    public let message: String

    public init(_ subsystem: LogSubsystem, _ message: String) {
        self.subsystem = subsystem
        self.message = message
    }
}

/// Records every log line; serves as both `ErrorLog` and `DeveloperLog` so a
/// test can check that a failure was reported without caring which sink.
public final class RecordingLog: ErrorLog, DeveloperLog, Sendable {
    public let entries = Collector<LogEntry>()

    public init() {}

    public func record(_ subsystem: LogSubsystem, _ message: String) {
        entries.append(LogEntry(subsystem, message))
    }

    public func messages(in subsystem: LogSubsystem) -> [String] {
        entries.values.filter { $0.subsystem == subsystem }.map(\.message)
    }

    public func contains(_ fragment: String) -> Bool {
        entries.contains { $0.message.contains(fragment) }
    }
}
