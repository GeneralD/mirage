import Dependencies
import Domain

/// Resolves a `FrameRef`'s lease to its surface and hands it to the stream.
/// The caller still owns the lease and releases it after `send`.
public struct StreamOutputRepositoryImpl: Sendable {
    @Dependency(\.streamOutput) private var streamOutput
    @Dependency(\.surfacePool) private var surfacePool
    @Dependency(\.errorLog) private var errorLog

    public init() {}
}

extension StreamOutputRepositoryImpl: StreamOutputRepository {
    public func start(
        descriptor: SurfaceDescriptor,
        frameRate: FrameRate,
        onEvent: @escaping @Sendable (StreamOutputEvent) -> Void
    ) throws {
        try streamOutput.start(descriptor: descriptor, frameRate: frameRate, onEvent: onEvent)
    }

    public var isStreaming: Bool { streamOutput.isStreaming }

    public func send(_ frame: FrameRef) -> SendOutcome {
        guard let handle = surfacePool.handle(for: frame.token) else {
            errorLog.record(.stream, "frame dropped: surface token \(frame.token) no longer resolves")
            return .dropped(.staleToken)
        }
        return streamOutput.send(handle, descriptor: frame.descriptor, presentationTime: frame.presentationTime)
    }
}
