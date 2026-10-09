/// The engine's MSL prelude, prepended to every effect (`ShaderSourceAssembly`).
///
/// - `Uniforms` mirrors Entity `EffectUniforms` field for field (offsets
///   0 / 4 / 8 / 16, stride 24); the `static_assert` turns a drift on the MSL
///   side into a compile error of every effect, and `EntityTests` pins the
///   Swift side.
/// - `hash` and `noise` are pure functions of (coordinate, time, seed) with a
///   Swift twin, `HashNoiseReference` (Tests/TestSupport); the `hash-noise
///   parity` GPU suite proves the two agree. `hash` is integer arithmetic
///   down to a 24-bit value, so it is bit-exact on both sides; `noise` blends
///   hashes with IEEE adds and multiplies, so it agrees within one 8-bit step
///   (compile with `ShaderCompileOptions.precise`, the default).
/// - Internal helpers live in `namespace prelude` so they cannot collide with
///   an author's names; `hash`, `noise` and `Uniforms` are the public surface.
///   The prelude never defines the entry point.
public enum ShaderPrelude {
    public static let source = """
        #include <metal_stdlib>
        using namespace metal;

        // Buffer 0 of every effect kernel; mirrors EffectUniforms.
        struct Uniforms {
            float time;
            uint frameIndex;
            float2 resolution;
            uint seed;
        };
        static_assert(sizeof(Uniforms) == 24, "Uniforms must mirror EffectUniforms (stride 24)");

        namespace prelude {
            // One 32-bit avalanche round (lowbias32, C. Wellons).
            inline uint avalanche(uint x) {
                x ^= x >> 16;
                x *= 0x7feb352du;
                x ^= x >> 15;
                x *= 0x846ca68bu;
                x ^= x >> 16;
                return x;
            }
        }

        // White noise in [0, 1) with 24-bit resolution: a pure function of a lattice
        // cell, a discrete time step (frameIndex, or floor(time) as noise uses it) and the seed.
        inline float hash(uint2 cell, uint timeStep, uint seed) {
            uint h = prelude::avalanche(cell.x ^ prelude::avalanche(cell.y ^ prelude::avalanche(timeStep ^ prelude::avalanche(seed))));
            return float(h >> 8) * (1.0f / 16777216.0f);
        }

        namespace prelude {
            // Bilinear blend of the four lattice values around `cell` at one time step.
            inline float plane(uint2 cell, uint timeStep, uint seed, float2 w) {
                float v00 = hash(cell, timeStep, seed);
                float v10 = hash(cell + uint2(1, 0), timeStep, seed);
                float v01 = hash(cell + uint2(0, 1), timeStep, seed);
                float v11 = hash(cell + uint2(1, 1), timeStep, seed);
                float bottom = v00 + (v10 - v00) * w.x;
                float top = v01 + (v11 - v01) * w.x;
                return bottom + (top - bottom) * w.y;
            }
        }

        // Value noise in [0, 1]: smooth in p and in time, a pure function of (p, time, seed).
        // The lattice is the integer grid of p and of time; the weights are the cubic smoothstep.
        inline float noise(float2 p, float time, uint seed) {
            float2 base = floor(p);
            float baseTime = floor(time);
            float2 f = p - base;
            float ft = time - baseTime;
            float2 w = f * f * (3.0f - 2.0f * f);
            float wt = ft * ft * (3.0f - 2.0f * ft);
            uint2 cell = uint2(int2(base));
            uint timeStep = uint(int(baseTime));
            float now = prelude::plane(cell, timeStep, seed, w);
            float next = prelude::plane(cell, timeStep + 1u, seed, w);
            return now + (next - now) * wt;
        }

        """
}
