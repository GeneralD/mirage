import CoreMedia
import CoreMediaIO

/// Support for `StreamOutputGatewayImpl` (port: `StreamOutputGateway`).
/// Wraps the started CMIO stream (`CMIOExtensionStream`) with the format
/// description and frame duration its sample buffers must carry. It also owns
/// the sources: CoreMediaIO declares every `source` property `weak`, so
/// without these strong references they would be freed once `start` returns.
struct StreamSession: @unchecked Sendable {
    let stream: CMIOExtensionStream
    let formatDescription: CMVideoFormatDescription
    let frameDuration: CMTime
    let providerSource: ProviderSource
    let deviceSource: DeviceSource
    let streamSource: StreamSource
    let device: CMIOExtensionDevice
    let provider: CMIOExtensionProvider
}
