import Domain
import TestSupport

/// The kernel between the host and the extension, in-process. One bootstrap
/// table in which the extension's check-in and the host's look-up name the same
/// port, one message queue per port in which a `send` is the next `receive`,
/// and the presence protocol (presence ports, dead-name notifications).
///
/// It models the parts of Mach the frame path leans on:
/// - a queue holds at most `queueLimit` messages (`MACH_PORT_QLIMIT_DEFAULT` is 5);
///   a send beyond that fails with `.queueFull`, and a message handed straight
///   to a waiting receiver does not count against it;
/// - after the receive right is destroyed a send fails with `.destinationLost`,
///   a pending receive ends with `.portDied`, and the bootstrap name is gone;
/// - destroying a presence port's receive right delivers `.deadName` to the port
///   the extension registered with `requestDeadNameNotification`, whatever its queue holds.
///
/// `killHost()` is the `kill -9` model: the host's rights vanish with no host-side cleanup.
/// One kernel is shared by both processes; the surface pools stay per side in the rig.
public final class InMemoryFrameTransport: Sendable {
    /// Which process an adapter speaks for. Only the host makes presence ports.
    public enum Side: Sendable {
        case host
        case `extension`
    }

    private struct Port {
        var alive = true
        var queue: [IncomingMessage] = []
        var waiters: [CheckedContinuation<IncomingMessage, any Error>] = []
        /// Where the dead-name notification goes when this port dies.
        var notify: UInt32?
    }

    private struct State {
        var nextName: UInt32 = 0x2000
        var services: [String: UInt32] = [:]
        var ports: [UInt32: Port] = [:]
        var hostPresence: [UInt32] = []
        var lookUpFailures = 0
        var lookUpFailureCode = 1102
    }

    private let state = Locked(State())
    public let queueLimit: Int
    public let checkIns = Collector<String>()
    public let lookUps = Collector<String>()
    public let receiveCalls = Collector<MachPortToken>()
    public let deallocated = Collector<MachPortToken>()
    public let destroyed = Collector<MachPortToken>()
    /// Every `announce`, in order.
    public let announced = Collector<(right: MachSendRight, port: MachPortToken)>()
    /// Every presence port `makePresencePort` handed out.
    public let presencePorts = Collector<PresencePort>()
    /// Every `requestDeadNameNotification`, in order.
    public let deadNameRequests = Collector<(right: MachSendRight, port: MachPortToken)>()

    public init(queueLimit: Int = 5) {
        self.queueLimit = queueLimit
    }

    /// The most recently registered service port that is still alive.
    public var servicePort: MachPortToken? {
        state.withLock { state in
            state.services.values.sorted().last(where: { state.ports[$0]?.alive == true }).map { MachPortToken(name: $0) }
        }
    }

    /// The next `count` look-ups fail with `.lookupFailed(code:)` before the table is consulted.
    public func failNextLookUps(_ count: Int, code: Int = 1102) {
        state.withLock {
            $0.lookUpFailures = count
            $0.lookUpFailureCode = code
        }
    }

    public func bootstrap(for side: Side) -> any MachBootstrapGateway {
        Bootstrap(kernel: self, side: side)
    }

    public func messaging(for side: Side) -> any MachMessageGateway {
        Messaging(kernel: self)
    }

    /// The host dies: every receive right it holds is destroyed, nothing else happens on its side.
    public func killHost() {
        let held = state.withLock { state in
            defer { state.hostPresence = [] }
            return state.hostPresence
        }
        for name in held { destroy(name) }
    }

    // MARK: Kernel operations

    fileprivate func allocate(service: String? = nil, host: Bool = false) -> UInt32 {
        state.withLock { state in
            defer { state.nextName += 1 }
            state.ports[state.nextName] = Port()
            if let service { state.services[service] = state.nextName }
            if host { state.hostPresence.append(state.nextName) }
            return state.nextName
        }
    }

    fileprivate func lookUp(_ serviceName: String) throws -> MachPortToken {
        lookUps.append(serviceName)
        return try state.withLock { state in
            let failing = state.lookUpFailures > 0
            state.lookUpFailures = max(0, state.lookUpFailures - 1)
            try (!failing).orThrow(MachError.lookupFailed(code: state.lookUpFailureCode))
            let name = try state.services[serviceName].orThrow(MachError.lookupFailed(code: 1102))
            try (state.ports[name]?.alive == true).orThrow(MachError.lookupFailed(code: 1102))
            return MachPortToken(name: name)
        }
    }

    fileprivate func checkIn(_ serviceName: String) -> MachPortToken {
        checkIns.append(serviceName)
        return MachPortToken(name: allocate(service: serviceName))
    }

