import BundledEffectDataSource
import Dependencies
import Domain
import EffectRuntimeRepository
import EffectRuntimeStateDataSource
import Foundation
import GPURenderDataSource
import IOSurfaceGateway
import MetalGateway
import ShaderCompilationDataSource
import TestDoubles
import TestSupport
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
/// Every kernel is assembled the way `ShaderCompilationDataSource` assembles an
/// effect (the prelude's `Uniforms`, then `#line 1 "effect"`), so the suite also
/// proves the prelude compiles and that `#line` maps diagnostics on this compiler.
/// The bundled effect is compiled the same way and its pixels compared with
/// `ChromaticGrainReference`, once through the gateway and once through
/// `EffectRuntimeRepository` over the live DataSources.
@Suite("MetalGateway smoke", .serialized, .enabled(if: MetalDeviceProbe.isAvailable), .timeLimit(.minutes(1)))
struct MetalGatewaySmokeTests {
    private let gateway = MetalGatewayImpl()
    private let surfaces = IOSurfaceGatewayImpl()
    private static let descriptor = SurfaceDescriptor.bgra(width: 256, height: 256)

    /// Every pixel becomes B G R A = 64 128 255 255.
    private static let fillEffect = """
        kernel void effect(texture2d<float, access::write> out [[texture(0)]], constant Uniforms &u [[buffer(0)]],
                           uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
            out.write(float4(1.0, 0.5, 0.25, 1.0), gid);
        }
        """
    private static let fillSource = ShaderSourceAssembly.assemble(fillEffect)

    /// `r = x / (w - 1)`, `g = y / (h - 1)`, `b = fract(time)`, `a = (seed % 256) / 255` — mirrored by `reference`.
    private static let gradientSource = ShaderSourceAssembly.assemble(
        """
        kernel void effect(texture2d<float, access::write> out [[texture(0)]], constant Uniforms &u [[buffer(0)]],
                           uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
            float2 uv = float2(gid) / (u.resolution - 1.0);
            out.write(float4(uv.x, uv.y, fract(u.time), float(u.seed % 256u) / 255.0), gid);
        }
        """)

