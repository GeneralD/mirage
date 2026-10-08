import Dependencies
import Domain

/// Install state machine over `SystemExtensionGateway`. Off the frame path and
/// low-rate, so it is an actor: the status and the subscriber list are mutated
/// only here, and a second `install()` while a request is pending joins it
/// instead of submitting a duplicate (the system would otherwise show two
/// approval prompts).
public actor ExtensionInstallDataSourceImpl {
    @Dependency(\.systemExtensionGateway) private var gateway
    @Dependency(\.developerLog) private var developerLog

    // Mutated on every transition; the actor is what makes that safe.
    private var current: InstallStatus = .notInstalled
    // Every caller of a pending request; emptied (and finished) at the terminal status.
    private var subscribers: [AsyncStream<InstallStatus>.Continuation] = []

    public init() {}
}

extension ExtensionInstallDataSourceImpl: CameraExtensionInstaller {
    public var status: InstallStatus { current }

    public func install() async -> AsyncStream<InstallStatus> {
        let (stream, continuation) = AsyncStream<InstallStatus>.makeStream()
        guard current != .installed else {
            continuation.yield(.installed)
            continuation.finish()
            return stream
        }
        subscribers.append(continuation)
        guard !isPending else {
            // Joined an in-flight request: replay where it stands, then forward the rest.
            continuation.yield(current)
            return stream
        }
        transition(to: .installing)
        Task { await drive() }
        return stream
    }
}

extension ExtensionInstallDataSourceImpl {
    private var isPending: Bool { current == .installing || current == .needsApproval }

    /// Relays gateway events until one is terminal. A stream that ends first
    /// is a failure: the delegate would otherwise leave callers waiting forever.
    private func drive() async {
        for await event in gateway.activate(extensionBundleID: ProductIdentity.extensionBundleID) {
            transition(to: Self.status(for: event))
            guard !current.isTerminal else { return }
        }
        transition(to: .failed(reason: "activation ended without a result"))
    }

    private func transition(to next: InstallStatus) {
        current = next
        developerLog.record(.install, "extension install status: \(next)")
        for subscriber in subscribers { subscriber.yield(next) }
        guard next.isTerminal else { return }
        for subscriber in subscribers { subscriber.finish() }
        subscribers = []
    }

    private static func status(for event: SystemExtensionEvent) -> InstallStatus {
        switch event {
        case .needsApproval: .needsApproval
        case .completed, .completesAfterReboot: .installed
        case .failed(let reason): .failed(reason: reason)
        }
    }
}
