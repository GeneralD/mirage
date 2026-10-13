/// The uniforms every effect kernel receives at buffer index 0. The layout is
/// fixed and mirrored by the MSL `Uniforms` struct the prelude declares
/// (`ShaderCompilationDataSource`):
///
/// ```metal
/// struct Uniforms { float time; uint frameIndex; float2 resolution; uint seed; };
/// ```
///
/// Offsets 0 / 4 / 8 / 16, stride 24 on both sides (`float2` is 8-aligned);
/// `EntityTests` pins them. `time` is seconds: PTS minus the session start
/// (`EffectSession`). `resolution` is the output surface's size in pixels; the
/// pass's grid is rounded up to whole threadgroups (`DispatchGrid.covering`), so it
/// can overshoot it and a kernel bounds-checks its `gid`. `seed` is what the
/// hash-noise helpers consume: 0 until a `RandomSource` exists (MVP-C).
public struct EffectUniforms: Sendable, Hashable {
    public let time: Float
    public let frameIndex: UInt32
    public let resolution: SIMD2<Float>
    public let seed: UInt32

    public init(time: Float, frameIndex: UInt32, resolution: SIMD2<Float>, seed: UInt32) {
        self.time = time
        self.frameIndex = frameIndex
        self.resolution = resolution
        self.seed = seed
    }
}
