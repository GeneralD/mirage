import Dependencies

/// The lite dev harness's frame source (#21): one solid frame, leased once from
/// `SurfaceRepository`, presented on the `PreviewSink` at every `FrameScheduler`
/// tick while no presentation of it is outstanding. No camera and no effect; the
/// harness moves onto the frame pipeline with #24.
///
/// `start` runs once, then `stop` once. A `start` that reaches the frame path
/// after `stop` does nothing, so a caller that starts from a task need not
/// order the two itself.
public protocol SolidFrameUseCase: Sendable {
    /// Main thread: hands the preview window's view to the sink. A pass-through
    /// of `PreviewSink.attach`: a refusal is thrown and the previous view stays.
    @MainActor func attach(_ target: any PreviewTargetHandle) throws

    /// Leases the frame and starts ticking at `frameRate`, with a summary line
    /// in the developer log once per second of ticks. A frame that cannot be
    /// leased is logged and nothing ticks.
    func start(descriptor: SurfaceDescriptor, frameRate: FrameRate)

    /// Stops the ticks. The frame goes back now, or when its outstanding
    /// presentation completes, exactly once.
    func stop()
}

public enum SolidFrameUseCaseKey: TestDependencyKey {
    public static let testValue: any SolidFrameUseCase = UnimplementedSolidFrameUseCase()
}

extension DependencyValues {
    public var solidFrameUseCase: any SolidFrameUseCase {
        get { self[SolidFrameUseCaseKey.self] }
        set { self[SolidFrameUseCaseKey.self] = newValue }
    }
}

private struct UnimplementedSolidFrameUseCase: SolidFrameUseCase {
    @MainActor func attach(_ target: any PreviewTargetHandle) throws {
        reportIssue("SolidFrameUseCase.attach not implemented")
    }

    func start(descriptor: SurfaceDescriptor, frameRate: FrameRate) {
        reportIssue("SolidFrameUseCase.start not implemented")
    }

    func stop() {
        reportIssue("SolidFrameUseCase.stop not implemented")
    }
}
