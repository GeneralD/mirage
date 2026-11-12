import Dependencies

/// Host-side attach and detach of the preview window's view to the pipeline's
/// preview. A refusal is a value, not a throw, so the window's presenter can say why.
public protocol PreviewInteractor: Sendable {
    /// Main thread: attaches the window's view. Returns `.attached`, or the
    /// refusal the pipeline gave, and logs either outcome.
    @MainActor func attach(_ target: any PreviewTargetHandle) -> PreviewAttachResult

    /// Detaches the window's view. Keeps no state: a second call reaches the pipeline again.
    func detach(_ target: any PreviewTargetHandle)

    /// Sets what the preview shows of each frame. Keeps no state: every call reaches the
    /// pipeline, so a repeated mode is passed on again.
    func setMode(_ mode: PreviewMode)
}

public enum PreviewInteractorKey: TestDependencyKey {
    public static let testValue: any PreviewInteractor = UnimplementedPreviewInteractor()
}

extension DependencyValues {
    public var previewInteractor: any PreviewInteractor {
        get { self[PreviewInteractorKey.self] }
        set { self[PreviewInteractorKey.self] = newValue }
    }
}

private struct UnimplementedPreviewInteractor: PreviewInteractor {
    @MainActor func attach(_ target: any PreviewTargetHandle) -> PreviewAttachResult {
        reportIssue("PreviewInteractor.attach not implemented")
        return .refused(.unavailable)
    }

    func detach(_ target: any PreviewTargetHandle) {
        reportIssue("PreviewInteractor.detach not implemented")
    }

    func setMode(_ mode: PreviewMode) {
        reportIssue("PreviewInteractor.setMode not implemented")
    }
}
