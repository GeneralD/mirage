import Dependencies

/// The dev harness's launch sequence for the entry lane: ask for the camera
/// once, then run the host pipeline — camera → effect → preview — in this process,
/// with no extension. It is `CameraInteractor` without the install step, which a
/// SwiftPM executable cannot take, and every outcome is a log line: the harness has no
/// display state of its own beyond the preview.
public protocol HarnessInteractor: Sendable {
    /// Asks for the camera and logs the answer; when it is granted, starts the
    /// pipeline at `descriptor` and `frameRate` and logs that. An answer that arrives
    /// after the caller's task was cancelled is not reported, and nothing starts.
    func launch(descriptor: SurfaceDescriptor, frameRate: FrameRate) async

    /// Main thread: attaches the preview window's view. A refusal is logged;
    /// the window then stays empty. It may come before the pipeline starts or after.
    @MainActor func attach(_ target: any PreviewTargetHandle)

    /// Stops the pipeline.
    func shutDown()
}

public enum HarnessInteractorKey: TestDependencyKey {
    public static let testValue: any HarnessInteractor = UnimplementedHarnessInteractor()
}

extension DependencyValues {
    public var harnessInteractor: any HarnessInteractor {
        get { self[HarnessInteractorKey.self] }
        set { self[HarnessInteractorKey.self] = newValue }
    }
}

private struct UnimplementedHarnessInteractor: HarnessInteractor {
    func launch(descriptor: SurfaceDescriptor, frameRate: FrameRate) async {
        reportIssue("HarnessInteractor.launch not implemented")
    }

    @MainActor func attach(_ target: any PreviewTargetHandle) {
        reportIssue("HarnessInteractor.attach not implemented")
    }

    func shutDown() {
        reportIssue("HarnessInteractor.shutDown not implemented")
    }
}
