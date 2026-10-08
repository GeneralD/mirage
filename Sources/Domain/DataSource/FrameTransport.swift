import Dependencies

/// `FrameTransportDataSource`, host side: the connection state machine over
/// the Mach gateways. `connect` looks the service up with the retry policy
/// (clock-driven, cancellable); `send` is synchronous on the frame executor and
/// never blocks — a frame that cannot go is dropped with a reason.
public protocol FrameTransport: Sendable {
    /// Resolves the extension's service port, retrying per the policy until the
    /// task is cancelled or the policy is exhausted (then throws `MachError`).
    func connect() async throws
    func disconnect()
    var isConnected: Bool { get }
    func send(_ surface: any SurfaceHandle, descriptor: SurfaceDescriptor, presentationTime: HostTimestamp) -> SendOutcome
    /// Registers the single event listener (connected / disconnected / dropped).
    func observe(_ onEvent: @escaping @Sendable (FrameTransportEvent) -> Void)
}

public enum FrameTransportKey: TestDependencyKey {
    public static let testValue: any FrameTransport = UnimplementedFrameTransport()
}

extension DependencyValues {
    public var frameTransport: any FrameTransport {
        get { self[FrameTransportKey.self] }
        set { self[FrameTransportKey.self] = newValue }
    }
}

private struct UnimplementedFrameTransport: FrameTransport {
    func connect() async throws {
        reportIssue("FrameTransport.connect not implemented")
        throw MachError.lookupFailed(code: -1)
    }

    func disconnect() {
        reportIssue("FrameTransport.disconnect not implemented")
    }

    var isConnected: Bool {
        reportIssue("FrameTransport.isConnected not implemented")
        return false
    }

    func send(_ surface: any SurfaceHandle, descriptor: SurfaceDescriptor, presentationTime: HostTimestamp) -> SendOutcome {
        reportIssue("FrameTransport.send not implemented")
        return .dropped(.notConnected)
    }

    func observe(_ onEvent: @escaping @Sendable (FrameTransportEvent) -> Void) {
        reportIssue("FrameTransport.observe not implemented")
    }
}
