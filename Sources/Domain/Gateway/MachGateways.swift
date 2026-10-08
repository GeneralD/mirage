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
    case receiveFailed(code: Int)
    /// The receive right was destroyed while a receive was pending
    /// (`MACH_RCV_PORT_DIED`) — the normal way a receive loop ends.
    case portDied
    /// A message arrived that is not a `FrameMessage` (wrong id or shape).
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
    /// Destroys a receive right; a receive blocked on it fails with `.portDied`.
    func destroyReceiveRight(_ port: MachPortToken)
}

/// Thin pass-through to `mach_msg` for the one message shape on the wire.
public protocol MachMessageGateway: Sendable {
    /// Moves `message.surface` into the message (`MACH_MSG_TYPE_MOVE_SEND`): on
    /// success the kernel owns the right; on failure it is deallocated here.
    func send(_ message: FrameMessage, to port: MachPortToken) throws
    /// Suspends until one message arrives on `port`. Ends with `.portDied` when
    /// the receive right is destroyed, which is how the loop above is stopped.
    func receive(on port: MachPortToken) async throws -> FrameMessage
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

    func deallocate(_ port: MachPortToken) {
        reportIssue("MachBootstrapGateway.deallocate not implemented")
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

    func receive(on port: MachPortToken) async throws -> FrameMessage {
        reportIssue("MachMessageGateway.receive not implemented")
        throw MachError.portDied
    }
}
