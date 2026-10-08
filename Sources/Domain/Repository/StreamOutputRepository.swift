import Dependencies

/// The extension's output stream for `FrameRef`s: resolves the lease to its
/// surface and sends. The caller releases the lease afterwards.
public protocol StreamOutputRepository: Sendable {
    func start(
        descriptor: SurfaceDescriptor,
        frameRate: FrameRate,
        onEvent: @escaping @Sendable (StreamOutputEvent) -> Void
    ) throws
    var isStreaming: Bool { get }
    func send(_ frame: FrameRef) -> SendOutcome
}

public enum StreamOutputRepositoryKey: TestDependencyKey {
    public static let testValue: any StreamOutputRepository = UnimplementedStreamOutputRepository()
}

extension DependencyValues {
    public var streamOutputRepository: any StreamOutputRepository {
        get { self[StreamOutputRepositoryKey.self] }
        set { self[StreamOutputRepositoryKey.self] = newValue }
    }
}

private struct UnimplementedStreamOutputRepository: StreamOutputRepository {
    func start(
        descriptor: SurfaceDescriptor,
        frameRate: FrameRate,
        onEvent: @escaping @Sendable (StreamOutputEvent) -> Void
    ) throws {
        reportIssue("StreamOutputRepository.start not implemented")
        throw StreamOutputError.notStarted
    }

    var isStreaming: Bool {
        reportIssue("StreamOutputRepository.isStreaming not implemented")
        return false
    }

    func send(_ frame: FrameRef) -> SendOutcome {
        reportIssue("StreamOutputRepository.send not implemented")
        return .dropped(.noClient)
    }
}
