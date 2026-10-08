/// Implements `SurfaceHandle` for frames coming out of `AVCaptureSession`.
/// Wraps the `IOSurface` behind a `CVPixelBuffer` and retains that buffer.
/// Holding the buffer keeps the camera's buffer pool from recycling the surface.
import CoreVideo
import Domain

final class CapturedPixelBuffer: SurfaceHandle, @unchecked Sendable {
    let backing: AnyObject
    private let pixelBuffer: CVPixelBuffer

    init(backing: AnyObject, pixelBuffer: CVPixelBuffer) {
        self.backing = backing
        self.pixelBuffer = pixelBuffer
    }
}
