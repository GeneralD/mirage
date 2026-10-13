import Dependencies
import Domain

/// The dev harness's launch sequence: camera permission through
/// `CameraControlUseCase` (the policy the host's launch uses), then the host's
/// `FramePipelineUseCase` — camera → effect → sink and preview — in this process.
/// It is `CameraInteractorImpl` minus the extension install, which the harness has
/// neither the bundle nor the need for (the sink it runs against discards frames).
/// A camera that is not granted starts nothing, and every outcome is a log line: the
/// harness has no display state of its own beyond the preview.
public struct HarnessInteractorImpl: Sendable {
    @Dependency(\.cameraControlUseCase) private var cameraControl
    @Dependency(\.framePipelineUseCase) private var pipeline
    @Dependency(\.errorLog) private var errorLog
    @Dependency(\.developerLog) private var developerLog

    public init() {}
}

extension HarnessInteractorImpl: HarnessInteractor {
    public func launch(descriptor: SurfaceDescriptor, frameRate: FrameRate) async {
        let status = await cameraControl.ensureAuthorized()
        guard !Task.isCancelled else { return }
        developerLog.record(.camera, "camera authorization: \(status)")
        guard status.isGranted else {
            errorLog.record(.camera, "camera access not granted (\(status)); Lane 1 of .claude/rules/dev-verification.md covers TCC")
            return
        }
        await startPipeline(descriptor: descriptor, frameRate: frameRate)
    }

    @MainActor
    public func attach(_ target: any PreviewTargetHandle) {
        do {
            try pipeline.attachPreview(target)
            developerLog.record(.preview, "preview window attached")
        } catch {
            errorLog.record(.preview, "preview window not attached: \(error)")
        }
    }

    public func shutDown() {
        pipeline.stop()
    }
}

extension HarnessInteractorImpl {
    /// The pipeline throws only when the camera cannot start, or the task is cancelled
    /// (a harness being quit): the second says nothing worth a line.
    private func startPipeline(descriptor: SurfaceDescriptor, frameRate: FrameRate) async {
        do {
            try await pipeline.start(descriptor: descriptor, frameRate: frameRate)
            developerLog.record(.pipeline, "pipeline started")
        } catch is CancellationError {
            return
        } catch {
            errorLog.record(.pipeline, "pipeline failed to start: \(error)")
        }
    }
}
