/// What the support report says about the state the user is looking at: the Camera Extension's install
/// status, the selected effect's status line and the compiler's output for that effect, when there is one.
/// Pure data; the report's wording is decided above it.
public struct SupportReportContext: Sendable, Hashable {
    public let install: InstallStatus
    public let effectStatus: String?
    public let compilerMessage: String?

    public init(install: InstallStatus, effectStatus: String? = nil, compilerMessage: String? = nil) {
        self.install = install
        self.effectStatus = effectStatus
        self.compilerMessage = compilerMessage
    }
}

/// How saving the support log ended: the file written with its line count and, when the system log could
/// not be read, why it could not; or the reason the file could not be written. Pure data.
public enum SupportLogExportOutcome: Sendable, Hashable {
    case saved(path: String, lineCount: Int, logError: String?)
    case failed(description: String)
}
