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
    /// Bumped by every `disconnect`, so a look-up still in flight at that moment
    /// cannot adopt the port it finds afterwards. Read once at the start of a
    /// `connect` from any context; the executor is its only writer.
    let generation = CurrentValueSubject<UInt64, Never>(0)
    /// The host's liveness beacon while connected (see `PresencePort`). Executor-confined.
    var presence: PresencePort?
    var onEvent: (@Sendable (FrameTransportEvent) -> Void)?

    public init(policy: RetryPolicy = .serviceLookup) {
        self.policy = policy
    }
}

extension FrameTransportDataSourceImpl: FrameTransport {
    public func connect() async throws {
        let epoch = generation.value
        let found = try await lookUp()
        // A connect cancelled, or disconnected, while its look-up was in flight must not
        // come alive afterwards; the port it found goes straight back.
        guard !Task.isCancelled, generation.value == epoch else {
            bootstrap.deallocate(found)
            throw CancellationError()
        }
        executor.run { [self] in adopt(found, epoch: epoch) }
    }

    public func disconnect() {
        executor.run { [self] in
            generation.value += 1
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

    /// Replaces any earlier port (a second `connect`) so no send right leaks. A
    /// result whose `connect` was overtaken by a `disconnect` on the executor is
    /// given back instead: the caller has already said it no longer wants a link.
    private func adopt(_ found: MachPortToken, epoch: UInt64) {
        guard epoch == generation.value else {
            bootstrap.deallocate(found)
            developerLog.record(.transport, "look-up result discarded: disconnected meanwhile")
            return
        }
        // The new hello goes out before the old presence port dies, so the extension never
        // sees the old host's dead name while this host is alive and already announced.
        let previous = (port: connection.value, presence: presence)
        presence = nil
        connection.value = found
        developerLog.record(.transport, "connected to port \(found.name)")
        announcePresence(to: found)
        giveBack(port: previous.port, presence: previous.presence)
        onEvent?(.connected)
    }

    /// Hands the extension a send right on a fresh presence port, so it learns of this
    /// process's death from a dead-name notification. Best effort: the frame-gap
    /// watchdog on the other side covers a link that has to go without.
    private func announcePresence(to port: MachPortToken) {
        let made: PresencePort
        do {
            made = try bootstrap.makePresencePort()
        } catch {
            errorLog.record(.transport, "no presence port could be made, continuing without: \(error)")
            return
        }
        do {
            // `MachMessageGateway.announce` contract: the moved send right is consumed on success
            // and deallocated by the gateway on failure, so only the receive right is left to destroy.
            try messaging.announce(made.send, to: port)
            presence = made
        } catch {
            bootstrap.destroyReceiveRight(made.receive)
            errorLog.record(.transport, "presence could not be announced, continuing without: \(error)")
        }
    }

    private func install(_ listener: @escaping @Sendable (FrameTransportEvent) -> Void) {
        onEvent = listener
    }

    /// Gives the send right back and forgets it, and destroys the presence receive
    /// right, which tells the extension this host is gone.
    func release() {
        let previous = (port: connection.value, presence: presence)
        connection.value = nil
        presence = nil
        giveBack(port: previous.port, presence: previous.presence)
    }

    private func giveBack(port: MachPortToken?, presence: PresencePort?) {
        _ = port.map(bootstrap.deallocate)
        _ = presence.map { bootstrap.destroyReceiveRight($0.receive) }
    }
}
