import Dependencies

/// Drives the Camera Extension activation to a terminal status, reporting each
/// transition (so the UI, later, can show "approve in System Settings").
public protocol ExtensionInstallUseCase: Sendable {
    var status: InstallStatus { get async }
    /// Runs the activation to a terminal status, reporting each transition.
    /// A stream that ends without a terminal status yields `.failed`.
    func install(onStatus: @escaping @Sendable (InstallStatus) -> Void) async -> InstallStatus
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
        return .failed(reason: "unimplemented")
    }
}
