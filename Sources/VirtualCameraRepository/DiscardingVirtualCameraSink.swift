import Domain

/// **Development only.** A `VirtualCameraSink` for a process that has no virtual
/// camera to send to: it reports every frame as sent and keeps none of them. The dev
/// harness (`swift run dev-harness`) runs the host pipeline without the System
/// Extension, so it swaps this in for `VirtualCameraRepositoryImpl` (epic #14, D13).
/// The shipped app never does: the host's live value stays `VirtualCameraRepositoryImpl`.
///
/// It lives here, beside the real sink, rather than in the harness so that it is
/// covered and tested like the rest of the sink's module; it is not a test double,
/// which stay in `Tests/TestDoubles` and are never referenced from `Sources/`.
///
/// `connect()` returns at once, so the pipeline settles to `.connected` and counts a
/// frame as sent (`frames=<n>` in its summary) instead of dropping it as
/// `.notConnected`. The sink emits no transport event: nothing connected to anything,
/// and the pipeline's "connected to the extension" line would say otherwise.
/// The lease stays the caller's, as with every sink; nothing here resolves a token.
public struct DiscardingVirtualCameraSink: Sendable {
    public init() {}
}

extension DiscardingVirtualCameraSink: VirtualCameraSink {
    public func connect() async throws {}

    public func disconnect() {}

    public func send(_ frame: FrameRef) -> SendOutcome {
        .sent
    }

    public func observe(_ onEvent: @escaping @Sendable (FrameTransportEvent) -> Void) {}
}
