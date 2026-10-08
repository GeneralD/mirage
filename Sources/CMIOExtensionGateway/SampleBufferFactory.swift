import CoreMedia
import CoreVideo
import Domain
import IOSurface

/// Support for `StreamOutputGatewayImpl` (port: `StreamOutputGateway`).
/// Wraps an `IOSurface` into a `CMSampleBuffer` (CoreVideo + CoreMedia) with
/// no pixel copy; the decision to send at all lives in the DataSource.
enum SampleBufferFactory {
    static func make(_ surface: IOSurface, presentationTime: HostTimestamp, session: StreamSession) throws -> CMSampleBuffer {
        let created = OutParam.call { CVPixelBufferCreateWithIOSurface(nil, surface, nil, $0) }
        let failure = StreamOutputError.sampleBufferFailed(code: Int(created.status))
        try (created.status == kCVReturnSuccess).orThrow(failure)
        let pixelBuffer = try created.value.orThrow(failure).takeRetainedValue()
        let timing = CMSampleTimingInfo(
            duration: session.frameDuration,
            presentationTimeStamp: CMTime(value: Int64(clamping: presentationTime.nanoseconds), timescale: 1_000_000_000),
            decodeTimeStamp: .invalid
        )
        return try CMSampleBuffer(imageBuffer: pixelBuffer, formatDescription: session.formatDescription, sampleTiming: timing)
    }
}
