// Ripple: horizontal bands of the frame sway sideways like heat haze, each by its own
// amount that drifts with time.
//
// The engine's prelude is compiled in front of this file, so `Uniforms`, `hash` and `noise`
// are already declared, with `<metal_stdlib>` and `using namespace metal;`. This file is only
// the kernel, which must be named `effect`. Textures: 0 is the camera frame, 1 the output.

constant float maxSway = 8.0f;      // pixels, to either side
constant float bandHeight = 48.0f;  // rows that sway together
constant float driftRate = 0.6f;    // noise steps per second

kernel void effect(texture2d<float, access::read> input [[texture(0)]],
                   texture2d<float, access::write> output [[texture(1)]],
                   constant Uniforms &uniforms [[buffer(0)]],
                   uint2 gid [[thread_position_in_grid]]) {
    // The grid is rounded up to whole threadgroups: stay inside the output.
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }

    // `noise` is smooth in the band and in time, so neighbouring bands sway alike and no band jumps.
    float band = float(gid.y) / bandHeight;
    float sway = (noise(float2(band, 0.0f), uniforms.time * driftRate, uniforms.seed) - 0.5f) * 2.0f * maxSway;

    // Read from the shifted column, clamped to the frame's edge.
    int lastColumn = int(input.get_width()) - 1;
    uint column = uint(clamp(int(gid.x) + int(round(sway)), 0, lastColumn));
    uint row = min(gid.y, input.get_height() - 1);
    output.write(float4(input.read(uint2(column, row)).rgb, 1.0f), gid);
}
