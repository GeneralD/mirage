import Domain

/// The preview with no window: accepts any target and completes every frame at
/// once, so the pipeline's lease bookkeeping runs unchanged without a drawable.
/// Registered as the host's live value until the real sink lands in this
/// module (#20; epic #14, D18).
public struct DiscardingPreviewSink: PreviewSink, Sendable {
    public init() {}

    public func attach(_ target: any PreviewTargetHandle) throws {}

    public func present(_ frame: FrameRef, completion: @escaping @Sendable () -> Void) {
        completion()
    }
}
