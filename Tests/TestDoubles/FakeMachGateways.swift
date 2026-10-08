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
    }

    private let state = Locked(State())
    public let lookUps = Collector<String>()
    public let checkIns = Collector<String>()
    public let registrations = Collector<String>()
    public let deallocated = Collector<MachPortToken>()
    public let destroyed = Collector<MachPortToken>()

    public init() {}

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
        var queues: [UInt32: [Result<FrameMessage, MachError>]] = [:]
        var waiters: [UInt32: [CheckedContinuation<FrameMessage, any Error>]] = [:]
        var sendError: MachError?
    }

    private let state = Locked(State())
    public let sent = Collector<(message: FrameMessage, port: MachPortToken)>()
    public let receiveCalls = Collector<MachPortToken>()

    public init() {}

    public func failSend(with error: MachError?) {
        state.withLock { $0.sendError = error }
    }

    public func send(_ message: FrameMessage, to port: MachPortToken) throws {
        try state.withLock { state in
            if let error = state.sendError { throw error }
        }
        sent.append((message, port))
    }

    public func receive(on port: MachPortToken) async throws -> FrameMessage {
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
        resolve(.success(message), on: port)
    }

    /// Makes the pending (or next) receive on `port` throw, e.g. `.portDied`.
    public func failReceive(with error: MachError, on port: MachPortToken) {
        resolve(.failure(error), on: port)
    }

    private func resolve(_ result: Result<FrameMessage, MachError>, on port: MachPortToken) {
        let waiter = state.withLock { state -> CheckedContinuation<FrameMessage, any Error>? in
            guard !state.waiters[port.name, default: []].isEmpty else {
                state.queues[port.name, default: []].append(result)
                return nil
            }
            return state.waiters[port.name, default: []].removeFirst()
        }
        waiter?.resume(with: result)
    }
}
