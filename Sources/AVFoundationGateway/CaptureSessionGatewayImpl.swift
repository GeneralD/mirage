/// Implements `CaptureSessionGateway`.
/// Wraps `AVCaptureSession` (default video device, BGRA 1280x720 output).
/// Starting stops any running rig first; every decision lives in CameraDataSource.
import Domain
import Foundation

public final class CaptureSessionGatewayImpl: @unchecked Sendable {
    private let lock = NSLock()
    private var rig: CaptureRig?

    public init() {}

    /// Swaps the stored rig and stops the one it replaced, outside the lock.
    private func replace(with new: CaptureRig?) {
        lock.withLock { () -> CaptureRig? in
            defer { rig = new }
            return rig
        }?.stop()
    }
}

extension CaptureSessionGatewayImpl: CaptureSessionGateway {
    public func start(
        descriptor: SurfaceDescriptor,
        onFrame: @escaping @Sendable (CapturedSurface) -> Void,
        onEnd: @escaping @Sendable (CaptureEnd) -> Void
    ) throws {
        // Stop the old rig first: two sessions on one camera must never overlap.
        replace(with: nil)
        replace(with: try CaptureRig(descriptor: descriptor, onFrame: onFrame, onEnd: onEnd))
    }

    public func stop() {
        replace(with: nil)
    }
}
