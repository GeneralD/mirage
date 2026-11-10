import Domain
import TestSupport

/// `ExtensionInstallUseCase` the test drives, as the OnboardingInteractor suites see it. `publish(_:)` makes
/// a status the current one and sends it to every open `updates()` stream. `updates()` yields the current
/// status first and then every later one; its stream stays open until the consumer lets go, and
/// `updateRequests` and `updateTerminations` count the calls and the streams that ended. The current status
/// and the registration of a stream are one step under one lock, so a `publish` is seen either before the
/// first status of a new stream or after it, never lost and never doubled. `install(onStatus:)` is recorded
/// and answers the current status; `openApprovalSettings(_:)` is recorded and answers `opensSettings`.
public final class FakeExtensionInstallUseCase: ExtensionInstallUseCase, Sendable {
    private struct State {
        var latest: InstallStatus
        var continuations: [Int: AsyncStream<InstallStatus>.Continuation] = [:]
        var nextStream = 0
    }

    private let state: Locked<State>
    private let opensSettings: Bool
    /// One entry per `updates()` call.
    public let updateRequests = Collector<Void>()
    /// One entry per `updates()` stream that ended.
    public let updateTerminations = Collector<Void>()
    /// One entry per `install(onStatus:)` call.
    public let installs = Collector<Void>()
    /// The System Settings panes `openApprovalSettings(_:)` was asked to open, in order.
    public let openedPanes = Collector<SystemSettingsPane>()

    public init(status: InstallStatus = .notInstalled, opensSettings: Bool = true) {
        state = Locked(State(latest: status))
        self.opensSettings = opensSettings
    }

    public var status: InstallStatus {
        get async { state.withLock { $0.latest } }
    }

    /// Makes `status` the current one and sends it to every open `updates()` stream.
    public func publish(_ status: InstallStatus) {
        state.withLock { locked in
            locked.latest = status
            for continuation in locked.continuations.values { _ = continuation.yield(status) }
        }
    }

    public func install(onStatus: @escaping @Sendable (InstallStatus) -> Void) async -> InstallStatus {
        installs.append(())
        return state.withLock { $0.latest }
    }

    public func updates() async -> AsyncStream<InstallStatus> {
        updateRequests.append(())
        let (stream, continuation) = AsyncStream<InstallStatus>.makeStream()
        let id = state.withLock { locked -> Int in
            let id = locked.nextStream
            locked.nextStream += 1
            _ = continuation.yield(locked.latest)
            locked.continuations[id] = continuation
            return id
        }
        continuation.onTermination = { [weak self] _ in self?.end(id) }
        return stream
    }

    public func openApprovalSettings(_ pane: SystemSettingsPane) async -> Bool {
        openedPanes.append(pane)
        return opensSettings
    }

    private func end(_ id: Int) {
        state.withLock { _ = $0.continuations.removeValue(forKey: id) }
        updateTerminations.append(())
    }
}
