import Dependencies

/// `ExtensionInstallDataSource`: the install state machine over
/// `SystemExtensionGateway` (`notInstalled → installing → needsApproval → installed`).
public protocol CameraExtensionInstaller: Sendable {
    var status: InstallStatus { get }
    /// Submits (or re-submits) the activation request and streams every
    /// transition until a terminal status. A second call while one is in
    /// flight joins the running request instead of submitting again.
    func install() -> AsyncStream<InstallStatus>
}

public enum CameraExtensionInstallerKey: TestDependencyKey {
    public static let testValue: any CameraExtensionInstaller = UnimplementedCameraExtensionInstaller()
}

extension DependencyValues {
    public var cameraExtensionInstaller: any CameraExtensionInstaller {
        get { self[CameraExtensionInstallerKey.self] }
        set { self[CameraExtensionInstallerKey.self] = newValue }
    }
}

private struct UnimplementedCameraExtensionInstaller: CameraExtensionInstaller {
    var status: InstallStatus {
        reportIssue("CameraExtensionInstaller.status not implemented")
        return .notInstalled
    }

    func install() -> AsyncStream<InstallStatus> {
        reportIssue("CameraExtensionInstaller.install not implemented")
        return AsyncStream { $0.finish() }
    }
}
