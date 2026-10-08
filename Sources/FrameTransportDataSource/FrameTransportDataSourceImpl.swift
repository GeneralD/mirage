import Dependencies
import Domain

/// Host side of the frame wire: finds the extension's Mach service (retrying while
/// the extension process does not exist yet) and sends one message per frame.
///
/// Every decision about the connection lives here, one layer above the thin Mach
/// gateways, so it is covered by tests against fakes: retry pacing, what a lost
/// destination means, and which failures drop a frame rather than end the link.
public final class FrameTransportDataSourceImpl: @unchecked Sendable {
    @Dependency(\.machBootstrapGateway) var bootstrap
    @Dependency(\.machMessageGateway) var messaging
    @Dependency(\.ioSurfaceGateway) var surfaces
    @Dependency(\.frameExecutor) var executor
    @Dependency(\.continuousClock) var clock
    @Dependency(\.errorLog) var errorLog
    @Dependency(\.developerLog) var developerLog

    let policy: RetryPolicy

    // Executor-confined: every mutation runs on FrameExecutor.
    var port: MachPortToken?
    var onEvent: (@Sendable (FrameTransportEvent) -> Void)?

    public init(policy: RetryPolicy = .serviceLookup) {
        self.policy = policy
    }
}

extension FrameTransportDataSourceImpl: FrameTransport {
    public func connect() async throws {
        let found = try await lookUp(attempt: 1)
        executor.run { [self] in adopt(found) }
    }

    public func disconnect() {
        executor.run { [self] in
            release()
            developerLog.record(.transport, "disconnected on request")
            onEvent?(.disconnected(.explicit))
        }
    }

    /// A snapshot read from any context; the frame path itself never relies on it.
    public var isConnected: Bool { port != nil }

    public func observe(_ onEvent: @escaping @Sendable (FrameTransportEvent) -> Void) {
        executor.run { [self] in install(onEvent) }
    }
}

extension FrameTransportDataSourceImpl {
    /// Looks the service up, backing off per the policy. Recursion keeps the attempt
    /// counter immutable; each level is one suspended sleep, so depth is bounded by
    /// how long the extension stays away, not by CPU.
    private func lookUp(attempt: Int) async throws -> MachPortToken {
        do {
            return try bootstrap.lookUp(serviceName: ProductIdentity.machServiceName)
        } catch let error as MachError {
            developerLog.record(.transport, "look-up attempt \(attempt) failed: \(error)")
            guard let delay = policy.delay(afterFailure: attempt) else {
                errorLog.record(.transport, "look-up gave up after \(attempt) attempts: \(error)")
                throw error
            }
            try await clock.sleep(for: delay)
            return try await lookUp(attempt: attempt + 1)
        }
    }

    /// Replaces any earlier port (a second `connect`) so no send right leaks.
    private func adopt(_ found: MachPortToken) {
        release()
        port = found
        developerLog.record(.transport, "connected to port \(found.name)")
        onEvent?(.connected)
    }

    private func install(_ listener: @escaping @Sendable (FrameTransportEvent) -> Void) {
        onEvent = listener
    }

    /// Gives the send right back and forgets it.
    func release() {
        _ = port.map(bootstrap.deallocate)
        port = nil
    }
}
