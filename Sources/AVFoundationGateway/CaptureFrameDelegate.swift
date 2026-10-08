/// Implements the frame callback of `CaptureSessionGateway`.
/// Wraps `AVCaptureVideoDataOutputSampleBufferDelegate` and `CMSampleBuffer`.
/// Hands each sample buffer's IOSurface and PTS on; no frame policy lives here.
import AVFoundation
import CoreMedia
import Domain

final class CaptureFrameDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let onFrame: @Sendable (CapturedSurface) -> Void

    init(onFrame: @escaping @Sendable (CapturedSurface) -> Void) {
        self.onFrame = onFrame
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        CMSampleBufferGetImageBuffer(sampleBuffer)
            .flatMap { surface(of: $0, at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds) }
            .map(onFrame)
    }

    /// The pixel format is always BGRA: the output's `videoSettings` pins it.
    private func surface(of pixelBuffer: CVPixelBuffer, at seconds: Double) -> CapturedSurface? {
        CVPixelBufferGetIOSurface(pixelBuffer).map {
            CapturedSurface(
                handle: CapturedPixelBuffer(backing: $0.takeUnretainedValue(), pixelBuffer: pixelBuffer),
                descriptor: SurfaceDescriptor(
                    width: CVPixelBufferGetWidth(pixelBuffer),
                    height: CVPixelBufferGetHeight(pixelBuffer),
                    pixelFormat: .bgra32,
                    bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer)
                ),
                presentationSeconds: seconds
            )
        }
    }
}
