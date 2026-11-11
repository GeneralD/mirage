// Tint: blends the frame towards a colour of your choice. `amount` 0 does nothing, and 1 multiplies
// every pixel by `tint`, so the whole frame takes on that colour; in between, the two are mixed.
//
// The engine's prelude is compiled in front of this file, so `Uniforms` is already declared, and so is
// `Parameters`, generated from this package's manifest `parameters`: the author declares neither. The
// input is texture 0, the output is texture 1, `Uniforms` is buffer 0 and `Parameters` is buffer 1.
// This file is only the kernel, which must be named `effect`.

kernel void effect(texture2d<float, access::read> input [[texture(0)]],
                   texture2d<float, access::write> output [[texture(1)]],
                   constant Uniforms &uniforms [[buffer(0)]],
                   constant Parameters &params [[buffer(1)]],
                   uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
    uint2 inside = min(gid, uint2(input.get_width() - 1, input.get_height() - 1));
    float3 source = input.read(inside).rgb;
    output.write(float4(mix(source, source * params.tint.rgb, params.amount), 1.0f), gid);
}
