import Dependencies
import Domain

/// The lite dev harness's launch sequence: the solid frame first, then the
/// camera prompt through `CameraControlUseCase` (the policy the host's launch
/// uses). Nothing waits for the prompt, and every outcome is a log line: the
/// harness has no display state of its own beyond the preview.
public struct HarnessInteractorImpl: Sendable {
    @Dependency(\.solidFrameUseCase) private var solidFrame
    @Dependency(\.cameraControlUseCase) private var cameraControl
    @Dependency(\.errorLog) private var errorLog
    @Dependency(\.developerLog) private var developerLog

    public init() {}
}

extension HarnessInteractorImpl: HarnessInteractor {
    public func launch(descriptor: SurfaceDescriptor, frameRate: FrameRate) async {
        solidFrame.start(descriptor: descriptor, frameRate: frameRate)
        let status = await cameraControl.ensureAuthorized()
        guard !Task.isCancelled else { return }
        developerLog.record(.camera, "camera authorization: \(status)")
        guard !status.isGranted else { return }
        errorLog.record(.camera, "camera access not granted (\(status)); Lane 1 of .claude/rules/dev-verification.md covers TCC")
    }

    @MainActor
    public func attach(_ target: any PreviewTargetHandle) {
        do {
            try solidFrame.attach(target)
            developerLog.record(.preview, "preview window attached")
        } catch {
            errorLog.record(.preview, "preview window not attached: \(error)")
        }
    }

    public func shutDown() {
        solidFrame.stop()
    }
}