    /// Queues `message` on `port`, or hands it to a waiting receiver. A kernel-generated
    /// message (a notification) ignores the queue limit, as send-once notifications do.
    fileprivate func enqueue(_ message: IncomingMessage, on port: UInt32, kernelGenerated: Bool = false) throws {
        let waiter = try state.withLock { state -> CheckedContinuation<IncomingMessage, any Error>? in
            let entry = try state.ports[port].orThrow(MachError.destinationLost)
            try entry.alive.orThrow(MachError.destinationLost)
            guard entry.waiters.isEmpty else { return state.ports[port]?.waiters.removeFirst() }
            try (kernelGenerated || entry.queue.count < queueLimit).orThrow(MachError.queueFull)
            state.ports[port]?.queue.append(message)
            return nil
        }
        waiter?.resume(returning: message)
    }

    fileprivate func receive(on port: MachPortToken) async throws -> IncomingMessage {
        receiveCalls.append(port)
        return try await withCheckedThrowingContinuation { continuation in
            let outcome = state.withLock { state -> Result<IncomingMessage, MachError>? in
                guard let entry = state.ports[port.name], entry.alive else { return .failure(.portDied) }
                guard entry.queue.isEmpty else { return .success(state.ports[port.name]?.queue.removeFirst() ?? .deadName(port)) }
                state.ports[port.name]?.waiters.append(continuation)
                return nil
            }
            if let outcome { continuation.resume(with: outcome) }
        }
    }

    /// Destroys a receive right: the pending receive dies, the queue is dropped
    /// and a registered dead-name notification is delivered.
    fileprivate func destroy(_ name: UInt32) {
        let (waiters, notify) = state.withLock { state -> ([CheckedContinuation<IncomingMessage, any Error>], UInt32?) in
            guard let entry = state.ports[name], entry.alive else { return ([], nil) }
            state.ports[name] = Port(alive: false)
            return (entry.waiters, entry.notify)
        }
        for waiter in waiters { waiter.resume(throwing: MachError.portDied) }
        if let notify { try? enqueue(.deadName(MachPortToken(name: name)), on: notify, kernelGenerated: true) }
    }

    /// Known gap: the real `mach_port_request_notification` hands back the previous notification
    /// port for the caller to deallocate, and a repeated request replaces it. This double keeps one
    /// registration per port and returns no previous one, so a receiver that leaks a replaced
    /// notification right is not caught here; model it when the phase 2 receiver re-registers.
    fileprivate func registerNotification(for right: MachSendRight, on notifyPort: MachPortToken) throws {
        deadNameRequests.append((right, notifyPort))
        let alreadyDead = try state.withLock { state -> Bool in
            let entry = try state.ports[right.name].orThrow(MachError.registerFailed(code: 15))
            state.ports[right.name]?.notify = notifyPort.name
            return !entry.alive
        }
        if alreadyDead { try enqueue(.deadName(MachPortToken(name: right.name)), on: notifyPort.name, kernelGenerated: true) }
    }

    // MARK: Adapters

    private struct Bootstrap: MachBootstrapGateway {
        let kernel: InMemoryFrameTransport
        let side: Side

        func lookUp(serviceName: String) throws -> MachPortToken { try kernel.lookUp(serviceName) }
        func checkIn(serviceName: String) throws -> MachPortToken { kernel.checkIn(serviceName) }
        func register(serviceName: String) throws -> MachPortToken { kernel.checkIn(serviceName) }

        func deallocate(_ port: MachPortToken) {
            kernel.deallocated.append(port)
        }

        func destroyReceiveRight(_ port: MachPortToken) {
            kernel.destroyed.append(port)
            kernel.destroy(port.name)
        }

        func makePresencePort() throws -> PresencePort {
            let name = kernel.allocate(host: side == .host)
            let presence = PresencePort(receive: MachPortToken(name: name), send: MachSendRight(name: name))
            kernel.presencePorts.append(presence)
            return presence
        }

        func requestDeadNameNotification(of right: MachSendRight, to notifyPort: MachPortToken) throws {
            try kernel.registerNotification(for: right, on: notifyPort)
        }
    }

    private struct Messaging: MachMessageGateway {
        let kernel: InMemoryFrameTransport

        func send(_ message: FrameMessage, to port: MachPortToken) throws {
            try kernel.enqueue(.frame(message), on: port.name)
        }

        func announce(_ presence: MachSendRight, to port: MachPortToken) throws {
            try kernel.enqueue(.hello(presence), on: port.name)
            kernel.announced.append((presence, port))
        }

        func receive(on port: MachPortToken) async throws -> IncomingMessage {
            try await kernel.receive(on: port)
        }
    }
}
