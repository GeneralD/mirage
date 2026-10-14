import Dependencies

/// Where the app keeps its files. The only module that resolves these paths is the
/// live one (it alone touches `FileManager`); everything else asks this port, so a
/// test hands its subject a fixed path and no environment variable or home directory
/// is ever read.
public protocol AppDirectoriesProvider: Sendable {
    /// The folder `.lens` packages are dropped into: `~/Library/Application Support/<host
    /// bundle id>/Effects` (epic #42, D2). It need not exist yet; the first listing creates it.
    var effectsDirectory: String { get }
}

public enum AppDirectoriesProviderKey: TestDependencyKey {
    public static let testValue: any AppDirectoriesProvider = UnimplementedAppDirectoriesProvider()
}

extension DependencyValues {
    public var appDirectories: any AppDirectoriesProvider {
        get { self[AppDirectoriesProviderKey.self] }
        set { self[AppDirectoriesProviderKey.self] = newValue }
    }
}

private struct UnimplementedAppDirectoriesProvider: AppDirectoriesProvider {
    var effectsDirectory: String {
        reportIssue("AppDirectoriesProvider.effectsDirectory not implemented")
        return ""
    }
}
