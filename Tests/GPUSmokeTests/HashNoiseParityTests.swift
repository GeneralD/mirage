import Domain
import IOSurfaceGateway
import MetalGateway
import ShaderCompilationDataSource
import TestSupport
import Testing

/// The prelude's `hash` and `noise` on the real GPU against `HashNoiseReference`
/// in Swift, on every pixel of a 256 × 256 image, for seed 0 and for another
/// seed. The kernels are compiled with the prelude exactly as an effect is
/// (`ShaderSourceAssembly`), with `ShaderCompileOptions.precise` (the default):
/// fast math off.
@Suite("hash-noise parity", .serialized, .enabled(if: MetalDeviceProbe.isAvailable), .timeLimit(.minutes(1)))
struct HashNoiseParityTests {
    private let gateway = MetalGatewayImpl()
    private let surfaces = IOSurfaceGatewayImpl()
    private static let descriptor = SurfaceDescriptor.bgra(width: 256, height: 256)
    private static let seeds: [UInt32] = [0, 0x5EED_1234]

    /// R is `hash` of the pixel at `frameIndex` (the integer path, and the
    /// `frameIndex` uniform); G is `noise` over 16-pixel cells at a fractional
    /// `time`; B is `noise` at negative, non-aligned coordinates and a faster time
    /// with a derived seed, so negative lattice cells wrap the same way on both
    /// sides. A is opaque.
    private static let fieldEffect = """
        kernel void effect(texture2d<float, access::write> out [[texture(0)]], constant Uniforms &u [[buffer(0)]],
                           uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
            float white = hash(gid, u.frameIndex, u.seed);
            float coarse = noise(float2(gid) / 16.0f, u.time, u.seed);
            float shifted = noise(float2(gid) * 0.37f - 40.0f, u.time * 2.5f, u.seed ^ 0x9e3779b9u);
            out.write(float4(white, coarse, shifted, 1.0f), gid);
        }
        """

    /// The 24 bits of `hash`, one byte per channel (R low, G middle, B high), each
    /// stored as `k / 255` — a value the unorm store returns as `k` exactly — so the
    /// hash is compared bit for bit, not through the rounding of one 8-bit store.
    private static let bitsEffect = """
        kernel void effect(texture2d<float, access::write> out [[texture(0)]], constant Uniforms &u [[buffer(0)]],
                           uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
            uint bits = uint(hash(gid, u.frameIndex, u.seed) * 16777216.0f);
            out.write(float4(float(bits & 0xffu), float((bits >> 8) & 0xffu), float(bits >> 16), 255.0f) / 255.0f, gid);
        }
        """

    /// `fieldEffect` for one pixel, as `[B, G, R, A]` bytes rounded the way the unorm store rounds.
    private static func field(x: Int, y: Int, uniforms: EffectUniforms) -> [UInt8] {
        let (fx, fy) = (Float(x), Float(y))
        let white = HashNoiseReference.hash(x: UInt32(x), y: UInt32(y), timeStep: uniforms.frameIndex, seed: uniforms.seed)
        let coarse = HashNoiseReference.noise(x: fx / 16, y: fy / 16, time: uniforms.time, seed: uniforms.seed)
        let shifted = HashNoiseReference.noise(
            x: fx * 0.37 - 40, y: fy * 0.37 - 40, time: uniforms.time * 2.5, seed: uniforms.seed ^ 0x9e37_79b9)
        return [shifted, coarse, white, 1].map { UInt8(clamping: Int(($0 * 255).rounded())) }
    }

    /// `bitsEffect` for one pixel, as `[B, G, R, A]` bytes.
    private static func bits(x: Int, y: Int, uniforms: EffectUniforms) -> [UInt8] {
        let hash = HashNoiseReference.hash(x: UInt32(x), y: UInt32(y), timeStep: uniforms.frameIndex, seed: uniforms.seed)
        let value = UInt32(hash * 16_777_216)
        return [UInt8(value >> 16), UInt8((value >> 8) & 0xff), UInt8(value & 0xff), 255]
    }

    private static func uniforms(seed: UInt32) -> EffectUniforms {
        EffectUniforms(time: 3.25, frameIndex: 7, resolution: SIMD2(Float(descriptor.width), Float(descriptor.height)), seed: seed)
    }

    /// Compiles `effect` with the prelude, runs it once over a fresh surface and reads the surface back.
    private func render(_ effect: String, uniforms: EffectUniforms) async throws -> SurfacePixels {
        let context = try gateway.makeContext()
        let kernel = try gateway.compile(source: ShaderSourceAssembly.assemble(effect), options: ShaderCompileOptions(), on: context).get()
        let surface = try surfaces.create(Self.descriptor)
        let texture = try gateway.bind(surface, on: context)
        let grid = DispatchGrid.covering(width: Self.descriptor.width, height: Self.descriptor.height)
        let completion = try await GPUSmokeSupport.run(
            ComputePass(kernel: kernel, textures: [texture], uniforms: uniforms, grid: grid), on: context, through: gateway)
        #expect(completion.error == nil)
        try gateway.unbind(texture)
        return try GPUSmokeSupport.pixels(of: surface)
    }

    /// Every pixel's largest channel difference from `reference`, row by row.
    private static func distances(_ image: SurfacePixels, _ reference: (Int, Int) -> [UInt8]) -> [Int] {
        (0..<descriptor.height).flatMap { y in
            (0..<descriptor.width).map { x in GPUSmokeSupport.distance(image.pixel(x: x, y: y), reference(x, y)) }
        }
    }

    @Test("hash and noise match the Swift reference within one 8-bit step on every pixel", arguments: seeds)
    func fieldMatchesReference(seed: UInt32) async throws {
        let uniforms = Self.uniforms(seed: seed)
        let image = try await render(Self.fieldEffect, uniforms: uniforms)

        let distances = Self.distances(image) { Self.field(x: $0, y: $1, uniforms: uniforms) }
        let outside = distances.filter { $0 > GPUSmokeSupport.tolerance }.count
        #expect(outside == 0, "\(outside) pixels outside the tolerance; worst channel difference \(distances.max() ?? 0)")
        // A field that ignored its inputs would still be within tolerance of itself; it must vary.
        #expect(Set((0..<64).map { image.pixel(x: $0, y: 0)[2] }).count > 32, "hash looks constant")
        #expect(Set((0..<256).map { image.pixel(x: $0, y: 0)[1] }).count > 16, "noise looks constant")
    }

    @Test("hash is bit-exact: its 24 bits equal the Swift reference's on every pixel", arguments: seeds)
    func hashIsBitExact(seed: UInt32) async throws {
        let uniforms = Self.uniforms(seed: seed)
        let image = try await render(Self.bitsEffect, uniforms: uniforms)

        let differing = Self.distances(image) { Self.bits(x: $0, y: $1, uniforms: uniforms) }.filter { $0 != 0 }.count
        #expect(differing == 0, "\(differing) pixels whose hash bits differ")
    }
}
