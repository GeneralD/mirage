/// Implements the output format of `CaptureSessionGateway`.
/// Wraps the `AVCaptureVideoDataOutput.videoSettings` pixel-buffer attributes.
/// Pins BGRA and IOSurface backing so every sample buffer has a surface to hand on.
import CoreVideo
import Domain

extension CaptureRig {
    static func videoSettings(for descriptor: SurfaceDescriptor) -> [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: descriptor.width,
            kCVPixelBufferHeightKey as String: descriptor.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
    }
}
