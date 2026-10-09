import Domain
import IOSurface
import IOSurfaceGateway
import MetalGateway
import TestDoubles
import Testing

/// The one suite that drives `MetalGateway` against a real device: runtime
/// compile through `ShaderLibraryGateway`, one compute pass through
/// `GPUGateway`, and an IOSurface-backed texture through `TextureCacheGateway`,
/// read back on the CPU and compared with a Swift reference under a single
/// fixed tolerance. Everything that decides (cache, completion mapping,
/// in-flight cap) is tested against the fakes and never needs a GPU.
///
/// `mac2` only: whole threadgroups, bounds-checked kernels, no Apple-family
/// features. The kernels are plain fills, so nothing here can hang or fault.
/// The MSL `Uniforms` declaration is inlined because the prelude that will
/// carry it belongs to `ShaderCompilationDataSource`.
@Suite("MetalGateway smoke", .serialized, .enabled(if: MetalDeviceProbe.isAvailable), .timeLimit(.minutes(1)))
struct MetalGatewaySmokeTests {
    private let gateway = MetalGatewayImpl()
    private let surfaces = IOSurfaceGatewayImpl()
    private static let descriptor = SurfaceDescriptor.bgra(width: 256, height: 256)
    /// One 8-bit step: the GPU rounds the unorm store, the reference rounds in Swift.
    private static let tolerance = 1

    private static let header = """
        #include <metal_stdlib>
        using namespace metal;
        struct Uniforms { float time; uint frameIndex; float2 resolution; uint seed; };

        """

    /// Every pixel becomes B G R A = 64 128 255 255.
    private static let fillSource =
        header + """
            kernel void effect(texture2d<float, access::write> out [[texture(0)]], constant Uniforms &u [[buffer(0)]],
                               uint2 gid [[thread_position_in_grid]]) {
                if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
                out.write(float4(1.0, 0.5, 0.25, 1.0), gid);
            }
            """

    /// `r = x / (w - 1)`, `g = y / (h - 1)`, `b = fract(time)`, `a = (seed % 256) / 255` — mirrored by `reference`.
    private static let gradientSource =
        header + """
            kernel void effect(texture2d<float, access::write> out [[texture(0)]], constant Uniforms &u [[buffer(0)]],
                               uint2 gid [[thread_position_in_grid]]) {
                if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
                float2 uv = float2(gid) / (u.resolution - 1.0);
                out.write(float4(uv.x, uv.y, fract(u.time), float(u.seed % 256u) / 255.0), gid);
            }
            """

    private static func reference(x: Int, y: Int, uniforms: EffectUniforms) -> [UInt8] {
        let r = Float(x) / (uniforms.resolution.x - 1)
        let g = Float(y) / (uniforms.resolution.y - 1)
        let b = uniforms.time - uniforms.time.rounded(.down)
        let a = Float(uniforms.seed % 256) / 255
        return [b, g, r, a].map { UInt8(clamping: Int(($0 * 255).rounded())) }
    }

    private static func uniforms(time: Float = 0, seed: UInt32 = 0) -> EffectUniforms {
        EffectUniforms(time: time, frameIndex: 0, resolution: SIMD2(Float(descriptor.width), Float(descriptor.height)), seed: seed)
    }

    /// Row-major BGRA bytes of the surface plus its stride, read under a read lock after the GPU is done.
    private static func pixels(of surface: any SurfaceHandle) throws -> (bytes: [UInt8], stride: Int) {
        let raw = try #require(surface.backing as? IOSurface)
        IOSurfaceLock(raw, .readOnly, nil)
        defer { IOSurfaceUnlock(raw, .readOnly, nil) }
        let base = IOSurfaceGetBaseAddress(raw).assumingMemoryBound(to: UInt8.self)
        return (Array(UnsafeBufferPointer(start: base, count: IOSurfaceGetAllocSize(raw))), IOSurfaceGetBytesPerRow(raw))
    }

    private static func pixel(_ image: (bytes: [UInt8], stride: Int), x: Int, y: Int) -> [UInt8] {
        (0..<4).map { image.bytes[y * image.stride + x * 4 + $0] }
    }

