import Dependencies
import Domain

/// Runs the activation to a terminal status. The data source finishes its
/// stream after the terminal status, so the last status seen is the outcome;
/// a stream that is empty or stops on a non-terminal status is reported as a
/// failure rather than as a stale "installing".
public struct ExtensionInstallUseCaseImpl: Sendable {
    @Dependency(\.extensionInstallRepository) private var repository

    public init() {}
}

extension ExtensionInstallUseCaseImpl: ExtensionInstallUseCase {
    public var status: InstallStatus {
        get async { await repository.status }
    }

    public func install(onStatus: @escaping @Sendable (InstallStatus) -> Void) async -> InstallStatus {
        let last = await repository.install().reduce(into: InstallStatus?.none) { last, status in
            onStatus(status)
            last = status
        }
        return last.flatMap { $0.isTerminal ? $0 : nil } ?? .failed(.other(code: -1, description: "no terminal status"))
    }
}
