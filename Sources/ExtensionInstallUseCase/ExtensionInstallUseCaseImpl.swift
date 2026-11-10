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

    public func updates() async -> AsyncStream<InstallStatus> {
        // The repository is asked before the relay starts, so its snapshot and registration happen in order.
        await repository.updates().distinct()
    }

    public func openApprovalSettings(_ pane: SystemSettingsPane) async -> Bool {
        await repository.openApprovalSettings(pane)
    }
}

extension AsyncStream where Element: Equatable & Sendable {
    /// Drops an element equal to the one before it; a repeat after another status is kept.
    /// The `previous` var lives only in the relay Task, which is cancelled when the consumer stops reading.
    fileprivate func distinct() -> AsyncStream<Element> {
        let (stream, continuation) = AsyncStream<Element>.makeStream()
        let relay = Task {
            var previous: Element?
            for await element in self {
                guard element != previous else { continue }
                previous = element
                continuation.yield(element)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in relay.cancel() }
        return stream
    }
}
