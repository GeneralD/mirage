import CoreMedia
import CoreMediaIO
import Domain

/// Support for `StreamOutputGatewayImpl` (port: `StreamOutputGateway`).
/// The `CMIOExtensionStreamSource` (CoreMediaIO); start/stop are relayed as
/// events, the "only send while a client streams" decision is the DataSource's.
final class StreamSource: NSObject, CMIOExtensionStreamSource, @unchecked Sendable {
    let formats: [CMIOExtensionStreamFormat]
    let availableProperties: Set<CMIOExtensionProperty> = [.streamActiveFormatIndex, .streamFrameDuration]
    private let frameDuration: CMTime
    private let onEvent: @Sendable (StreamOutputEvent) -> Void

    init(format: CMIOExtensionStreamFormat, frameDuration: CMTime, onEvent: @escaping @Sendable (StreamOutputEvent) -> Void) {
        formats = [format]
        self.frameDuration = frameDuration
        self.onEvent = onEvent
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let result = CMIOExtensionStreamProperties(dictionary: [:])
        result.activeFormatIndex = properties.contains(.streamActiveFormatIndex) ? 0 : nil
        result.frameDuration = properties.contains(.streamFrameDuration) ? frameDuration : nil
        return result
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool { true }

    func startStream() throws { onEvent(.streamStarted) }

    func stopStream() throws { onEvent(.streamStopped) }
}
