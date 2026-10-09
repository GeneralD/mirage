import Dependencies

/// `PreviewDataSource`: draws presented frames into the attached preview target.
/// Owns the preview kernel's source, the `SurfaceToken` → texture binding, the
/// attach state and the draw order: work runs on the `FrameExecutor`, one draw
/// is in flight at a time, and of the frames that arrive meanwhile only the
/// newest waits — the ones it replaces complete undrawn. Every `present`
/// completes exactly once, drawn or not.
public protocol PreviewRenderer: Sendable {
    /// Readies `target` and makes it the one frames are drawn into; on the main
    /// thread, because the target is a view. A failed attach leaves the
    /// previous target attached.
    @MainActor
    func attach(_ target: any PreviewTargetHandle) throws
    func present(_ frame: FrameRef, completion: @escaping @Sendable () -> Void)
}

public enum PreviewRendererKey: TestDependencyKey {
    public static let testValue: any PreviewRenderer = UnimplementedPreviewRenderer()
}

extension DependencyValues {
    public var previewRenderer: any PreviewRenderer {
        get { self[PreviewRendererKey.self] }
        set { self[PreviewRendererKey.self] = newValue }
    }
}

private struct UnimplementedPreviewRenderer: PreviewRenderer {
    func attach(_ target: any PreviewTargetHandle) throws {
        reportIssue("PreviewRenderer.attach not implemented")
        throw PreviewError.foreignTarget
    }

    func present(_ frame: FrameRef, completion: @escaping @Sendable () -> Void) {
        reportIssue("PreviewRenderer.present not implemented")
        completion()
    }
}
