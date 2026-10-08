import Dependencies
import Domain

/// Where host frames go to become the virtual camera: turns a pooled `FrameRef`
/// into the surface the transport sends. The pool keeps the lease; this layer
/// only resolves the token for the duration of one send.
public struct VirtualCameraRepositoryImpl: Sendable {
    @Dependency(\.frameTransport) private var transport
    @Dependency(\.surfacePool) private var pool
    @Dependency(\.errorLog) private var errorLog

    public init() {}
}

extension VirtualCameraRepositoryImpl: VirtualCameraSink {
    public func connect() async throws {
        try await transport.connect()
    }

    public func disconnect() {
        transport.disconnect()
    }

    public func observe(_ onEvent: @escaping @Sendable (FrameTransportEvent) -> Void) {
        transport.observe(onEvent)
    }

    /// A token that no longer resolves means the lease was already released (the
    /// frame is late): dropping it is correct, and logging says who held it.
    public func send(_ frame: FrameRef) -> SendOutcome {
        guard let surface = pool.handle(for: frame.token) else {
            errorLog.record(.transport, "frame dropped, token \(frame.token.index)/\(frame.token.generation) is stale")
            return .dropped(.staleToken)
        }
        return transport.send(surface, descriptor: frame.descriptor, presentationTime: frame.presentationTime)
    }
}
