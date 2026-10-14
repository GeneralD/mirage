import Domain

/// `AppDirectoriesProvider` with the effects folder the test names, so no home
/// directory or environment variable is ever read.
public struct FixedAppDirectories: AppDirectoriesProvider, Sendable {
    public let effectsDirectory: String

    public init(effectsDirectory: String) {
        self.effectsDirectory = effectsDirectory
    }
}
