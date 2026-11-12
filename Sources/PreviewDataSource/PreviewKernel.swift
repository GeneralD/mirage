import Domain

/// The preview's kernels. The blit (`source`) scales the frame into the drawable keeping its
/// aspect ratio, bilinearly, with opaque black bars around it. The binding is
/// `PreviewGateway.draw`'s convention — the frame at texture 0, the drawable at
/// texture 1, whole threadgroups that overshoot the drawable — so the kernel
/// bounds-checks `gid` before anything else. Compiled once per attach through
/// `ShaderLibraryGateway`, whose handle is this kernel's compute pipeline state.
enum PreviewKernel {
    /// A scaling blit needs no bit-exact math, so fast math stays on.
    static let options = ShaderCompileOptions(entryPoint: "previewBlit", precise: false)

    static let source = """
        #include <metal_stdlib>
        using namespace metal;

        kernel void previewBlit(texture2d<float, access::sample> frame [[texture(0)]],
                                texture2d<float, access::write> drawable [[texture(1)]],
                                uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= drawable.get_width() || gid.y >= drawable.get_height()) { return; }
            float2 target = float2(drawable.get_width(), drawable.get_height());
            float2 source = float2(frame.get_width(), frame.get_height());
            float2 fitted = source * min(target.x / source.x, target.y / source.y);
            float2 uv = (float2(gid) + 0.5 - (target - fitted) * 0.5) / fitted;
            constexpr sampler bilinear(coord::normalized, address::clamp_to_edge, filter::linear);
            bool inside = all(uv >= 0.0) && all(uv <= 1.0);
            drawable.write(inside ? frame.sample(bilinear, uv, level(0)) : float4(0.0, 0.0, 0.0, 1.0), gid);
        }
        """

    /// The before / after split: the original on the left of a two-pixel white
    /// rule at the centre, the frame on the right, both under the blit's aspect
    /// fit. Its own source and options, so `source` and `options` keep their text
    /// and compile key. Fast math stays on for the same reason as the blit's.
    static let splitOptions = ShaderCompileOptions(entryPoint: "previewSplit", precise: false)

    /// The four fit lines are copied from `source`, not shared through an
    /// interpolation, because a shared string would change `source`'s text; the
    /// PreviewKernelTests pin that the copies match.
    static let splitSource = """
        #include <metal_stdlib>
        using namespace metal;

        kernel void previewSplit(texture2d<float, access::sample> frame [[texture(0)]],
                                 texture2d<float, access::write> drawable [[texture(1)]],
                                 texture2d<float, access::sample> original [[texture(2)]],
                                 uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= drawable.get_width() || gid.y >= drawable.get_height()) { return; }
            float2 target = float2(drawable.get_width(), drawable.get_height());
            float2 source = float2(frame.get_width(), frame.get_height());
            float2 fitted = source * min(target.x / source.x, target.y / source.y);
            float2 uv = (float2(gid) + 0.5 - (target - fitted) * 0.5) / fitted;
            constexpr sampler bilinear(coord::normalized, address::clamp_to_edge, filter::linear);
            bool inside = all(uv >= 0.0) && all(uv <= 1.0);
            float4 color;
            if (!inside) {
                color = float4(0.0, 0.0, 0.0, 1.0);
            } else if (abs(uv.x - 0.5) * fitted.x < 1.0) {
                color = float4(1.0, 1.0, 1.0, 1.0);
            } else if (uv.x < 0.5) {
                color = original.sample(bilinear, uv, level(0));
            } else {
                color = frame.sample(bilinear, uv, level(0));
            }
            drawable.write(color, gid);
        }
        """
}
