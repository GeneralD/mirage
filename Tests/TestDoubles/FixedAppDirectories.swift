import Domain

/// `AppDirectoriesProvider` with the effects and diagnostics folders the test names, so no home
/// directory or environment variable is ever read.
public struct FixedAppDirectories: AppDirectoriesProvider, Sendable {
    public let effectsDirectory: String
    public let diagnosticsDirectory: String

    public init(effectsDirectory: String, diagnosticsDirectory: String = "/diagnostics") {
        self.effectsDirectory = effectsDirectory
        self.diagnosticsDirectory = diagnosticsDirectory
    }
}
