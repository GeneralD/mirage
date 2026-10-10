import Dependencies

/// The lite dev harness's launch sequence (#21) for the entry lane: show the
/// solid frame in the preview window and ask for the camera once, so a run
/// shows whether TCC honours the `Info.plist` linked into the binary.
public protocol HarnessInteractor: Sendable {
    /// Starts the solid frame, then asks for the camera and logs the answer.
    /// The frame does not wait for the prompt. An answer that arrives after the
    /// caller's task was cancelled is not reported.
    func launch(descriptor: SurfaceDescriptor, frameRate: FrameRate) async

    /// Main thread: attaches the preview window's view. A refusal is logged;
    /// the window then stays empty.
    @MainActor func attach(_ target: any PreviewTargetHandle)

    /// Stops the solid frame.
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
