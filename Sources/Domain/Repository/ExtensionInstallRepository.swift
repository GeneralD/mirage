import Dependencies

/// Install state for the UseCase layer; a pass-through over the installer
/// data source that keeps the adjacent-layer chain intact.
public protocol ExtensionInstallRepository: Sendable {
    var status: InstallStatus { get async }
    func install() async -> AsyncStream<InstallStatus>
    /// Streams the current status first, then every later transition, terminal ones included.
    /// It never finishes on its own, and it submits no activation.
    func updates() async -> AsyncStream<InstallStatus>
    /// Opens the System Settings pane for the extension approval. Returns `true` when the system
    /// accepted the request. It leaves `status` alone and submits no activation.
    func openApprovalSettings(_ pane: SystemSettingsPane) async -> Bool
}

public enum ExtensionInstallRepositoryKey: TestDependencyKey {
    public static let testValue: any ExtensionInstallRepository = UnimplementedExtensionInstallRepository()
}

extension DependencyValues {
    public var extensionInstallRepository: any ExtensionInstallRepository {
        get { self[ExtensionInstallRepositoryKey.self] }
        set { self[ExtensionInstallRepositoryKey.self] = newValue }
    }
}

private struct UnimplementedExtensionInstallRepository: ExtensionInstallRepository {
    var status: InstallStatus {
        get async {
            reportIssue("ExtensionInstallRepository.status not implemented")
            return .notInstalled
        }
    }

    func install() async -> AsyncStream<InstallStatus> {
        reportIssue("ExtensionInstallRepository.install not implemented")
        return AsyncStream { $0.finish() }
    }

    func updates() async -> AsyncStream<InstallStatus> {
        reportIssue("ExtensionInstallRepository.updates not implemented")
        return AsyncStream { $0.finish() }
    }

    func openApprovalSettings(_ pane: SystemSettingsPane) async -> Bool {
        reportIssue("ExtensionInstallRepository.openApprovalSettings not implemented")
        return false
    }
}
