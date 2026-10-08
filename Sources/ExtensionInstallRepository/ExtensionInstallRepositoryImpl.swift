import Dependencies
import Domain

/// Pass-through to the installer data source. It exists to keep the layer
/// chain adjacent (UseCase → Repository → DataSource); caching or policy
/// would belong here, and M0 needs neither.
public struct ExtensionInstallRepositoryImpl: Sendable {
    @Dependency(\.cameraExtensionInstaller) private var installer

    public init() {}
}

extension ExtensionInstallRepositoryImpl: ExtensionInstallRepository {
    public var status: InstallStatus {
        get async { await installer.status }
    }

    public func install() async -> AsyncStream<InstallStatus> {
        await installer.install()
    }
}
