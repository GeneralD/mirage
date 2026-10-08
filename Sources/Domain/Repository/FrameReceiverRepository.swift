import Dependencies

/// Extension side mirror of `CameraRepository`: received surfaces adopted into
/// the extension's own pool and handed up as `FrameRef`s.
public protocol FrameReceiverRepository: Sendable {
    func start(
        onFrame: @escaping @Sendable (FrameRef) -> Void,
        onEvent: @escaping @Sendable (ReceiverEvent) -> Void
    ) async throws
    func stop()
}

public enum FrameReceiverRepositoryKey: TestDependencyKey {
    public static let testValue: any FrameReceiverRepository = UnimplementedFrameReceiverRepository()
}

extension DependencyValues {
    public var frameReceiverRepository: any FrameReceiverRepository {
        get { self[FrameReceiverRepositoryKey.self] }
        set { self[FrameReceiverRepositoryKey.self] = newValue }
    }
}

private struct UnimplementedFrameReceiverRepository: FrameReceiverRepository {
    func start(
        onFrame: @escaping @Sendable (FrameRef) -> Void,
        onEvent: @escaping @Sendable (ReceiverEvent) -> Void
    ) async throws {
        reportIssue("FrameReceiverRepository.start not implemented")
        throw MachError.checkInFailed(code: -1)
    }

    func stop() {
        reportIssue("FrameReceiverRepository.stop not implemented")
    }
}