    private func compile(_ source: String) throws -> (any LibraryHandle, any GPUContextHandle) {
        let context = try gateway.makeContext()
        return (try gateway.compile(source: source, options: ShaderCompileOptions(), on: context).get(), context)
    }

    /// The completion handler is the only clock: no sleeps, no polling.
    private func run(_ pass: ComputePass, on context: any GPUContextHandle) async throws -> GPUCompletion {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try gateway.encodeAndCommit(pass, on: context) { continuation.resume(returning: $0) }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    @Test("a kernel compiled from source fills an IOSurface-backed texture through one compute pass")
    func compileBindDispatch() async throws {
        let (kernel, context) = try compile(Self.fillSource)
        let surface = try surfaces.create(Self.descriptor)
        let texture = try gateway.bind(surface, on: context)

        let grid = DispatchGrid.covering(width: Self.descriptor.width, height: Self.descriptor.height)
        let completion = try await run(ComputePass(kernel: kernel, textures: [texture], uniforms: Self.uniforms(), grid: grid), on: context)
        #expect(completion.error == nil)
        #expect(completion.gpuEnd >= completion.gpuStart)

        let image = try Self.pixels(of: surface)
        let offPixels = (0..<Self.descriptor.height).flatMap { y in
            (0..<Self.descriptor.width).filter { x in Self.pixel(image, x: x, y: y) != [64, 128, 255, 255] }
        }
        #expect(offPixels.isEmpty, "\(offPixels.count) pixels differ from the fill")
        try gateway.unbind(texture)
    }

    /// Width 6 is not a multiple of four, so `width * 4` asks for 24-byte rows; Metal aborts the process when
    /// an IOSurface texture's rows are not 16-byte aligned, so this only passes when `IOSurfaceGateway.create`
    /// aligned the stride.
    @Test("a surface whose width is not a multiple of four binds, fills through its padded rows and unbinds")
    func widthNotMultipleOfFourSurfaceBinds() async throws {
        let (kernel, context) = try compile(Self.fillSource)
        let unaligned = SurfaceDescriptor.bgra(width: 6, height: 4)
        let surface = try surfaces.create(unaligned)
        let texture = try gateway.bind(surface, on: context)

        let grid = DispatchGrid.covering(width: unaligned.width, height: unaligned.height)
        let completion = try await run(ComputePass(kernel: kernel, textures: [texture], uniforms: Self.uniforms(), grid: grid), on: context)
        #expect(completion.error == nil)

        let image = try Self.pixels(of: surface)
        let offPixels = (0..<unaligned.height).flatMap { y in
            (0..<unaligned.width).filter { x in Self.pixel(image, x: x, y: y) != [64, 128, 255, 255] }
        }
        #expect(offPixels.isEmpty, "\(offPixels.count) pixels differ from the fill at stride \(image.stride)")
        try gateway.unbind(texture)
    }

    @Test("uniforms reach the kernel and the output matches the Swift reference within one 8-bit step")
    func gradientMatchesReference() async throws {
        let (kernel, context) = try compile(Self.gradientSource)
        let surface = try surfaces.create(Self.descriptor)
        let texture = try gateway.bind(surface, on: context)
        let uniforms = Self.uniforms(time: 3.25, seed: 0x1_0040)

        let grid = DispatchGrid.covering(width: Self.descriptor.width, height: Self.descriptor.height)
        let completion = try await run(ComputePass(kernel: kernel, textures: [texture], uniforms: uniforms, grid: grid), on: context)
        #expect(completion.error == nil)

        let image = try Self.pixels(of: surface)
        let worst =
            (0..<Self.descriptor.height).flatMap { y in
                (0..<Self.descriptor.width).map { x in
                    zip(Self.pixel(image, x: x, y: y), Self.reference(x: x, y: y, uniforms: uniforms)).map { abs(Int($0) - Int($1)) }.max() ?? 0
                }
            }.max() ?? 0
        #expect(worst <= Self.tolerance, "worst channel difference \(worst)")
        // The corners are exact: the tolerance alone would hide a dropped `- 1`, a swapped axis or an unread uniform.
        #expect(Self.pixel(image, x: 0, y: 0) == [64, 0, 0, 64], "fract(3.25) and seed % 256 = 64 land in B and A")
        #expect(Self.pixel(image, x: 255, y: 0) == [64, 0, 255, 64], "x saturates R alone")
        #expect(Self.pixel(image, x: 0, y: 255) == [64, 255, 0, 64], "y saturates G alone")
        #expect(Self.pixel(image, x: 255, y: 255) == [64, 255, 255, 64])
        try gateway.unbind(texture)
    }

    @Test("two commits on one context each write their own surface")
    func twoCommitsOnOneContext() async throws {
        let (kernel, context) = try compile(Self.gradientSource)
        let first = try surfaces.create(Self.descriptor)
        let second = try surfaces.create(Self.descriptor)
        let grid = DispatchGrid.covering(width: Self.descriptor.width, height: Self.descriptor.height)
        let passes = try [(first, UInt32(10)), (second, UInt32(200))].map { surface, seed in
            ComputePass(kernel: kernel, textures: [try gateway.bind(surface, on: context)], uniforms: Self.uniforms(seed: seed), grid: grid)
        }

        let completions = try await passes.asyncMap { try await run($0, on: context) }
        #expect(completions.allSatisfy { $0.error == nil })
        #expect(Self.pixel(try Self.pixels(of: first), x: 0, y: 0)[3] == 10)
        #expect(Self.pixel(try Self.pixels(of: second), x: 0, y: 0)[3] == 200)
    }

    @Test("a syntax error comes back as the compiler's diagnostics, not a thrown error")
    func syntaxErrorYieldsDiagnostics() throws {
        let context = try gateway.makeContext()
        let result = gateway.compile(source: Self.header + "kernel void effect( {", options: ShaderCompileOptions(), on: context)
        let diagnostics = try #require(result.failure)
        #expect(diagnostics.message.contains("error"))
        #expect(diagnostics.code != 0)
    }

    @Test("a source without the entry point is a diagnostic with code 0")
    func missingEntryPointYieldsDiagnostics() throws {
        let context = try gateway.makeContext()
        let source = Self.fillSource.replacingOccurrences(of: "kernel void effect(", with: "kernel void other(")
        let diagnostics = try #require(gateway.compile(source: source, options: ShaderCompileOptions(), on: context).failure)
        #expect(diagnostics.code == 0)
        #expect(diagnostics.message.contains("effect"))
    }

    @Test("a surface can be bound again after unbind, and foreign handles are refused")
    func rebindAndProvenance() throws {
        let (kernel, context) = try compile(Self.fillSource)
        let surface = try surfaces.create(Self.descriptor)
        let first = try gateway.bind(surface, on: context)
        try gateway.unbind(first)
        let second = try gateway.bind(surface, on: context)
        #expect(ObjectIdentifier(second.backing) != ObjectIdentifier(first.backing), "a fresh texture, not the unbound one")
        try gateway.unbind(second)

        #expect(throws: SurfaceError.foreignHandle) {
            try gateway.bind(FakeSurfaceHandle(id: 1, descriptor: Self.descriptor), on: context)
        }
        #expect(throws: GPUError.foreignHandle) {
            try gateway.unbind(ForeignTextureHandle())
        }
        let grid = DispatchGrid.covering(width: Self.descriptor.width, height: Self.descriptor.height)
        let pass = ComputePass(kernel: kernel, textures: [], uniforms: Self.uniforms(), grid: grid)
        #expect(throws: GPUError.foreignHandle) {
            try gateway.encodeAndCommit(pass, on: ForeignContextHandle()) { _ in }
        }
    }
}

extension Array {
    /// `map` with an `await` in the body; the accumulator stays private to the helper.
    fileprivate func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var result: [T] = []
        for element in self { result.append(try await transform(element)) }
        return result
    }
}

private final class ForeignTextureHandle: TextureHandle, Sendable {
    var backing: AnyObject { self }
}

private final class ForeignContextHandle: GPUContextHandle, Sendable {
    var backing: AnyObject { self }
}

extension Result {
    fileprivate var failure: Failure? {
        switch self {
        case .success: nil
        case .failure(let error): error
        }
    }
}
