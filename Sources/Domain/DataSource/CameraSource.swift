import Dependencies

/// A surface that just arrived from outside the layer stack — the camera on the
/// host, the Mach port on the extension — with its timing already on the
/// host-time axis. The repository above adopts the handle into the surface pool
/// and turns it into a `FrameRef`.
public struct IncomingSurface: Sendable {
    public let handle: any SurfaceHandle
    public let descriptor: SurfaceDescriptor
    public let presentationTime: HostTimestamp

    public init(handle: any SurfaceHandle, descriptor: SurfaceDescriptor, presentationTime: HostTimestamp) {
        self.handle = handle
        self.descriptor = descriptor
        self.presentationTime = presentationTime
    }
}

/// `CameraDataSource`: the capture session's frames with their PTS converted to
/// `HostTimestamp` (monotonic contract: a frame older than the previous one is
/// dropped here). Callbacks are delivered on the `FrameExecutor`.
public protocol CameraSource: Sendable {
    func start(
        descriptor: SurfaceDescriptor,
        onFrame: @escaping @Sendable (IncomingSurface) -> Void,
        onEnd: @escaping @Sendable (CaptureEnd) -> Void
    ) throws
    func stop()
}

public enum CameraSourceKey: TestDependencyKey {
    public static let testValue: any CameraSource = UnimplementedCameraSource()
}

extension DependencyValues {
    public var cameraSource: any CameraSource {
        get { self[CameraSourceKey.self] }
        set { self[CameraSourceKey.self] = newValue }
    }
}

private struct UnimplementedCameraSource: CameraSource {
    func start(
        descriptor: SurfaceDescriptor,
        onFrame: @escaping @Sendable (IncomingSurface) -> Void,
        onEnd: @escaping @Sendable (CaptureEnd) -> Void
    ) throws {
        reportIssue("CameraSource.start not implemented")
        throw CaptureSessionError.deviceUnavailable
    }

    func stop() {
        reportIssue("CameraSource.stop not implemented")
    }
}
