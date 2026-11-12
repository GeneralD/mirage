import Domain

/// The bundled duotone: each pixel's brightness picks a colour between the `shadows` and `highlights`
/// colours, and `amount` mixes that colour with the pixel itself.
///
/// - Brightness is the sRGB values weighted by Rec.709's luma weights (0.2126, 0.7152, 0.0722), with no
///   linearisation first, so the mix happens in the same space as the input.
/// - `amount` 0 leaves the input as it is, 1 gives the two colours alone.
/// - The input is texture 0, the output texture 1, `Uniforms` buffer 0 and the parameter block buffer 1
///   (the layout `GPURenderDataSource` binds and `EffectParameterLayout` gives). Alpha is written opaque.
///
/// The source is the author's part only: `ShaderCompilationDataSource` puts the prelude and the
/// `Parameters` struct in front of it. The `Duotone smoke` GPU suite compiles it and compares every pixel
/// of one pass with `DuotoneReference`.
public enum DuotoneEffect {
    public static let name = "Duotone"

    public static let source = """
        constant float3 lumaWeights = float3(0.2126f, 0.7152f, 0.0722f);

        kernel void effect(texture2d<float, access::read> input [[texture(0)]],
                           texture2d<float, access::write> output [[texture(1)]],
                           constant Uniforms &uniforms [[buffer(0)]],
                           constant Parameters &params [[buffer(1)]],
                           uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
            uint2 inside = min(gid, uint2(input.get_width() - 1, input.get_height() - 1));
            float3 source = input.read(inside).rgb;
            float3 toned = mix(params.shadows.rgb, params.highlights.rgb, dot(source, lumaWeights));
            output.write(float4(mix(source, toned, params.amount), 1.0f), gid);
        }

        """

    public static let parameters: [EffectParameterSpec] = [
        EffectParameterSpec(id: "shadows", label: "Shadows", kind: .color(defaultValue: SIMD4<Float>(0.05, 0.05, 0.25, 1))),
        EffectParameterSpec(id: "highlights", label: "Highlights", kind: .color(defaultValue: SIMD4<Float>(1, 0.85, 0.5, 1))),
        EffectParameterSpec(id: "amount", label: "Amount", kind: .float(min: 0, max: 1, step: 0.05, defaultValue: 1)),
    ]

    /// Compiled precise (fast math off), like every effect, so the GPU's arithmetic matches the Swift reference.
    public static let effect = EffectSource(name: name, source: source, options: ShaderCompileOptions(), parameters: parameters)
}
