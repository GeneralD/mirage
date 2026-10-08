import Dependencies

/// Install state for the UseCase layer; a pass-through over the installer
/// data source that keeps the adjacent-layer chain intact.
public protocol ExtensionInstallRepository: Sendable {
    var status: InstallStatus { get async }
    func install() async -> AsyncStream<InstallStatus>
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
}
