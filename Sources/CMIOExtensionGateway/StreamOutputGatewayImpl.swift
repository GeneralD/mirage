/// Implements `StreamOutputGateway` and `StreamOutputHandle`.
/// Wraps `CMIOExtensionProvider.startService` and `CMIOExtensionStream.send`.
/// Stateless: each start is one `StreamSession`, handed back as the handle.
import Domain
import IOSurface

public struct StreamOutputGatewayImpl: Sendable {
    public init() {}
}

extension StreamOutputGatewayImpl: StreamOutputGateway {
    public func start(
        deviceName: String,
        descriptor: SurfaceDescriptor,
        frameRate: FrameRate,
        onEvent: @escaping @Sendable (StreamOutputEvent) -> Void
    ) throws -> any StreamOutputHandle {
        try Result {
            try StreamAssembly.start(deviceName: deviceName, descriptor: descriptor, frameRate: frameRate, onEvent: onEvent)
        }
        .mapError { ($0 as? StreamOutputError) ?? .providerSetupFailed(String(describing: $0)) }
        .get()
    }
}

extension StreamSession: StreamOutputHandle {
    public func send(_ surface: any SurfaceHandle, presentationTime: HostTimestamp) throws {
        let ioSurface = try (surface.backing as? IOSurface).orThrow(SurfaceError.foreignHandle)
        let buffer = try SampleBufferFactory.make(ioSurface, presentationTime: presentationTime, session: self)
        stream.send(buffer, discontinuity: [], hostTimeInNanoseconds: presentationTime.nanoseconds)
    }
}
