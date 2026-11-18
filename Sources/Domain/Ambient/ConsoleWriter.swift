import Dependencies

/// The standard output and standard error of the command-line tool: the one exit for the results and
/// failures the user reads. The live value is `StandardStreamsImpl`; tests record into `RecordingConsole`.
/// Developer and operational logs go through `DeveloperLog` and `ErrorLog`, never through this port.
public protocol ConsoleWriter: Sendable {
    /// Writes `text` and one newline to standard output.
    func line(_ text: String)
    /// Writes `text` and one newline to standard error.
    func errorLine(_ text: String)
}

public enum ConsoleWriterKey: TestDependencyKey {
    /// Pure port: a test that prints nothing needs no override, so the unimplemented value only reports a
    /// call that a test did not expect.
    public static let testValue: any ConsoleWriter = UnimplementedConsoleWriter()
}

extension DependencyValues {
    public var consoleWriter: any ConsoleWriter {
        get { self[ConsoleWriterKey.self] }
        set { self[ConsoleWriterKey.self] = newValue }
    }
}

private struct UnimplementedConsoleWriter: ConsoleWriter {
    func line(_ text: String) {
        reportIssue("ConsoleWriter.line not implemented")
    }

    func errorLine(_ text: String) {
        reportIssue("ConsoleWriter.errorLine not implemented")
    }
}
