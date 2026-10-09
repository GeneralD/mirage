/// What an effect may know about the frame it is applied to. The uniform
/// `time` is derived from `presentationTime` against the session start by the
/// UseCase (`EffectUniforms`); the runtime never reads a clock.
public struct FrameContext: Sendable, Hashable {
    public let presentationTime: HostTimestamp
    public let frameIndex: UInt32

    public init(presentationTime: HostTimestamp, frameIndex: UInt32) {
        self.presentationTime = presentationTime
        self.frameIndex = frameIndex
    }
}

/// Failures at the preview boundary.
public enum PreviewError: Error, Sendable, Hashable {
    /// The target was not produced by this sink's gateway.
    case foreignTarget
}
