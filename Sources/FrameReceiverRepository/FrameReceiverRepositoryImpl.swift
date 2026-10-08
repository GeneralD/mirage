import Dependencies
import Domain

/// Adopts every surface the receiver resolves into the extension's own pool, so
/// the layers above hold a process-local `SurfaceToken` instead of an OS handle.
public struct FrameReceiverRepositoryImpl: Sendable {
    @Dependency(\.frameReceiver) private var frameReceiver
    @Dependency(\.surfacePool) private var surfacePool
    @Dependency(\.errorLog) private var errorLog

    public init() {}
}

extension FrameReceiverRepositoryImpl: FrameReceiverRepository {
    public func start(
        onFrame: @escaping @Sendable (FrameRef) -> Void,
        onEvent: @escaping @Sendable (ReceiverEvent) -> Void
    ) async throws {
        try await frameReceiver.start(
            onFrame: { [surfacePool, errorLog] incoming in
                // A full pool means the consumer is slower than the host; the
                // latest frame wins, so the surplus one is dropped, not queued.
                guard let token = surfacePool.adopt(incoming.handle, descriptor: incoming.descriptor) else {
                    errorLog.record(.receiver, "frame dropped: surface pool exhausted (\(surfacePool.liveCount)/\(surfacePool.capacity))")
                    return
                }
                onFrame(FrameRef(token: token, descriptor: incoming.descriptor, presentationTime: incoming.presentationTime))
            },
            onEvent: onEvent
        )
    }

    public func stop() {
        frameReceiver.stop()
    }
}
