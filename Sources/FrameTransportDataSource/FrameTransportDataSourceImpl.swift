import Combine
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

    // Executor-confined: every mutation runs on FrameExecutor. The port lives in
    // a subject so `isConnected` reads a whole value from any context (the
    // subject synchronizes its `value`); the executor is its only writer.
    let connection = CurrentValueSubject<MachPortToken?, Never>(nil)
    var onEvent: (@Sendable (FrameTransportEvent) -> Void)?

    public init(policy: RetryPolicy = .serviceLookup) {
        self.policy = policy
    }
}

extension FrameTransportDataSourceImpl: FrameTransport {
    public func connect() async throws {
        let found = try await lookUp()
        // A connect cancelled while its look-up was in flight must not come alive afterwards.
        guard !Task.isCancelled else {
            bootstrap.deallocate(found)
            throw CancellationError()
        }
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
    public var isConnected: Bool { connection.value != nil }

    public func observe(_ onEvent: @escaping @Sendable (FrameTransportEvent) -> Void) {
        executor.run { [self] in install(onEvent) }
    }
}

extension FrameTransportDataSourceImpl {
    /// Looks the service up, backing off per the policy. A loop rather than recursion,
    /// so an extension that stays away for hours costs one suspended sleep at a time
    /// instead of a growing chain of async frames.
    private func lookUp() async throws -> MachPortToken {
        // The attempt counter is the loop's only state; it exists to feed the policy.
        var attempt = 1
        while true {
            do {
                return try bootstrap.lookUp(serviceName: ProductIdentity.machServiceName)
            } catch let error as MachError {
                developerLog.record(.transport, "look-up attempt \(attempt) failed: \(error)")
                guard let delay = policy.delay(afterFailure: attempt) else { throw giveUp(after: attempt, error) }
                try await clock.sleep(for: delay)
                attempt += 1
            }
        }
    }

    /// Retries are exhausted: tell the observer as well as the caller, since the
    /// observer is the one that outlives this `connect` call.
    private func giveUp(after attempts: Int, _ error: MachError) -> MachError {
        errorLog.record(.transport, "look-up gave up after \(attempts) attempts: \(error)")
        executor.run { [self] in onEvent?(.disconnected(.lookupFailed(code: error.code))) }
        return error
    }

    /// Replaces any earlier port (a second `connect`) so no send right leaks.
    private func adopt(_ found: MachPortToken) {
        release()
        connection.value = found
        developerLog.record(.transport, "connected to port \(found.name)")
        onEvent?(.connected)
    }

    private func install(_ listener: @escaping @Sendable (FrameTransportEvent) -> Void) {
        onEvent = listener
    }

    /// Gives the send right back and forgets it.
    func release() {
        _ = connection.value.map(bootstrap.deallocate)
        connection.value = nil
    }
}
