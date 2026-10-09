import Dependencies

/// Failures at the Mach boundary; codes are raw `kern_return_t` /
/// `mach_msg_return_t` values, kept for the issue log rather than interpreted.
public enum MachError: Error, Sendable, Hashable {
    case bootstrapUnavailable(code: Int)
    case lookupFailed(code: Int)
    case checkInFailed(code: Int)
    case registerFailed(code: Int)
    case sendFailed(code: Int)
    /// `MACH_SEND_INVALID_DEST`: the receive right on the other side is gone.
    case destinationLost
    /// `MACH_SEND_TIMED_OUT`: the destination's queue is full. The link is
    /// fine; the frame is dropped.
    case queueFull
    case receiveFailed(code: Int)
    /// The receive right was destroyed while a receive was pending
    /// (`MACH_RCV_PORT_DIED`) — the normal way a receive loop ends.
    case portDied
    /// A message arrived that is not a frame, hello or dead-name notification
    /// (wrong id or shape).
    case malformedMessage
}

/// Thin pass-through to launchd's bootstrap server. Which registration route
/// the sandboxed extension may use is the M0 open question Q2; all three are
/// exposed so the data source can try them in order and log what the system
/// says.
public protocol MachBootstrapGateway: Sendable {
    /// Host side: `bootstrap_look_up` → a send right to the extension's port.
    func lookUp(serviceName: String) throws -> MachPortToken
    /// Extension side, launchd-known name: `bootstrap_check_in` → the receive right.
    func checkIn(serviceName: String) throws -> MachPortToken
    /// Extension side, dynamic name: allocate a receive right and
    /// `bootstrap_register` it.
    func register(serviceName: String) throws -> MachPortToken
    /// Releases a send right (`mach_port_deallocate`).
    func deallocate(_ port: MachPortToken)
    /// Gives up every user reference to a dead name (`mach_port_destroy`). A
    /// dead-name notification adds a reference of its own on top of the one the
    /// send right turned into, so a single `deallocate` would leave the name behind.
    func releaseDeadName(_ port: MachPortToken)
    /// Destroys a receive right; a receive blocked on it fails with `.portDied`.
    func destroyReceiveRight(_ port: MachPortToken)
    /// Host side: allocates a presence receive right and makes one send right on
    /// it (`mach_port_allocate` + `MAKE_SEND`). The send right is announced to the
    /// extension; destroying the receive right is how the extension learns the
    /// host is gone.
    func makePresencePort() throws -> PresencePort
    /// Extension side: asks for a `MACH_NOTIFY_DEAD_NAME` message on `notifyPort`
    /// (the service port) when the port behind `right` is destroyed
    /// (`mach_port_request_notification`). The notification arrives through
    /// `MachMessageGateway.receive` as `.deadName`.
    func requestDeadNameNotification(of right: MachSendRight, to notifyPort: MachPortToken) throws
}

/// Thin pass-through to `mach_msg` for the message shapes on the wire: the
/// frame, the host's hello and the kernel's dead-name notification.
public protocol MachMessageGateway: Sendable {
    /// Moves `message.surface` into the message (`MACH_MSG_TYPE_MOVE_SEND`): on
    /// success the kernel owns the right; on failure it is deallocated here.
    func send(_ message: FrameMessage, to port: MachPortToken) throws
    /// Moves `presence` (the host's presence send right) into a hello message
    /// (`MACH_MSG_TYPE_MOVE_SEND`, no payload) sent to `port`. Like `send`, it
    /// never blocks, and on failure the right is deallocated here.
    func announce(_ presence: MachSendRight, to port: MachPortToken) throws
    /// Suspends until one message arrives on `port`. Ends with `.portDied` when
    /// the receive right is destroyed, which is how the loop above is stopped.
    /// A message of any other shape is `.malformedMessage` and is destroyed.
    func receive(on port: MachPortToken) async throws -> IncomingMessage
}

public enum MachBootstrapGatewayKey: TestDependencyKey {
    public static let testValue: any MachBootstrapGateway = UnimplementedMachBootstrapGateway()
}

public enum MachMessageGatewayKey: TestDependencyKey {
    public static let testValue: any MachMessageGateway = UnimplementedMachMessageGateway()
}

extension DependencyValues {
    public var machBootstrapGateway: any MachBootstrapGateway {
        get { self[MachBootstrapGatewayKey.self] }
        set { self[MachBootstrapGatewayKey.self] = newValue }
    }

    public var machMessageGateway: any MachMessageGateway {
        get { self[MachMessageGatewayKey.self] }
        set { self[MachMessageGatewayKey.self] = newValue }
    }
}

private struct UnimplementedMachBootstrapGateway: MachBootstrapGateway {
    func lookUp(serviceName: String) throws -> MachPortToken {
        reportIssue("MachBootstrapGateway.lookUp not implemented")
        throw MachError.lookupFailed(code: -1)
    }

    func checkIn(serviceName: String) throws -> MachPortToken {
        reportIssue("MachBootstrapGateway.checkIn not implemented")
        throw MachError.checkInFailed(code: -1)
    }

    func register(serviceName: String) throws -> MachPortToken {
        reportIssue("MachBootstrapGateway.register not implemented")
        throw MachError.registerFailed(code: -1)
    }

    func makePresencePort() throws -> PresencePort {
        reportIssue("MachBootstrapGateway.makePresencePort not implemented")
        throw MachError.registerFailed(code: -1)
    }

    func requestDeadNameNotification(of right: MachSendRight, to notifyPort: MachPortToken) throws {
        reportIssue("MachBootstrapGateway.requestDeadNameNotification not implemented")
        throw MachError.registerFailed(code: -1)
    }

    func deallocate(_ port: MachPortToken) {
        reportIssue("MachBootstrapGateway.deallocate not implemented")
    }

    func releaseDeadName(_ port: MachPortToken) {
        reportIssue("MachBootstrapGateway.releaseDeadName not implemented")
    }

    func destroyReceiveRight(_ port: MachPortToken) {
        reportIssue("MachBootstrapGateway.destroyReceiveRight not implemented")
    }
}

private struct UnimplementedMachMessageGateway: MachMessageGateway {
    func send(_ message: FrameMessage, to port: MachPortToken) throws {
        reportIssue("MachMessageGateway.send not implemented")
        throw MachError.sendFailed(code: -1)
    }

    func announce(_ presence: MachSendRight, to port: MachPortToken) throws {
        reportIssue("MachMessageGateway.announce not implemented")
        throw MachError.sendFailed(code: -1)
    }

    func receive(on port: MachPortToken) async throws -> IncomingMessage {
        reportIssue("MachMessageGateway.receive not implemented")
        throw MachError.portDied
    }
}
