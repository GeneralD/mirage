import Dependencies

/// One frame as the capture session delivered it: the IOSurface behind the
/// `CVPixelBuffer` (kept alive by the handle) and the raw presentation time in
/// seconds on the session's clock. `CameraDataSource` turns the seconds into a
/// `HostTimestamp`.
public struct CapturedSurface: Sendable {
    public let handle: any SurfaceHandle
    public let descriptor: SurfaceDescriptor
    public let presentationSeconds: Double

    public init(handle: any SurfaceHandle, descriptor: SurfaceDescriptor, presentationSeconds: Double) {
        self.handle = handle
        self.descriptor = descriptor
        self.presentationSeconds = presentationSeconds
    }
}

/// One running capture session, as `CaptureSessionGateway.start` handed it
/// out. Whoever started the session owns the handle and stops it; the gateway
/// keeps no record of it.
public protocol CaptureSessionHandle: Sendable {
    func stop()
}

/// Thin pass-through to `AVCaptureSession`: configure the default camera for
/// `descriptor`, deliver each sample buffer's surface to `onFrame` on the
/// session's own queue, report the end of the session to `onEnd`. Stateless:
/// the running session lives in the returned handle, so which session is
/// current is decided one layer up, where it is tested.
public protocol CaptureSessionGateway: Sendable {
    func start(
        descriptor: SurfaceDescriptor,
        onFrame: @escaping @Sendable (CapturedSurface) -> Void,
        onEnd: @escaping @Sendable (CaptureEnd) -> Void
    ) throws -> any CaptureSessionHandle
}

public enum CaptureSessionGatewayKey: TestDependencyKey {
    public static let testValue: any CaptureSessionGateway = UnimplementedCaptureSessionGateway()
}

extension DependencyValues {
    public var captureSessionGateway: any CaptureSessionGateway {
        get { self[CaptureSessionGatewayKey.self] }
        set { self[CaptureSessionGatewayKey.self] = newValue }
    }
}

private struct UnimplementedCaptureSessionGateway: CaptureSessionGateway {
    func start(
        descriptor: SurfaceDescriptor,
        onFrame: @escaping @Sendable (CapturedSurface) -> Void,
        onEnd: @escaping @Sendable (CaptureEnd) -> Void
    ) throws -> any CaptureSessionHandle {
        reportIssue("CaptureSessionGateway.start not implemented")
        throw CaptureSessionError.deviceUnavailable
    }
}
