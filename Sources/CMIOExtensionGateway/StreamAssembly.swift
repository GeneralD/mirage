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
        let stream = CMIOExtensionStream(
            localizedName: deviceName,
            streamID: try identifier(String(ProductIdentity.virtualDeviceID.dropLast()) + "4"),
            direction: .source,
            clockType: .hostTime,
            source: StreamSource(format: format, frameDuration: duration, onEvent: onEvent)
        )
        let device = CMIOExtensionDevice(
            localizedName: deviceName,
            deviceID: try identifier(ProductIdentity.virtualDeviceID),
            legacyDeviceID: nil,
            source: DeviceSource(model: deviceName)
        )
        let provider = CMIOExtensionProvider(source: ProviderSource(), clientQueue: nil)
        try device.addStream(stream)
        try provider.addDevice(device)
        CMIOExtensionProvider.startService(provider: provider)
        return StreamSession(stream: stream, formatDescription: formatDescription, frameDuration: duration)
    }

    private static func identifier(_ text: String) throws -> UUID {
        try UUID(uuidString: text).orThrow(StreamOutputError.providerSetupFailed("invalid identifier \(text)"))
    }
}
