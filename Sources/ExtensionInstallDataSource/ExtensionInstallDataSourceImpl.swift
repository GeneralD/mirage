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
    @Dependency(\.workspaceGateway) private var workspace
    @Dependency(\.errorLog) private var errorLog

    // Mutated on every transition; the actor is what makes that safe.
    private var current: InstallStatus = .notInstalled
    // Every caller of a pending request, keyed so a consumer that stops early can be dropped;
    // emptied (and finished) at the terminal status.
    private var subscribers: [Int: AsyncStream<InstallStatus>.Continuation] = [:]
    // Source of subscriber keys; bumped once per subscription.
    private var nextSubscriberID = 0
    // Consumers of `updates()`: they see every transition, terminal ones included, and the
    // source never finishes them, so they stay attached across retried requests.
    private var watchers: [Int: AsyncStream<InstallStatus>.Continuation] = [:]
    // Source of watcher keys; bumped once per `updates()` call.
    private var nextWatcherID = 0
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

    public func updates() async -> AsyncStream<InstallStatus> {
        let (stream, continuation) = AsyncStream<InstallStatus>.makeStream()
        // No suspension between the snapshot and the registration, so no transition lands in between.
        continuation.yield(current)
        watch(continuation)
        return stream
    }

    public func openApprovalSettings(_ pane: SystemSettingsPane) async -> Bool {
        let opened = workspace.openURL(Self.settingsURL(for: pane))
        if opened {
            developerLog.record(.install, "opened System Settings: \(pane)")
        } else {
            errorLog.record(.install, "System Settings did not open: \(pane)")
        }
        return opened
    }
}

extension ExtensionInstallDataSourceImpl {
    /// Number of callers still attached to the pending request.
    var subscriberCount: Int { subscribers.count }

    /// Number of consumers attached through `updates()`.
    var watcherCount: Int { watchers.count }

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

    /// A watcher is not finished by the source, so a terminal status does not end it; like a
    /// subscriber, it is detached when its consumer terminates.
    private func watch(_ continuation: AsyncStream<InstallStatus>.Continuation) {
        let id = nextWatcherID
        nextWatcherID += 1
        watchers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unwatch(id) }
        }
    }

    private func unwatch(_ id: Int) {
        watchers[id] = nil
    }

    private func transition(to next: InstallStatus) {
        current = next
        developerLog.record(.install, "extension install status: \(next)")
        for subscriber in subscribers.values { subscriber.yield(next) }
        for watcher in watchers.values { watcher.yield(next) }
        guard next.isTerminal else { return }
        for subscriber in subscribers.values { subscriber.finish() }
        subscribers = [:]
    }

    /// The System Settings deep links. Apple documents neither, so the strings are kept in this one place.
    private static func settingsURL(for pane: SystemSettingsPane) -> String {
        switch pane {
        case .loginItemsAndExtensions: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        case .privacyAndSecurity: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
        }
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
    /// 4 extensionNotFound, 5 extensionMissingIdentifier, 6 duplicateExtensionIdentifier,
    /// 7 unknownExtensionCategory, 8 codeSignatureInvalid and 9 validationFailed describe
    /// a wrong build. 1 unknown and 13 authorizationRequired stay `other`.
    static func failure(code: Int, description: String) -> InstallFailure {
        switch code {
        case 10: .denied
        case 11, 12: .canceled
        case 2...9: .invalidBuild(code: code)
        default: .other(code: code, description: description)
        }
    }
}
