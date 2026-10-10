import Dependencies

/// The host frame path: camera → latest-frame slot → one effect pass per
/// scheduler tick (at most one in flight; a failed pass sends its input
/// unchanged) → virtual camera sink and preview, with every lease released
/// exactly once: a frame sent is presented too, and released once both are
/// done with it.
public protocol FramePipelineUseCase: Sendable {
    /// Starts the camera and the scheduler, then connects the sink (retrying
    /// per the transport's policy, so this suspends until the extension answers
    /// or the task is cancelled). Frames captured meanwhile are dropped as
    /// `.notConnected`. Throws only when the camera cannot start; a sink that
    /// never connects is logged, not thrown.
    func start(descriptor: SurfaceDescriptor, frameRate: FrameRate) async throws
    func stop()
    var stats: PipelineStats { get }
}

public enum FramePipelineUseCaseKey: TestDependencyKey {
    public static let testValue: any FramePipelineUseCase = UnimplementedFramePipelineUseCase()
}

extension DependencyValues {
    public var framePipelineUseCase: any FramePipelineUseCase {
        get { self[FramePipelineUseCaseKey.self] }
        set { self[FramePipelineUseCaseKey.self] = newValue }
    }
}

private struct UnimplementedFramePipelineUseCase: FramePipelineUseCase {
    func start(descriptor: SurfaceDescriptor, frameRate: FrameRate) async throws {
        reportIssue("FramePipelineUseCase.start not implemented")
        throw CaptureSessionError.deviceUnavailable
    }

    func stop() {
        reportIssue("FramePipelineUseCase.stop not implemented")
    }

    var stats: PipelineStats {
        reportIssue("FramePipelineUseCase.stats not implemented")
        return .empty
    }
}
