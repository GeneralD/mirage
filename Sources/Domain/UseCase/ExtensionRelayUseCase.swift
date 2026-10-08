import Dependencies

/// The extension's frame path: declare the stream, receive host frames and
/// relay each one to the stream, releasing the lease after the send. `run`
/// returns when `stop()` is called or the receive loop ends.
public protocol ExtensionRelayUseCase: Sendable {
    func run(descriptor: SurfaceDescriptor, frameRate: FrameRate) async throws
    func stop()
    var stats: PipelineStats { get }
}

public enum ExtensionRelayUseCaseKey: TestDependencyKey {
    public static let testValue: any ExtensionRelayUseCase = UnimplementedExtensionRelayUseCase()
}

extension DependencyValues {
    public var extensionRelayUseCase: any ExtensionRelayUseCase {
        get { self[ExtensionRelayUseCaseKey.self] }
        set { self[ExtensionRelayUseCaseKey.self] = newValue }
    }
}

private struct UnimplementedExtensionRelayUseCase: ExtensionRelayUseCase {
    func run(descriptor: SurfaceDescriptor, frameRate: FrameRate) async throws {
        reportIssue("ExtensionRelayUseCase.run not implemented")
        throw MachError.checkInFailed(code: -1)
    }

    func stop() {
        reportIssue("ExtensionRelayUseCase.stop not implemented")
    }

    var stats: PipelineStats {
        reportIssue("ExtensionRelayUseCase.stats not implemented")
        return .empty
    }
}
