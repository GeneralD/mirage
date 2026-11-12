import Domain

/// Where an effect's clock starts, and the uniforms of one pass. Pure: no clock
/// is read, the time is the distance between two presentation times.
///
/// A session starts at the frame whose index is 0 — the pipeline counts its
/// passes from 0 again at every `start`, so each run is a session — or at the
/// first frame the runtime is handed when that one has another index. Every
/// other frame continues the session it finds. A session also carries the seed
/// its hash noise draws from, drawn once when the session starts.
public struct EffectSession: Sendable, Hashable {
    /// The presentation time of the session's first frame.
    public let start: HostTimestamp
    /// The seed of the session, 0 when none was drawn for it.
    public let seed: UInt32

    public init(start: HostTimestamp, seed: UInt32 = 0) {
        self.start = start
        self.seed = seed
    }

    /// The session `context` belongs to, given the one the previous frame was in. A session that
    /// starts here takes its seed from `drawingSeed`, which is called once and only then; a frame
    /// that continues `current` keeps `current`'s seed and draws nothing.
    public static func of(_ context: FrameContext, after current: EffectSession?, drawingSeed: () -> UInt32 = { 0 }) -> EffectSession {
        guard context.frameIndex != 0, let current else {
            return EffectSession(start: context.presentationTime, seed: drawingSeed())
        }
        return current
    }

    /// Seconds from the session's start to `presentationTime`: 0 at the start, never
    /// negative (a frame stamped before the start is at 0). The distance is taken in
    /// whole nanoseconds and converted once, so the only rounding is `Float`'s.
    public func time(at presentationTime: HostTimestamp) -> Float {
        guard presentationTime > start else { return 0 }
        return Float(Double(presentationTime.nanoseconds - start.nanoseconds) / 1_000_000_000)
    }
}

extension EffectUniforms {
    /// The uniforms of one pass: `time` in seconds since `session` started, the
    /// caller's `frameIndex`, the output surface's size in pixels as `resolution`
    /// (the pass's grid is rounded up to whole threadgroups, so it can overshoot
    /// `resolution` and a kernel bounds-checks its `gid`), and the session's `seed`,
    /// drawn once from `RandomSource` when the session starts (epic #14, D3).
    public static func pass(_ context: FrameContext, in session: EffectSession, output: SurfaceDescriptor) -> EffectUniforms {
        EffectUniforms(
            time: session.time(at: context.presentationTime),
            frameIndex: context.frameIndex,
            resolution: SIMD2(Float(output.width), Float(output.height)),
            seed: session.seed
        )
    }
}
