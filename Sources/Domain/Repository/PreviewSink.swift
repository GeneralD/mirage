import Dependencies

/// The view the preview frames go to (live: the `MTKView` that `PreviewView`
/// creates; `PreviewGateway.prepare` turns it into the layer it draws into), in
/// the shape of the other handles: `backing` is the OS object as `AnyObject`,
/// the gateway that consumes it casts it back and throws
/// `PreviewError.foreignTarget` for anything else.
public protocol PreviewTargetHandle: AnyObject, Sendable {
    var backing: AnyObject { get }
}

/// Where the host shows frames to its own user. `present` borrows the frame's
/// surface until `completion` runs — exactly once, on any thread, and possibly
/// before `present` itself returns — and the caller releases the lease
/// afterwards; a sink that is slower than the camera is visible to the pipeline
/// as completions that lag. Until a target is attached every frame completes at
/// once, undrawn. `attach` runs on the main thread, because the target is a
/// view; returning from it does not promise drawing — a preview kernel that
/// fails to compile afterwards leaves no target attached (logged, not thrown),
/// and frames complete at once again. The live value is `PreviewRepositoryImpl`
/// over `PreviewDataSource`.
public protocol PreviewSink: Sendable {
    @MainActor
    func attach(_ target: any PreviewTargetHandle) throws
    func present(_ frame: FrameRef, completion: @escaping @Sendable () -> Void)
}

public enum PreviewSinkKey: TestDependencyKey {
    public static let testValue: any PreviewSink = UnimplementedPreviewSink()
}

extension DependencyValues {
    public var previewSink: any PreviewSink {
        get { self[PreviewSinkKey.self] }
        set { self[PreviewSinkKey.self] = newValue }
    }
}

private struct UnimplementedPreviewSink: PreviewSink {
    func attach(_ target: any PreviewTargetHandle) throws {
        reportIssue("PreviewSink.attach not implemented")
        throw PreviewError.foreignTarget
    }

    func present(_ frame: FrameRef, completion: @escaping @Sendable () -> Void) {
        reportIssue("PreviewSink.present not implemented")
        completion()
    }
}
