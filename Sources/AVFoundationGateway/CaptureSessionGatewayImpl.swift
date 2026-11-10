/// Implements `CaptureSessionGateway`.
/// Wraps `AVCaptureSession` (the camera `capture` names, BGRA 1280x720 output).
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
        try CaptureRig(descriptor: descriptor, capture: capture, onFrame: onFrame, onEnd: onEnd)
    }
}
