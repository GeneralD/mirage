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

/// Thin pass-through to `AVCaptureSession`: configure the default camera for
/// `descriptor`, deliver each sample buffer's surface to `onFrame` on the
/// session's own queue, report the end of the session to `onEnd`.
public protocol CaptureSessionGateway: Sendable {
    func start(
        descriptor: SurfaceDescriptor,
        onFrame: @escaping @Sendable (CapturedSurface) -> Void,
        onEnd: @escaping @Sendable (CaptureEnd) -> Void
    ) throws
    func stop()
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
    ) throws {
        reportIssue("CaptureSessionGateway.start not implemented")
        throw CaptureSessionError.deviceUnavailable
    }

    func stop() {
        reportIssue("CaptureSessionGateway.stop not implemented")
    }
}
