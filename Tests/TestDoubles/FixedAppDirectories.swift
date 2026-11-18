import Domain

/// `AppDirectoriesProvider` with the Application Support folder the test names, so no home directory or
/// environment variable is ever read. `effectsDirectory` and `diagnosticsDirectory` are the folders the two
/// DataSources keep under that base, for the suites that seed or read them; `EffectPackageDataSourceTests` and
/// `SupportLogDataSourceTests` pin that layout against paths they spell out.
public struct FixedAppDirectories: AppDirectoriesProvider, Sendable {
    public let applicationSupportDirectory: String

    public init(applicationSupportDirectory: String = "/support") {
        self.applicationSupportDirectory = applicationSupportDirectory
    }

    /// The effects folder `EffectPackageDataSourceImpl` lists under this base.
    public var effectsDirectory: String { "\(applicationSupportDirectory)/\(ProductIdentity.hostBundleID)/Effects" }

    /// The diagnostics folder `SupportLogDataSourceImpl` writes into under this base.
    public var diagnosticsDirectory: String { "\(applicationSupportDirectory)/\(ProductIdentity.hostBundleID)/Diagnostics" }
}
