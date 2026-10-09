import Dependencies
import Domain

/// The host's preview sink: a pass-through to `PreviewDataSource`, which owns
/// the draw order, the kernel and the surface binding. It exists to keep the
/// layer chain adjacent (UseCase → Repository → DataSource); a preview policy
/// that is not about drawing (say, pausing while the window is hidden) would
/// belong here.
public struct PreviewRepositoryImpl: Sendable {
    @Dependency(\.previewRenderer) private var renderer

    public init() {}
}

extension PreviewRepositoryImpl: PreviewSink {
    @MainActor
    public func attach(_ target: any PreviewTargetHandle) throws {
        try renderer.attach(target)
    }

    public func present(_ frame: FrameRef, completion: @escaping @Sendable () -> Void) {
        renderer.present(frame, completion: completion)
    }
}
