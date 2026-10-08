import Dependencies

/// `StreamOutputDataSource`: the CMIO stream with the "only send while a client
/// is streaming" decision on top of the gateway. `send` is synchronous on the
/// frame executor.
public protocol StreamOutput: Sendable {
    func start(
        descriptor: SurfaceDescriptor,
        frameRate: FrameRate,
        onEvent: @escaping @Sendable (StreamOutputEvent) -> Void
    ) throws
    var isStreaming: Bool { get }
    /// `.dropped(.noClient)` while no client is streaming, `.dropped(.formatMismatch)`
    /// for a surface whose geometry differs from the declared format.
    func send(_ surface: any SurfaceHandle, descriptor: SurfaceDescriptor, presentationTime: HostTimestamp) -> SendOutcome
}

public enum StreamOutputKey: TestDependencyKey {
    public static let testValue: any StreamOutput = UnimplementedStreamOutput()
}

extension DependencyValues {
    public var streamOutput: any StreamOutput {
        get { self[StreamOutputKey.self] }
        set { self[StreamOutputKey.self] = newValue }
    }
}

private struct UnimplementedStreamOutput: StreamOutput {
    func start(
        descriptor: SurfaceDescriptor,
        frameRate: FrameRate,
        onEvent: @escaping @Sendable (StreamOutputEvent) -> Void
    ) throws {
        reportIssue("StreamOutput.start not implemented")
        throw StreamOutputError.notStarted
    }

    var isStreaming: Bool {
        reportIssue("StreamOutput.isStreaming not implemented")
        return false
    }

    func send(_ surface: any SurfaceHandle, descriptor: SurfaceDescriptor, presentationTime: HostTimestamp) -> SendOutcome {
        reportIssue("StreamOutput.send not implemented")
        return .dropped(.noClient)
    }
}
