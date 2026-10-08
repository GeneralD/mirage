import Domain
import IOSurface

/// Adapter for `StreamOutputGateway`; wraps `CMIOExtensionStream.send`.
/// `current` is written once by `start` (extension launch) and only read
/// afterwards from the frame executor, so the box needs no lock.
public final class StreamOutputGatewayImpl: @unchecked Sendable {
    private let current = CurrentSession()

    public init() {}
}

extension StreamOutputGatewayImpl: StreamOutputGateway {
    public func start(
        deviceName: String,
        descriptor: SurfaceDescriptor,
        frameRate: FrameRate,
        onEvent: @escaping @Sendable (StreamOutputEvent) -> Void
    ) throws {
        current.session = try Result {
            try StreamAssembly.start(deviceName: deviceName, descriptor: descriptor, frameRate: frameRate, onEvent: onEvent)
        }
        .mapError { ($0 as? StreamOutputError) ?? .providerSetupFailed(String(describing: $0)) }
        .get()
    }

    public func send(_ surface: any SurfaceHandle, presentationTime: HostTimestamp) throws {
        let session = try current.session.orThrow(StreamOutputError.notStarted)
        let ioSurface = try (surface.backing as? IOSurface).orThrow(SurfaceError.foreignHandle)
        let buffer = try SampleBufferFactory.make(ioSurface, presentationTime: presentationTime, session: session)
        session.stream.send(buffer, discontinuity: [], hostTimeInNanoseconds: presentationTime.nanoseconds)
    }
}

private final class CurrentSession: @unchecked Sendable {
    public var session: StreamSession?
}
