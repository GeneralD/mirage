// Parameter Tour: tints the frame by its distance from `center`, so one parameter of every kind shows in
// one effect. `strength` caps how much tint is applied (0 leaves the frame as it is). `reach` scales the
// distance, so a larger reach brings the full tint nearer to `center`. `inverted` tints the near part
// instead of the far part. `tint` is the colour applied. `mode` picks the falloff: 0 (`Linear`) keeps the
// distance as it is, 1 (`Squared`) squares it, so the tint stays weak near `center` and gathers at the edge.
//
// The engine's prelude is compiled in front of this file, so `Uniforms` is already declared, and so is
// `Parameters`, generated from this package's manifest `parameters`: the author declares neither. The
// six parameters reach the shader as `float` (strength), `int` (reach), `uint` (inverted, a bool: 0 or 1),
// `float4` (tint, a colour), `float2` (center) and `uint` (mode, a choice: the index of the option).
// The input is texture 0, the output is texture 1, `Uniforms` is buffer 0 and `Parameters` is buffer 1.
// This file is only the kernel, which must be named `effect`.

kernel void effect(texture2d<float, access::read> input [[texture(0)]],
                   texture2d<float, access::write> output [[texture(1)]],
                   constant Uniforms &uniforms [[buffer(0)]],
                   constant Parameters &params [[buffer(1)]],
                   uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
    uint2 inside = min(gid, uint2(input.get_width() - 1, input.get_height() - 1));
    float3 source = input.read(inside).rgb;
    float2 position = (float2(gid) + 0.5f) / uniforms.resolution;
    float ramp = saturate(length(position - params.center) * float(params.reach) / 4.0f);
    float falloff = params.mode == 0u ? ramp : ramp * ramp;
    float weight = params.strength * (params.inverted != 0u ? 1.0f - falloff : falloff);
    output.write(float4(mix(source, source * params.tint.rgb, weight), 1.0f), gid);
}
