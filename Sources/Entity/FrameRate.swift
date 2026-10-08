/// Frames per second as a whole number; the extension declares one fixed rate.
public struct FrameRate: Sendable, Hashable {
    public let framesPerSecond: Int

    public init(framesPerSecond: Int) {
        precondition(framesPerSecond > 0, "frame rate must be positive")
        self.framesPerSecond = framesPerSecond
    }
}

extension FrameRate {
    public static let standard = FrameRate(framesPerSecond: 30)

    public var frameDuration: Duration { .seconds(1) / framesPerSecond }

    /// The presentation time of slate frame `index` after `base`
    /// (`base + index × frameDuration`), so synthesized frames never depend on
    /// a clock reading per frame.
    public func slateTime(base: HostTimestamp, index: Int) -> HostTimestamp {
        base.advanced(by: frameDuration * index)
    }
}
