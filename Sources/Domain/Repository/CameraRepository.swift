import Dependencies

/// Camera frames as leased `FrameRef`s plus the permission state. Adopts each
/// incoming surface into the surface pool; a frame that cannot get a lease
/// (pool at capacity) is dropped and counted, never queued.
public protocol CameraRepository: Sendable {
    func authorizationStatus() -> CameraAuthorizationStatus
    func requestAuthorization() async -> CameraAuthorizationStatus
    func start(
        descriptor: SurfaceDescriptor,
        onFrame: @escaping @Sendable (FrameRef) -> Void,
        onEnd: @escaping @Sendable (CaptureEnd) -> Void
    ) throws
    func stop()
}

public enum CameraRepositoryKey: TestDependencyKey {
    public static let testValue: any CameraRepository = UnimplementedCameraRepository()
}

extension DependencyValues {
    public var cameraRepository: any CameraRepository {
        get { self[CameraRepositoryKey.self] }
        set { self[CameraRepositoryKey.self] = newValue }
    }
}

private struct UnimplementedCameraRepository: CameraRepository {
    func authorizationStatus() -> CameraAuthorizationStatus {
        reportIssue("CameraRepository.authorizationStatus not implemented")
        return .denied
    }

    func requestAuthorization() async -> CameraAuthorizationStatus {
        reportIssue("CameraRepository.requestAuthorization not implemented")
        return .denied
    }

    func start(
        descriptor: SurfaceDescriptor,
        onFrame: @escaping @Sendable (FrameRef) -> Void,
        onEnd: @escaping @Sendable (CaptureEnd) -> Void
    ) throws {
        reportIssue("CameraRepository.start not implemented")
        throw CaptureSessionError.deviceUnavailable
    }

    func stop() {
        reportIssue("CameraRepository.stop not implemented")
    }
}
