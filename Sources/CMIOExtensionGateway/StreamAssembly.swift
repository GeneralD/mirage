import CoreMedia
import CoreMediaIO
import Domain

/// Support for `StreamOutputGatewayImpl` (port: `StreamOutputGateway`).
/// Builds provider, device and stream for `CMIOExtensionProvider.startService`;
/// the stream id is the device id with its last hex digit changed.
enum StreamAssembly {
    static func start(
        deviceName: String,
        descriptor: SurfaceDescriptor,
        frameRate: FrameRate,
        onEvent: @escaping @Sendable (StreamOutputEvent) -> Void
    ) throws -> StreamSession {
        let formats = try StreamFormatSet.make(descriptor: descriptor, frameRate: frameRate)
        let streamSource = StreamSource(format: formats.format, frameDuration: formats.duration, onEvent: onEvent)
        let deviceSource = DeviceSource(model: deviceName)
        let providerSource = ProviderSource()
        let stream = CMIOExtensionStream(
            localizedName: deviceName,
            streamID: try identifier(String(ProductIdentity.virtualDeviceID.dropLast()) + "4"),
            direction: .source,
            clockType: .hostTime,
            source: streamSource
        )
        let device = CMIOExtensionDevice(
            localizedName: deviceName,
            deviceID: try identifier(ProductIdentity.virtualDeviceID),
            legacyDeviceID: nil,
            source: deviceSource
        )
        let provider = CMIOExtensionProvider(source: providerSource, clientQueue: nil)
        try device.addStream(stream)
        try provider.addDevice(device)
        CMIOExtensionProvider.startService(provider: provider)
        return StreamSession(
            stream: stream, formatDescription: formats.formatDescription, frameDuration: formats.duration,
            providerSource: providerSource, deviceSource: deviceSource, streamSource: streamSource,
            device: device, provider: provider
        )
    }

    private static func identifier(_ text: String) throws -> UUID {
        try UUID(uuidString: text).orThrow(StreamOutputError.providerSetupFailed("invalid identifier \(text)"))
    }
}
