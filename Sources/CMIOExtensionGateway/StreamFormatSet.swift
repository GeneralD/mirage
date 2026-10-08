import CoreMedia
import CoreMediaIO
import Domain

/// Support for `StreamOutputGatewayImpl` (port: `StreamOutputGateway`).
/// Builds the one declared stream format (CoreMedia `CMVideoFormatDescription`
/// and CoreMediaIO `CMIOExtensionStreamFormat`) plus its frame duration.
struct StreamFormatSet {
    let formatDescription: CMVideoFormatDescription
    let format: CMIOExtensionStreamFormat
    let duration: CMTime

    static func make(descriptor: SurfaceDescriptor, frameRate: FrameRate) throws -> StreamFormatSet {
        let duration = CMTime(value: 1, timescale: Int32(clamping: frameRate.framesPerSecond))
        let formatDescription = try CMVideoFormatDescription(
            videoCodecType: CMFormatDescription.MediaSubType(rawValue: descriptor.pixelFormat.fourCC),
            width: descriptor.width,
            height: descriptor.height
        )
        let format = CMIOExtensionStreamFormat(
            formatDescription: formatDescription,
            maxFrameDuration: duration,
            minFrameDuration: duration,
            validFrameDurations: nil
        )
        return StreamFormatSet(formatDescription: formatDescription, format: format, duration: duration)
    }
}
