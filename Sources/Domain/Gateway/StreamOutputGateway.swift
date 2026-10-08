import Dependencies

/// The started CMIO stream, as `StreamOutputGateway.start` handed it out:
/// `send` wraps the surface in a `CMSampleBuffer` whose PTS and
/// `hostTimeInNanoseconds` are both `presentationTime`. Whoever started the
/// stream owns the handle; the gateway keeps no record of it.
public protocol StreamOutputHandle: Sendable {
    func send(_ surface: any SurfaceHandle, presentationTime: HostTimestamp) throws
}

/// Thin pass-through to the CMIO extension objects: one provider, one device,
/// one source stream declared with `descriptor` / `frameRate` and the
/// `.hostTime` clock. Stateless: the running stream lives in the returned
/// handle, so which stream is current is decided one layer up, where it is tested.
public protocol StreamOutputGateway: Sendable {
    func start(
        deviceName: String,
        descriptor: SurfaceDescriptor,
        frameRate: FrameRate,
        onEvent: @escaping @Sendable (StreamOutputEvent) -> Void
    ) throws -> any StreamOutputHandle
}

public enum StreamOutputError: Error, Sendable, Hashable {
    case providerSetupFailed(String)
    case sampleBufferFailed(code: Int)
    case notStarted
}

public enum StreamOutputGatewayKey: TestDependencyKey {
    public static let testValue: any StreamOutputGateway = UnimplementedStreamOutputGateway()
}

extension DependencyValues {
    public var streamOutputGateway: any StreamOutputGateway {
        get { self[StreamOutputGatewayKey.self] }
        set { self[StreamOutputGatewayKey.self] = newValue }
    }
}

private struct UnimplementedStreamOutputGateway: StreamOutputGateway {
    func start(
        deviceName: String,
        descriptor: SurfaceDescriptor,
        frameRate: FrameRate,
        onEvent: @escaping @Sendable (StreamOutputEvent) -> Void
    ) throws -> any StreamOutputHandle {
        reportIssue("StreamOutputGateway.start not implemented")
        throw StreamOutputError.notStarted
    }
}
