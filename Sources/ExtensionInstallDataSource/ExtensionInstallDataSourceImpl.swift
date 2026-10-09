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
    // Every caller of a pending request, keyed so a consumer that stops early can be dropped;
    // emptied (and finished) at the terminal status.
    private var subscribers: [Int: AsyncStream<InstallStatus>.Continuation] = [:]
    // Source of subscriber keys; bumped once per subscription.
    private var nextSubscriberID = 0
    // Identifies the newest activation request; bumped per submission so a superseded
    // request's late events cannot touch the one that replaced it.
    private var generation = 0

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
        subscribe(continuation)
        guard !isPending else {
            // Joined an in-flight request: replay where it stands, then forward the rest.
            continuation.yield(current)
            return stream
        }
        transition(to: .installing)
        generation += 1
        let mine = generation
        Task { await drive(generation: mine) }
        return stream
    }
}

extension ExtensionInstallDataSourceImpl {
    /// Number of callers still attached to the pending request.
    var subscriberCount: Int { subscribers.count }

    private var isPending: Bool { current == .installing || current == .needsApproval }

    /// Relays gateway events of one request until its stream ends. A stream that ends
    /// before a terminal status is a failure: the delegate would otherwise leave callers
    /// waiting forever. The loop keeps reading after a terminal event so a late callback
    /// of this request is consumed (and dropped) instead of leaking into a newer one.
    private func drive(generation mine: Int) async {
        for await event in gateway.activate(extensionBundleID: ProductIdentity.extensionBundleID) {
            guard mine == generation, !current.isTerminal else { continue }
            apply(event)
        }
        guard mine == generation, !current.isTerminal else { return }
        transition(to: .failed(.other(code: -1, description: "activation ended without a result")))
    }

    private func apply(_ event: SystemExtensionEvent) {
        switch event {
        case .willReplaceExisting:
            // Informational: the request stays in flight. Re-yield only while installing; after
            // needsApproval a fallback to .installing would hide the approval guidance.
            developerLog.record(.install, "replacing the installed extension build")
            guard current == .installing else { return }
            transition(to: .installing)
        case .needsApproval, .completed, .completesAfterReboot, .failed:
            transition(to: Self.status(for: event))
        }
    }

    /// A consumer that stops reading must not stay in the fan-out until the
    /// terminal status, so termination detaches it; the activation itself is unaffected.
    private func subscribe(_ continuation: AsyncStream<InstallStatus>.Continuation) {
        let id = nextSubscriberID
        nextSubscriberID += 1
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id) }
        }
    }

    private func unsubscribe(_ id: Int) {
        subscribers[id] = nil
    }

    private func transition(to next: InstallStatus) {
        current = next
        developerLog.record(.install, "extension install status: \(next)")
        for subscriber in subscribers.values { subscriber.yield(next) }
        guard next.isTerminal else { return }
        for subscriber in subscribers.values { subscriber.finish() }
        subscribers = [:]
    }

    static func status(for event: SystemExtensionEvent) -> InstallStatus {
        switch event {
        case .needsApproval: .needsApproval
        case .completed: .installed
        // Accepted, but not active until the next restart: terminal, yet not installed,
        // so the host does not start a pipeline against an extension that is not there.
        case .completesAfterReboot: .rebootRequired
        case .failed(let code, let description): .failed(failure(code: code, description: description))
        // Handled by the caller (it is not a status change); mapped here only to stay exhaustive.
        case .willReplaceExisting: .installing
        }
    }

    /// Classifies a raw `OSSystemExtensionError.Code` (kept as numbers so the gateway
    /// stays a pass-through): 10 forbiddenBySystemPolicy; 11 requestCanceled and
    /// 12 requestSuperseded; 2 missingEntitlement, 3 unsupportedParentBundleLocation,
    /// 4 extensionNotFound, 5 extensionMissingIdentifier, 8 unknownExtensionCategory and
    /// 9 codeSignatureInvalid describe a wrong build.
    static func failure(code: Int, description: String) -> InstallFailure {
        switch code {
        case 10: .denied
        case 11, 12: .canceled
        case 2, 3, 4, 5, 8, 9: .invalidBuild(code: code)
        default: .other(code: code, description: description)
        }
    }
}
