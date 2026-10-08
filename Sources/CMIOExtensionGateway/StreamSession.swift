import CoreMedia
import CoreMediaIO

/// Support for `StreamOutputGatewayImpl` (port: `StreamOutputGateway`).
/// Wraps the started CMIO stream (`CMIOExtensionStream`) with the format
/// description and frame duration its sample buffers must carry.
struct StreamSession: @unchecked Sendable {
    let stream: CMIOExtensionStream
    let formatDescription: CMVideoFormatDescription
    let frameDuration: CMTime
}