    /// A syntax error on the author's third line (`1.0 +;` has no right operand).
    private static let brokenOnLine3 = """
        kernel void effect(texture2d<float, access::write> out [[texture(0)]],
                           uint2 gid [[thread_position_in_grid]]) {
            float broken = 1.0 +;
            out.write(float4(broken), gid);
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

    private func compile(_ source: String) throws -> (any LibraryHandle, any GPUContextHandle) {
        let context = try gateway.makeContext()
        return (try gateway.compile(source: source, options: ShaderCompileOptions(), on: context).get(), context)
    }

    private func run(_ pass: ComputePass, on context: any GPUContextHandle) async throws -> GPUCompletion {
        try await GPUSmokeSupport.run(pass, on: context, through: gateway)
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

        let image = try GPUSmokeSupport.pixels(of: surface)
        let offPixels = (0..<Self.descriptor.height).flatMap { y in
            (0..<Self.descriptor.width).filter { x in image.pixel(x: x, y: y) != [64, 128, 255, 255] }
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

        let image = try GPUSmokeSupport.pixels(of: surface)
        let offPixels = (0..<unaligned.height).flatMap { y in
            (0..<unaligned.width).filter { x in image.pixel(x: x, y: y) != [64, 128, 255, 255] }
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

        let image = try GPUSmokeSupport.pixels(of: surface)
        let worst =
            (0..<Self.descriptor.height).flatMap { y in
                (0..<Self.descriptor.width).map { x in
                    GPUSmokeSupport.distance(image.pixel(x: x, y: y), Self.reference(x: x, y: y, uniforms: uniforms))
                }
            }.max() ?? 0
        #expect(worst <= GPUSmokeSupport.tolerance, "worst channel difference \(worst)")
        // The corners are exact: the tolerance alone would hide a dropped `- 1`, a swapped axis or an unread uniform.
        #expect(image.pixel(x: 0, y: 0) == [64, 0, 0, 64], "fract(3.25) and seed % 256 = 64 land in B and A")
        #expect(image.pixel(x: 255, y: 0) == [64, 0, 255, 64], "x saturates R alone")
        #expect(image.pixel(x: 0, y: 255) == [64, 255, 0, 64], "y saturates G alone")
        #expect(image.pixel(x: 255, y: 255) == [64, 255, 255, 64])
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
        #expect(try GPUSmokeSupport.pixels(of: first).pixel(x: 0, y: 0)[3] == 10)
        #expect(try GPUSmokeSupport.pixels(of: second).pixel(x: 0, y: 0)[3] == 200)
    }

    @Test("a syntax error comes back as the compiler's diagnostics, not a thrown error")
    func syntaxErrorYieldsDiagnostics() throws {
        let context = try gateway.makeContext()
        let result = gateway.compile(source: ShaderSourceAssembly.assemble("kernel void effect( {"), options: ShaderCompileOptions(), on: context)
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

    @Test("#line makes the compiler report a syntax error on the author's third line as effect:3")
    func lineDirectiveMapsDiagnostics() throws {
        let context = try gateway.makeContext()
        let source = ShaderSourceAssembly.assemble(Self.brokenOnLine3)
        let diagnostics = try #require(gateway.compile(source: source, options: ShaderCompileOptions(), on: context).failure)
        #expect(diagnostics.message.hasPrefix("effect:3:"), "the raw compiler output: \(diagnostics.message)")
        #expect(!diagnostics.message.contains("program_source:\(ShaderSourceAssembly.authorLineOffset + 3):"))
        #expect(diagnostics.code != 0)
    }

    @Test("ShaderCompilationDataSource over the live gateway: author lines, prelude notes, and a kernel that runs on another context")
    func dataSourceOverLiveGateway() async throws {
        let compiler = withDependencies {
            $0.gpuGateway = gateway
            $0.shaderLibraryGateway = gateway
            $0.workRunner = RecordingWorkRunner()
        } operation: {
            ShaderCompilationDataSourceImpl()
        }
        let broken = try #require(await compiler.compile(EffectSource(name: "broken", source: Self.brokenOnLine3)).failure)
        #expect(broken.message.hasPrefix("effect:3:"), "\(broken.message)")

        // Redefining a prelude function: the error is the author's, the note points into the prelude.
        let clash = "inline float hash(uint2 cell, uint timeStep, uint seed) { return 0.0f; }\n" + Self.fillEffect
        let redefinition = try #require(await compiler.compile(EffectSource(name: "clash", source: clash)).failure)
        #expect(redefinition.message.hasPrefix("effect:1:"), "\(redefinition.message)")
        #expect(redefinition.message.contains("prelude:"), "\(redefinition.message)")
        #expect(!redefinition.message.contains("program_source:"), "\(redefinition.message)")

        // The handle is the device's: it dispatches on a context the compile never saw.
        let kernel = try await compiler.compile(EffectSource(name: "fill", source: Self.fillEffect)).get()
        let context = try gateway.makeContext()
        let surface = try surfaces.create(Self.descriptor)
        let texture = try gateway.bind(surface, on: context)
        let grid = DispatchGrid.covering(width: Self.descriptor.width, height: Self.descriptor.height)
        let completion = try await run(ComputePass(kernel: kernel, textures: [texture], uniforms: Self.uniforms(), grid: grid), on: context)
        #expect(completion.error == nil)
        #expect(try GPUSmokeSupport.pixels(of: surface).pixel(x: 17, y: 201) == [64, 128, 255, 255])
        try gateway.unbind(texture)
    }

    // MARK: - The bundled effect

    private static let effectDescriptor = SurfaceDescriptor.bgra(width: 160, height: 96)

    private static func effectUniforms(time: Float, frameIndex: UInt32, seed: UInt32) -> EffectUniforms {
        EffectUniforms(
            time: time, frameIndex: frameIndex, resolution: SIMD2(Float(effectDescriptor.width), Float(effectDescriptor.height)), seed: seed)
    }

    /// The input surface of the bundled-effect checks, filled with `ChromaticGrainReference.input`.
    private func effectInput() throws -> any SurfaceHandle {
        let surface = try surfaces.create(Self.effectDescriptor)
        try GPUSmokeSupport.write(surface) { ChromaticGrainReference.input($0, $1) }
        return surface
    }

    /// Checks `output` against the reference for `uniforms`, pixel by pixel, plus what the
    /// tolerance cannot hide: alpha is opaque everywhere, and red really drifted.
    private static func expectBundledEffect(in output: any SurfaceHandle, uniforms: EffectUniforms) throws {
        let image = try GPUSmokeSupport.pixels(of: output)
        let (width, height) = (effectDescriptor.width, effectDescriptor.height)
        let distances = (0..<height).flatMap { y in
            (0..<width).map { x in
                GPUSmokeSupport.distance(
                    image.pixel(x: x, y: y),
                    ChromaticGrainReference.pixel(x: x, y: y, uniforms: uniforms, width: width, height: height, input: ChromaticGrainReference.input))
            }
        }
        let outside = distances.filter { $0 > GPUSmokeSupport.tolerance }.count
        #expect(outside == 0, "\(outside) pixels outside the tolerance; worst channel difference \(distances.max() ?? 0)")
        let pixels = (0..<height).flatMap { y in (0..<width).map { x in (image.pixel(x: x, y: y), ChromaticGrainReference.input(x, y)) } }
        #expect(pixels.allSatisfy { $0.0[3] == 255 }, "alpha is written opaque")
        // The grain moves a channel by at most 8 levels; a red channel 9 levels a pixel steep moves further only by drifting.
        let drifted = pixels.filter { abs(Int($0.0[2]) - Int($0.1[2])) > 8 }.count
        #expect(drifted > pixels.count / 2, "only \(drifted) of \(pixels.count) pixels show the red drift")
    }

    @Test(
        "the bundled effect compiles behind the prelude and one pass over a fixed input matches its Swift reference within one 8-bit step",
        arguments: [(Float(3.25), UInt32(7), UInt32(0)), (0.6, 120, 0x5EED_1234)]
    )
    func bundledEffectMatchesReference(time: Float, frameIndex: UInt32, seed: UInt32) async throws {
        let effect = BundledEffectDataSourceImpl().defaultEffect
        let context = try gateway.makeContext()
        let kernel = try gateway.compile(source: ShaderSourceAssembly.assemble(effect.source), options: effect.options, on: context).get()
        let output = try surfaces.create(Self.effectDescriptor)
        let textures = [try gateway.bind(try effectInput(), on: context), try gateway.bind(output, on: context)]
        let uniforms = Self.effectUniforms(time: time, frameIndex: frameIndex, seed: seed)

        let grid = DispatchGrid.covering(width: Self.effectDescriptor.width, height: Self.effectDescriptor.height)
        let completion = try await run(ComputePass(kernel: kernel, textures: textures, uniforms: uniforms, grid: grid), on: context)
        #expect(completion.error == nil)
        try textures.forEach(gateway.unbind)
        try Self.expectBundledEffect(in: output, uniforms: uniforms)
    }

    @Test("EffectRuntimeRepository over the live stack: with nothing prepared, apply compiles the bundled effect once and renders it")
    @MainActor
    func runtimeOverLiveStack() async throws {
        let executor = ManualFrameExecutor()
        let pool = FakeSurfacePool(capacity: 2)
        let log = RecordingLog()
        let gateway = gateway
        let (compiler, renderer) = withDependencies {
            $0.gpuGateway = gateway
            $0.shaderLibraryGateway = gateway
            $0.textureCacheGateway = gateway
            $0.workRunner = RecordingWorkRunner()
            $0.surfacePool = pool
            $0.frameExecutor = executor
            $0.errorLog = log
        } operation: {
            (ShaderCompilationDataSourceImpl(), GPURenderDataSourceImpl())
        }
        let state = withDependencies {
            $0.frameExecutor = executor
        } operation: {
            EffectRuntimeStateDataSourceImpl()
        }
        let runtime = withDependencies {
            $0.effectRuntimeState = state
            $0.shaderCompiler = compiler
            $0.gpuRenderer = renderer
            $0.bundledEffects = BundledEffectDataSourceImpl()
            $0.errorLog = log
            $0.developerLog = log
        } operation: {
            EffectRuntimeRepositoryImpl()
        }
        let descriptor = Self.effectDescriptor
        let output = try surfaces.create(descriptor)
        let input = try #require(pool.adopt(try effectInput(), descriptor: descriptor))
        let target = try #require(pool.adopt(output, descriptor: descriptor))

        // Two frames of one run, 0.75 s apart: the first compiles, the second hits the cache.
        for (index, seconds) in [(UInt32(0), 5.0), (1, 5.75)] {
            let time = HostTimestamp.seconds(seconds)
            let answered = Collector<EffectFailure?>()
            Task {
                let result = await runtime.apply(
                    input: FrameRef(token: input, descriptor: descriptor, presentationTime: time),
                    output: FrameRef(token: target, descriptor: descriptor, presentationTime: time),
                    frameContext: FrameContext(presentationTime: time, frameIndex: index))
                answered.append(result.failure)
            }
            #expect(await tickUntil(tick: { executor.drain() }, until: { answered.count == 1 }))
            #expect(answered.values == [nil], "frame \(index)")
            try Self.expectBundledEffect(in: output, uniforms: Self.effectUniforms(time: index == 0 ? 0 : 0.75, frameIndex: index, seed: 0))
        }
        #expect(log.entries.values.map(\.message) == ["effect 'Chromatic Grain' compiled"])
        #expect(pool.release(input) && pool.release(target), "the leases stayed the caller's")
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
