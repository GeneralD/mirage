import Dependencies
import Domain

/// Camera frames as pooled `FrameRef`s plus the permission state. A frame the
/// pool cannot lease (capacity reached) is dropped on the spot and reported:
/// queueing it would only add latency to a stream where the latest frame wins.
public struct CameraRepositoryImpl: Sendable {
    @Dependency(\.cameraSource) private var cameraSource
    @Dependency(\.cameraPermission) private var cameraPermission
    @Dependency(\.surfacePool) private var surfacePool
    @Dependency(\.errorLog) private var errorLog

    public init() {}
}

extension CameraRepositoryImpl: CameraRepository {
    public func authorizationStatus() -> CameraAuthorizationStatus {
        cameraPermission.status()
    }

    public func requestAuthorization() async -> CameraAuthorizationStatus {
        await cameraPermission.request()
    }

    public func start(
        descriptor: SurfaceDescriptor,
        onFrame: @escaping @Sendable (FrameRef) -> Void,
        onEnd: @escaping @Sendable (CaptureEnd) -> Void
    ) throws {
        try cameraSource.start(
            descriptor: descriptor,
            onFrame: { incoming in lease(incoming).map(onFrame) },
            onEnd: onEnd
        )
    }

    public func stop() {
        cameraSource.stop()
    }
}

extension CameraRepositoryImpl {
    /// Adopts the surface into the pool; `nil` (and a log line) when the pool is full.
    private func lease(_ incoming: IncomingSurface) -> FrameRef? {
        guard let token = surfacePool.adopt(incoming.handle, descriptor: incoming.descriptor) else {
            errorLog.record(.camera, "camera frame dropped: pool exhausted (capacity \(surfacePool.capacity))")
            return nil
        }
        return FrameRef(token: token, descriptor: incoming.descriptor, presentationTime: incoming.presentationTime)
    }
}
