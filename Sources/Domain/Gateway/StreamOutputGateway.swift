import Dependencies

/// Thin pass-through to the CMIO extension objects: one provider, one device,
/// one source stream declared with `descriptor` / `frameRate` and the
/// `.hostTime` clock. `send` wraps the surface in a `CMSampleBuffer` whose PTS
/// and `hostTimeInNanoseconds` are both `presentationTime`.
public protocol StreamOutputGateway: Sendable {
    func start(
        deviceName: String,
        descriptor: SurfaceDescriptor,
        frameRate: FrameRate,
        onEvent: @escaping @Sendable (StreamOutputEvent) -> Void
    ) throws
    func send(_ surface: any SurfaceHandle, presentationTime: HostTimestamp) throws
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
    ) throws {
        reportIssue("StreamOutputGateway.start not implemented")
        throw StreamOutputError.notStarted
    }

    func send(_ surface: any SurfaceHandle, presentationTime: HostTimestamp) throws {
        reportIssue("StreamOutputGateway.send not implemented")
        throw StreamOutputError.notStarted
    }
}
