import Dependencies

/// The host frame path: camera → latest-frame slot → one effect pass per
/// scheduler tick (at most one in flight; a failed pass sends its input
/// unchanged, and while bypassed every frame does) → virtual camera sink and preview, with every lease released
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

    /// While true, every frame the pipeline takes goes through the pass-through delivery a failed effect pass already uses: no effect pass is started and the effect runtime is not called. Returns at once; the change reaches the next tick. It is kept across `stop()` and `start(...)`.
    func setBypass(_ bypassed: Bool)

    /// Sets what the preview shows of each frame it presents. `after` (the default) shows the
    /// frame alone. `split` also hands the preview the input of a successful pass as the frame's
    /// original, so the input stays leased until the preview's completion, not the pass's answer;
    /// a failed pass presents its input as the frame, with no original. Returns at once; the change
    /// reaches the next answer the pipeline takes. It is kept across `stop()` and `start(...)`.
    func setPreviewMode(_ mode: PreviewMode)
    var stats: PipelineStats { get }

    /// Main thread: hands the preview window's view to the `PreviewSink` the
    /// pipeline presents to, a pass-through of `PreviewSink.attach`. It may come
    /// before `start` or after: until a view is attached the preview gives every
    /// frame back undrawn. A refusal is thrown and the previous view stays.
    @MainActor func attachPreview(_ target: any PreviewTargetHandle) throws

    /// A pass-through of `PreviewSink.detach`, callable from any context: the preview
    /// lets go of `target` only when it is the view attached now, and a call naming any
    /// other target does nothing. Frames presented after the detach complete undrawn,
    /// as they do before any attach. A frame already handed to the preview keeps its
    /// lease until its completion, detach or not.
    func detachPreview(_ target: any PreviewTargetHandle)
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

    func setBypass(_ bypassed: Bool) {
        reportIssue("FramePipelineUseCase.setBypass not implemented")
    }

    func setPreviewMode(_ mode: PreviewMode) {
        reportIssue("FramePipelineUseCase.setPreviewMode not implemented")
    }

    var stats: PipelineStats {
        reportIssue("FramePipelineUseCase.stats not implemented")
        return .empty
    }

    @MainActor func attachPreview(_ target: any PreviewTargetHandle) throws {
        reportIssue("FramePipelineUseCase.attachPreview not implemented")
        throw PreviewError.foreignTarget
    }

    func detachPreview(_ target: any PreviewTargetHandle) {
        reportIssue("FramePipelineUseCase.detachPreview not implemented")
    }
}
