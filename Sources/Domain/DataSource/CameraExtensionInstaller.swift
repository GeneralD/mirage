import Dependencies

/// `ExtensionInstallDataSource`: the install state machine over
/// `SystemExtensionGateway` (`notInstalled → installing → needsApproval → installed`,
/// or `rebootRequired` when the activation only takes effect after a restart).
/// Off the frame path and low-rate, so the live implementation is an actor
/// and the accessors are `async`.
public protocol CameraExtensionInstaller: Sendable {
    var status: InstallStatus { get async }
    /// Submits (or re-submits) the activation request and streams every
    /// transition until a terminal status. A second call while one is in
    /// flight joins the running request instead of submitting again.
    func install() async -> AsyncStream<InstallStatus>
    /// Streams the current status first, then every later transition, terminal ones included.
    /// It never finishes on its own: a retried `install()` reaches it again, and it is detached
    /// when the consumer stops reading. It submits no activation; only `install()` does.
    func updates() async -> AsyncStream<InstallStatus>
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
        get async {
            reportIssue("CameraExtensionInstaller.status not implemented")
            return .notInstalled
        }
    }

    func install() async -> AsyncStream<InstallStatus> {
        reportIssue("CameraExtensionInstaller.install not implemented")
        return AsyncStream { $0.finish() }
    }

    func updates() async -> AsyncStream<InstallStatus> {
        reportIssue("CameraExtensionInstaller.updates not implemented")
        return AsyncStream { $0.finish() }
    }
}
