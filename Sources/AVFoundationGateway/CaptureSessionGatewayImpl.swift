/// Implements `CaptureSessionGateway`.
/// Wraps `AVCaptureSession` (default video device, BGRA 1280x720 output).
/// Stateless: each start is one `CaptureRig`, handed back as the session handle.
import Domain

public struct CaptureSessionGatewayImpl: Sendable {
    public init() {}
}

extension CaptureSessionGatewayImpl: CaptureSessionGateway {
    public func start(
        descriptor: SurfaceDescriptor,
        capture: CameraCapture,
        onFrame: @escaping @Sendable (CapturedSurface) -> Void,
        onEnd: @escaping @Sendable (CaptureEnd) -> Void
    ) throws -> any CaptureSessionHandle {
        // Received for the capture rig to apply; the rig does not take it yet.
        try CaptureRig(descriptor: descriptor, onFrame: onFrame, onEnd: onEnd)
    }
}
