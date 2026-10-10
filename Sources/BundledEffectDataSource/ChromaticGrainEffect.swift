import Domain

/// The bundled effect: the red and blue channels drift sideways in opposite
/// directions and a fresh grain covers every frame.
///
/// - The drift is 1 to 4 pixels, from the prelude's `noise` over 64-pixel bands
///   down the frame and over `time` at half speed, so it wanders smoothly.
///   Red and blue are read at fractional columns, blended linearly between the
///   two nearest pixels and clamped to the edge, so the drift moves without
///   steps — and so the GPU and a Swift twin agree within one 8-bit step.
/// - The grain is the prelude's `hash` of the pixel and `frameIndex`, ±3 % of
///   full scale, added to every channel and clamped to [0, 1].
/// - The input is texture 0, the output texture 1, `Uniforms` buffer 0 (the
///   layout `GPURenderDataSource` binds). Alpha is written opaque.
///
/// The source is the author's part only: `ShaderCompilationDataSource` puts the
/// prelude (`Uniforms`, `hash`, `noise`) in front of it. The `MetalGateway smoke`
/// GPU suite compiles it and compares one pass with a Swift reference.
public enum ChromaticGrainEffect {
    public static let name = "Chromatic Grain"

    public static let source = """
        constant float driftBase = 1.0f;
        constant float driftRange = 3.0f;
        constant float driftBand = 64.0f;
        constant float driftRate = 0.5f;
        constant float grainAmount = 0.06f;

        // Row y of the image at a fractional column: the two nearest pixels blended
        // linearly, clamped to the edge.
        static float4 sampleRow(texture2d<float, access::read> image, float x, uint y) {
            float base = floor(x);
            float weight = x - base;
            int last = int(image.get_width()) - 1;
            float4 left = image.read(uint2(uint(clamp(int(base), 0, last)), y));
            float4 right = image.read(uint2(uint(clamp(int(base) + 1, 0, last)), y));
            return left + (right - left) * weight;
        }

        kernel void effect(texture2d<float, access::read> input [[texture(0)]],
                           texture2d<float, access::write> output [[texture(1)]],
                           constant Uniforms &uniforms [[buffer(0)]],
                           uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
            uint row = min(gid.y, input.get_height() - 1);
            float x = float(gid.x);
            float wander = noise(float2(0.0f, float(gid.y) / driftBand), uniforms.time * driftRate, uniforms.seed);
            float drift = driftBase + driftRange * wander;
            float red = sampleRow(input, x - drift, row).r;
            float green = sampleRow(input, x, row).g;
            float blue = sampleRow(input, x + drift, row).b;
            float grain = (hash(gid, uniforms.frameIndex, uniforms.seed) - 0.5f) * grainAmount;
            output.write(float4(saturate(float3(red, green, blue) + grain), 1.0f), gid);
        }

        """

    /// Compiled precise (fast math off), like every effect, so the prelude's noise
    /// matches its Swift twin.
    public static let effect = EffectSource(name: name, source: source, options: ShaderCompileOptions())
}
