import Dependencies
import Domain

/// The host launch sequence: install the extension, obtain camera permission,
/// then start the pipeline. Camera permission is requested even when the
/// install failed, so the user meets both prompts in one launch instead of
/// being sent back for the second one later.
public struct CameraInteractorImpl: Sendable {
    @Dependency(\.extensionInstallUseCase) private var installUseCase
    @Dependency(\.cameraControlUseCase) private var cameraControl
    @Dependency(\.framePipelineUseCase) private var pipeline
    @Dependency(\.errorLog) private var errorLog
    @Dependency(\.developerLog) private var developerLog

    public init() {}
}

extension CameraInteractorImpl: CameraInteractor {
    public func launch(descriptor: SurfaceDescriptor, frameRate: FrameRate) async -> LaunchReport {
        let install = await install()
        let authorization = await cameraControl.ensureAuthorized()
        developerLog.record(.camera, "camera authorization: \(authorization)")
        let started = await startPipeline(install: install, authorization: authorization, descriptor: descriptor, frameRate: frameRate)
        return LaunchReport(install: install, authorization: authorization, pipelineStarted: started)
    }

    public func shutDown() {
        pipeline.stop()
    }
}

extension CameraInteractorImpl {
    private func install() async -> InstallStatus {
        let (developerLog, errorLog) = (developerLog, errorLog)
        let result = await installUseCase.install { status in
            developerLog.record(.install, "install status: \(status)")
            guard case .failed(let reason) = status else { return }
            errorLog.record(.install, "extension install failed: \(reason)")
        }
        return result
    }

    private func startPipeline(
        install: InstallStatus,
        authorization: CameraAuthorizationStatus,
        descriptor: SurfaceDescriptor,
        frameRate: FrameRate
    ) async -> Bool {
        guard install.isInstalled, authorization.isGranted else {
            developerLog.record(.pipeline, "pipeline not started: install=\(install) authorization=\(authorization)")
            return false
        }
        do {
            try await pipeline.start(descriptor: descriptor, frameRate: frameRate)
            developerLog.record(.pipeline, "pipeline started")
            return true
        } catch {
            errorLog.record(.pipeline, "pipeline failed to start: \(error)")
            return false
        }
    }
}
