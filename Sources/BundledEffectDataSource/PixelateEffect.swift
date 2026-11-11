import Domain

/// The bundled pixelate effect: the frame is cut into `blockSize` × `blockSize` blocks, and each block
/// takes the colour of its centre pixel, clamped to the last pixel of the input. Nearest-neighbour only,
/// so every output pixel is an input pixel and the GPU matches `PixelateReference` exactly.
///
/// - The input is texture 0, the output texture 1, `Uniforms` buffer 0 and `Parameters` buffer 1 (the
///   layout `GPURenderDataSource` binds). `blockSize` is an `int`, read as `uint(max(…, 1))` so a value
///   below 1 cannot divide by zero. Alpha is written opaque.
/// - The source is the author's part only: `ShaderCompilationDataSource` puts the prelude and the
///   generated `Parameters` struct in front of it.
public enum PixelateEffect {
    public static let name = "Pixelate"

    public static let source = """
        kernel void effect(texture2d<float, access::read> input [[texture(0)]],
                           texture2d<float, access::write> output [[texture(1)]],
                           constant Uniforms &uniforms [[buffer(0)]],
                           constant Parameters &params [[buffer(1)]],
                           uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
            uint size = uint(max(params.blockSize, 1));
            uint2 middle = (gid / size) * size + size / 2;
            uint2 inside = min(middle, uint2(input.get_width() - 1, input.get_height() - 1));
            output.write(float4(input.read(inside).rgb, 1.0f), gid);
        }

        """

    /// The one knob: the side of a block in pixels, `[1, 64]`, default 8.
    public static let parameters: [EffectParameterSpec] = [
        EffectParameterSpec(id: "blockSize", label: "Block Size", kind: .int(min: 1, max: 64, defaultValue: 8))
    ]

    /// Compiled precise under the entry point `effect`, like every bundled effect.
    public static let effect = EffectSource(name: name, source: source, options: ShaderCompileOptions(), parameters: parameters)
}
