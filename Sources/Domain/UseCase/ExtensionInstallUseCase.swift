import Dependencies

/// Drives the Camera Extension activation to a terminal status, reporting each
/// transition (so the UI, later, can show "approve in System Settings").
public protocol ExtensionInstallUseCase: Sendable {
    var status: InstallStatus { get async }
    /// Runs the activation to a terminal status, reporting each transition.
    /// A stream that ends without a terminal status yields `.failed`.
    func install(onStatus: @escaping @Sendable (InstallStatus) -> Void) async -> InstallStatus
    /// Streams the current status first, then every later transition. Consecutive equal
    /// statuses are reported once. It does not end at a terminal status; it ends when its
    /// source ends.
    func updates() async -> AsyncStream<InstallStatus>
    /// Opens the System Settings pane for the extension approval. Returns `true` when the
    /// system accepted the request.
    func openApprovalSettings(_ pane: SystemSettingsPane) async -> Bool
}

public enum ExtensionInstallUseCaseKey: TestDependencyKey {
    public static let testValue: any ExtensionInstallUseCase = UnimplementedExtensionInstallUseCase()
}

extension DependencyValues {
    public var extensionInstallUseCase: any ExtensionInstallUseCase {
        get { self[ExtensionInstallUseCaseKey.self] }
        set { self[ExtensionInstallUseCaseKey.self] = newValue }
    }
}

private struct UnimplementedExtensionInstallUseCase: ExtensionInstallUseCase {
    var status: InstallStatus {
        get async {
            reportIssue("ExtensionInstallUseCase.status not implemented")
            return .notInstalled
        }
    }

    func install(onStatus: @escaping @Sendable (InstallStatus) -> Void) async -> InstallStatus {
        reportIssue("ExtensionInstallUseCase.install not implemented")
        return .failed(.other(code: -1, description: "unimplemented"))
    }

    func updates() async -> AsyncStream<InstallStatus> {
        reportIssue("ExtensionInstallUseCase.updates not implemented")
        return AsyncStream { $0.finish() }
    }

    func openApprovalSettings(_ pane: SystemSettingsPane) async -> Bool {
        reportIssue("ExtensionInstallUseCase.openApprovalSettings not implemented")
        return false
    }
}
