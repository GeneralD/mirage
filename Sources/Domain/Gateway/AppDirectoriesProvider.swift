import Dependencies

/// Where the OS keeps an app's files. The port answers the base directory only and knows no folder of the
/// app's own: the DataSource that keeps files joins the host bundle id and its folder's name below it
/// (`EffectPackageDataSourceImpl` the effects folder, `SupportLogDataSourceImpl` the diagnostics folder), as
/// path resolution lives in DataSources. The live value alone touches the OS's directory lookup; a test
/// hands its subject a fixed path, so no environment variable or home directory is ever read.
public protocol AppDirectoriesProvider: Sendable {
    /// The user's Application Support folder, `~/Library/Application Support`, as a plain absolute path
    /// with no trailing slash.
    var applicationSupportDirectory: String { get }
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
    var applicationSupportDirectory: String {
        reportIssue("AppDirectoriesProvider.applicationSupportDirectory not implemented")
        return ""
    }
}
