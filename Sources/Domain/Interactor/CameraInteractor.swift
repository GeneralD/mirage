import Dependencies

/// Host launch sequence for the entry lane: install the extension, obtain
/// camera permission, start the pipeline, and report what happened.
public protocol CameraInteractor: Sendable {
    func launch(descriptor: SurfaceDescriptor, frameRate: FrameRate) async -> LaunchReport
    func shutDown()
}

public enum CameraInteractorKey: TestDependencyKey {
    public static let testValue: any CameraInteractor = UnimplementedCameraInteractor()
}

extension DependencyValues {
    public var cameraInteractor: any CameraInteractor {
        get { self[CameraInteractorKey.self] }
        set { self[CameraInteractorKey.self] = newValue }
    }
}

private struct UnimplementedCameraInteractor: CameraInteractor {
    func launch(descriptor: SurfaceDescriptor, frameRate: FrameRate) async -> LaunchReport {
        reportIssue("CameraInteractor.launch not implemented")
        return LaunchReport(install: .notInstalled, authorization: .denied, pipelineStarted: false)
    }

    func shutDown() {
        reportIssue("CameraInteractor.shutDown not implemented")
    }
}
