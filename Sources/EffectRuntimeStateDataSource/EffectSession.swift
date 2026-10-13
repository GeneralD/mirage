import Domain

/// Where an effect's clock starts, and the uniforms of one pass. Pure: no clock
/// is read, the time is the distance between two presentation times.
///
/// A session starts at the frame whose index is 0 — the pipeline counts its
/// passes from 0 again at every `start`, so each run is a session — or at the
/// first frame the runtime is handed when that one has another index. Every
/// other frame continues the session it finds.
public struct EffectSession: Sendable, Hashable {
    /// The presentation time of the session's first frame.
    public let start: HostTimestamp

    public init(start: HostTimestamp) {
        self.start = start
    }

    /// The session `context` belongs to, given the one the previous frame was in.
    public static func of(_ context: FrameContext, after current: EffectSession?) -> EffectSession {
        guard context.frameIndex != 0, let current else { return EffectSession(start: context.presentationTime) }
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
    /// (the pass's grid covers it, so a kernel's `gid` runs over `[0, resolution)`),
    /// and seed 0 — there is no `RandomSource` before MVP-C (epic #14, D3).
    public static func pass(_ context: FrameContext, in session: EffectSession, output: SurfaceDescriptor) -> EffectUniforms {
        EffectUniforms(
            time: session.time(at: context.presentationTime),
            frameIndex: context.frameIndex,
            resolution: SIMD2(Float(output.width), Float(output.height)),
            seed: 0
        )
    }
}
