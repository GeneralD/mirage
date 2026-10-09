import Domain
import TestSupport

/// Bootstrap with scripted outcomes: each call pops the next result for its
/// operation; when the script is empty the default (success with a fresh port
/// name) applies. Every deallocate / destroy is recorded.
public final class FakeMachBootstrapGateway: MachBootstrapGateway, Sendable {
    private struct State {
        var lookUpScript: [Result<MachPortToken, MachError>] = []
        var checkInScript: [Result<MachPortToken, MachError>] = []
        var registerScript: [Result<MachPortToken, MachError>] = []
        var nextName: UInt32 = 0x2000
        var presenceScript: [Result<PresencePort, MachError>] = []
        var deadNameScript: [MachError] = []
    }

    private let state = Locked(State())
    public let lookUps = Collector<String>()
    public let checkIns = Collector<String>()
    public let registrations = Collector<String>()
    public let deallocated = Collector<MachPortToken>()
    public let destroyed = Collector<MachPortToken>()
    /// Every presence port handed out, in order.
    public let presencePorts = Collector<PresencePort>()
    /// Every dead-name notification request, in order (recorded even when it fails).
    public let deadNameRequests = Collector<(right: MachSendRight, port: MachPortToken)>()

    public init() {}

    public func scriptMakePresencePort(_ results: [Result<PresencePort, MachError>]) {
        state.withLock { $0.presenceScript = results }
    }

    /// Makes the next requests fail with these errors, in order; later ones succeed.
    public func scriptDeadNameRequests(failingWith errors: [MachError]) {
        state.withLock { $0.deadNameScript = errors }
    }

    public func makePresencePort() throws -> PresencePort {
        let presence = try state.withLock { state -> PresencePort in
            guard state.presenceScript.isEmpty else { return try state.presenceScript.removeFirst().get() }
            defer { state.nextName += 1 }
            return PresencePort(receive: MachPortToken(name: state.nextName), send: MachSendRight(name: state.nextName))
        }
        presencePorts.append(presence)
        return presence
    }

    public func requestDeadNameNotification(of right: MachSendRight, to notifyPort: MachPortToken) throws {
        deadNameRequests.append((right, notifyPort))
        try state.withLock { state in
            guard state.deadNameScript.isEmpty else { throw state.deadNameScript.removeFirst() }
        }
    }

    public func scriptLookUp(_ results: [Result<MachPortToken, MachError>]) {
        state.withLock { $0.lookUpScript = results }
    }

    public func scriptCheckIn(_ results: [Result<MachPortToken, MachError>]) {
        state.withLock { $0.checkInScript = results }
    }

    public func scriptRegister(_ results: [Result<MachPortToken, MachError>]) {
        state.withLock { $0.registerScript = results }
    }

    public func lookUp(serviceName: String) throws -> MachPortToken {
        lookUps.append(serviceName)
        return try next(\.lookUpScript)
    }

    public func checkIn(serviceName: String) throws -> MachPortToken {
        checkIns.append(serviceName)
        return try next(\.checkInScript)
    }

    public func register(serviceName: String) throws -> MachPortToken {
        registrations.append(serviceName)
        return try next(\.registerScript)
    }

    public func deallocate(_ port: MachPortToken) {
        deallocated.append(port)
    }

    public func destroyReceiveRight(_ port: MachPortToken) {
        destroyed.append(port)
    }

    private func next(_ script: WritableKeyPath<State, [Result<MachPortToken, MachError>]>) throws -> MachPortToken {
        try state.withLock { state in
            guard !state[keyPath: script].isEmpty else {
                defer { state.nextName += 1 }
                return MachPortToken(name: state.nextName)
            }
            return try state[keyPath: script].removeFirst().get()
        }
    }
}

/// Mach messaging the test drives from both ends: `send` records (or fails
/// with the scripted error) and `receive` suspends until `deliver` or
/// `failReceive` is called for that port. Deliveries made before a receive are
/// queued in order, like a port's message queue.
public final class FakeMachMessageGateway: MachMessageGateway, Sendable {
    private struct State {
        var queues: [UInt32: [Result<IncomingMessage, MachError>]] = [:]
        var waiters: [UInt32: [CheckedContinuation<IncomingMessage, any Error>]] = [:]
        var sendError: MachError?
        var announceError: MachError?
    }

    private let state = Locked(State())
    public let sent = Collector<(message: FrameMessage, port: MachPortToken)>()
    /// Every hello the subject announced, in order.
    public let announced = Collector<(right: MachSendRight, port: MachPortToken)>()
    public let receiveCalls = Collector<MachPortToken>()

    public init() {}

    public func failSend(with error: MachError?) {
        state.withLock { $0.sendError = error }
    }

    public func failAnnounce(with error: MachError?) {
        state.withLock { $0.announceError = error }
    }

    public func announce(_ presence: MachSendRight, to port: MachPortToken) throws {
        try state.withLock { state in
            if let error = state.announceError { throw error }
        }
        announced.append((presence, port))
    }

    public func send(_ message: FrameMessage, to port: MachPortToken) throws {
        try state.withLock { state in
            if let error = state.sendError { throw error }
        }
        sent.append((message, port))
    }

    public func receive(on port: MachPortToken) async throws -> IncomingMessage {
        receiveCalls.append(port)
        return try await withCheckedThrowingContinuation { continuation in
            state.withLock { state in
                guard state.queues[port.name, default: []].isEmpty else {
                    continuation.resume(with: state.queues[port.name, default: []].removeFirst())
                    return
                }
                state.waiters[port.name, default: []].append(continuation)
            }
        }
    }

    /// Hands a message to the receiver on `port` (resumes a pending receive, or
    /// queues it for the next one).
    public func deliver(_ message: FrameMessage, on port: MachPortToken) {
        deliver(.frame(message), on: port)
    }

    /// Hands any incoming message (a hello, a dead-name notification) to the receiver on `port`.
    public func deliver(_ incoming: IncomingMessage, on port: MachPortToken) {
        resolve(.success(incoming), on: port)
    }

    /// Makes the pending (or next) receive on `port` throw, e.g. `.portDied`.
    public func failReceive(with error: MachError, on port: MachPortToken) {
        resolve(.failure(error), on: port)
    }

    private func resolve(_ result: Result<IncomingMessage, MachError>, on port: MachPortToken) {
        let waiter = state.withLock { state -> CheckedContinuation<IncomingMessage, any Error>? in
            guard !state.waiters[port.name, default: []].isEmpty else {
                state.queues[port.name, default: []].append(result)
                return nil
            }
            return state.waiters[port.name, default: []].removeFirst()
        }
        waiter?.resume(with: result)
    }
}
