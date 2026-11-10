import Dependencies

/// `PreviewDataSource`: draws presented frames into the attached preview target.
/// Owns the preview kernel's source, the `SurfaceToken` → texture binding, the
/// attach state and the draw order: work runs on the `FrameExecutor`, one draw
/// is in flight at a time, and of the frames that arrive meanwhile only the
/// newest waits — the ones it replaces complete undrawn. Every `present`
/// completes exactly once, drawn or not.
public protocol PreviewRenderer: Sendable {
    /// Readies `target` and makes it the one frames are drawn into; on the main
    /// thread, because the target is a view. A refused attach (it throws)
    /// leaves the previous target attached. A returned attach does not yet
    /// promise drawing: the kernel compiles afterwards on the `FrameExecutor`,
    /// and if that fails no target stays attached — the previous one is
    /// dropped too — so every frame completes undrawn until an attach whose
    /// kernel compiles. That failure reaches only `ErrorLog` (`.preview`).
    @MainActor
    func attach(_ target: any PreviewTargetHandle) throws
    /// Lets go of `target` when it is the one attached, so no frame is drawn
    /// into it after this call: the frame waiting for a draw completes undrawn,
    /// a draw already in flight finishes on its own, and every later `present`
    /// completes undrawn until the next attach. Any other target, or nothing
    /// attached, is a no-op. Not on the main thread: it hands the release to the
    /// `FrameExecutor`, the same place the frames are ordered.
    func detach(_ target: any PreviewTargetHandle)
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

    func detach(_ target: any PreviewTargetHandle) {
        reportIssue("PreviewRenderer.detach not implemented")
    }

    func present(_ frame: FrameRef, completion: @escaping @Sendable () -> Void) {
        reportIssue("PreviewRenderer.present not implemented")
        completion()
    }
}
