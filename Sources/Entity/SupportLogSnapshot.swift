/// What the support report is written from: the host's environment, the log lines this process wrote
/// (oldest first), and why those lines could not be read when they could not. Pure data; the report's
/// wording is decided above it.
public struct SupportLogSnapshot: Sendable, Hashable {
    public let environment: HostEnvironmentInfo
    public let entries: [SupportLogEntry]
    public let logError: String?

    public init(environment: HostEnvironmentInfo, entries: [SupportLogEntry], logError: String?) {
        self.environment = environment
        self.entries = entries
        self.logError = logError
    }
}
