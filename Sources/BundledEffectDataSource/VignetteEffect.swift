import Domain

/// The bundled vignette: the picture darkens toward its corners past a radius.
///
/// - Distance from the centre is measured in half-heights (the centre is 0, the
///   top and bottom edges are 1), so the falloff stays round at any aspect ratio.
/// - Past `radius` the colour falls off smoothly and is darkest at
///   `radius + featherWidth`, where RGB is multiplied by `1 - strength`.
/// - The two parameters are `strength` (0 to 1) and `radius` (0.2 to 1.5). The
///   `Parameters` struct is generated from `parameters` (`strength` at 0, `radius`
///   at 4, stride 8), so the source never defines it.
/// - The input is texture 0, the output texture 1, `Uniforms` buffer 0 and the
///   parameters buffer 1. Alpha is written opaque.
///
/// The source is the author's part only: `ShaderCompilationDataSource` puts the
/// prelude and the `Parameters` struct in front of it. The `Vignette smoke` GPU
/// suite compares one pass with `VignetteReference`.
public enum VignetteEffect {
    public static let name = "Vignette"

    public static let source = """
        constant float featherWidth = 0.5f;  // from the clear centre to the full edge, in half-heights

        kernel void effect(texture2d<float, access::read> input [[texture(0)]],
                           texture2d<float, access::write> output [[texture(1)]],
                           constant Uniforms &uniforms [[buffer(0)]],
                           constant Parameters &params [[buffer(1)]],
                           uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
            float2 centered = (float2(gid) + 0.5f - 0.5f * uniforms.resolution) / (0.5f * uniforms.resolution.y);
            float edge = smoothstep(params.radius, params.radius + featherWidth, length(centered));
            uint2 inside = min(gid, uint2(input.get_width() - 1, input.get_height() - 1));
            float3 color = input.read(inside).rgb * (1.0f - params.strength * edge);
            output.write(float4(color, 1.0f), gid);
        }

        """

    public static let parameters: [EffectParameterSpec] = [
        EffectParameterSpec(id: "strength", label: "Strength", kind: .float(min: 0, max: 1, step: 0.05, defaultValue: 0.5)),
        EffectParameterSpec(id: "radius", label: "Radius", kind: .float(min: 0.2, max: 1.5, step: 0.05, defaultValue: 0.8)),
    ]

    /// Compiled precise (fast math off) under the entry point `effect`, like every effect, so the
    /// smoke suite's Swift twin agrees within one 8-bit step.
    public static let effect = EffectSource(name: name, source: source, options: ShaderCompileOptions(), parameters: parameters)
}
