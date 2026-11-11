import BundledEffectDataSource
import Dependencies
import Domain
import EffectRuntimeRepository
import EffectRuntimeStateDataSource
import Foundation
import GPURenderDataSource
import IOSurfaceGateway
import Metal
import MetalGateway
import ShaderCompilationDataSource
import TestDoubles
import TestSupport
import Testing

/// The GPU's own timing of one pass, checked at both seams that carry it: the completion the Metal gateway
/// hands back, and the outcome the effect runtime reports for a frame of the bundled effect.
///
/// `gpuStartTime` and `gpuEndTime` are command-buffer seconds, copied through unchanged. A real device must
/// report a start after zero and an end after the start; a Paravirtual device (a CI VM) only has to keep the
/// order. The timing is never compared with an absolute value.
///
/// `mac2`-class kernels only: a plain fill cannot hang or fault, so nothing here touches the real hang,
/// page-fault or access-revoked paths (`.claude/rules/gpu-testing.md`).
@Suite("GPU timing smoke", .serialized, .enabled(if: MetalDeviceProbe.isAvailable), .timeLimit(.minutes(1)))
struct GPUTimingSmokeTests {
    private let gateway = MetalGatewayImpl()
    private let surfaces = IOSurfaceGatewayImpl()
    private static let descriptor = SurfaceDescriptor.bgra(width: 256, height: 256)
    private static let effectDescriptor = SurfaceDescriptor.bgra(width: 160, height: 96)

    /// Every pixel is written with a fixed colour. Only the pass's timing is checked, so the output is not compared.
    private static let fillSource = ShaderSourceAssembly.assemble(
        """
        kernel void effect(texture2d<float, access::write> out [[texture(0)]], constant Uniforms &u [[buffer(0)]],
                           uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
            out.write(float4(1.0, 0.5, 0.25, 1.0), gid);
        }
        """)

    private static func uniforms() -> EffectUniforms {
        EffectUniforms(time: 0, frameIndex: 0, resolution: SIMD2(Float(descriptor.width), Float(descriptor.height)), seed: 0)
    }

    private func compile(_ source: String) throws -> (any LibraryHandle, any GPUContextHandle) {
        let context = try gateway.makeContext()
        return (try gateway.compile(source: source, options: ShaderCompileOptions(), on: context).get(), context)
    }

    @Test("one compute pass through the Metal gateway completes with the GPU's own start and end time")
    func gatewayPassCarriesRealGPUTime() async throws {
        let (kernel, context) = try compile(Self.fillSource)
        let surface = try surfaces.create(Self.descriptor)
        let texture = try gateway.bind(surface, on: context)

        let grid = DispatchGrid.covering(width: Self.descriptor.width, height: Self.descriptor.height)
        let completion = try await GPUSmokeSupport.run(
            ComputePass(kernel: kernel, textures: [texture], uniforms: Self.uniforms(), parameters: .none, grid: grid),
            on: context, through: gateway)
        #expect(completion.error == nil)
        expectRealTiming(gpuStart: completion.gpuStart, gpuEnd: completion.gpuEnd)
        try gateway.unbind(texture)
    }

    /// The input of the bundled effect, filled the way the bundled-effect suite fills it.
    private func effectInput() throws -> any SurfaceHandle {
        let surface = try surfaces.create(Self.effectDescriptor)
        try GPUSmokeSupport.write(surface) { ChromaticGrainReference.input($0, $1) }
        return surface
    }

    /// The runtime over the live compiler, renderer and Metal gateway, on one manual executor and a fake pool.
    private func liveRuntime(executor: ManualFrameExecutor, pool: FakeSurfacePool, log: RecordingLog) -> EffectRuntimeRepositoryImpl {
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
        return withDependencies {
            $0.effectRuntimeState = state
            $0.workRunner = RecordingWorkRunner()
            $0.shaderCompiler = compiler
            $0.gpuRenderer = renderer
            $0.bundledEffects = BundledEffectDataSourceImpl()
            $0.errorLog = log
            $0.developerLog = log
        } operation: {
            EffectRuntimeRepositoryImpl()
        }
    }

    @Test("a frame of the bundled effect through the live runtime reports the same real GPU time as its outcome")
    @MainActor
    func runtimeOutcomeCarriesRealGPUTime() async throws {
        let executor = ManualFrameExecutor()
        let pool = FakeSurfacePool(capacity: 2)
        let runtime = liveRuntime(executor: executor, pool: pool, log: RecordingLog())
        let descriptor = Self.effectDescriptor
        let input = try #require(pool.adopt(try effectInput(), descriptor: descriptor))
        let target = try #require(pool.adopt(try surfaces.create(descriptor), descriptor: descriptor))

        // The stream is made before the frame, so the outcome of that frame is not missed.
        let outcomes = runtime.outcomes()
        let collected = Collector<EffectPassOutcome>()
        let relay = Task {
            for await outcome in outcomes {
                collected.append(outcome)
                return
            }
        }
        defer { relay.cancel() }

        let time = HostTimestamp.seconds(5)
        let answered = Collector<EffectFailure?>()
        Task {
            let result = await runtime.apply(
                input: FrameRef(token: input, descriptor: descriptor, presentationTime: time),
                output: FrameRef(token: target, descriptor: descriptor, presentationTime: time),
                frameContext: FrameContext(presentationTime: time, frameIndex: 0))
            answered.append(result.failure)
        }
        #expect(await tickUntil(tick: { executor.drain() }, until: { answered.count == 1 }))
        #expect(answered.values == [nil])
        #expect(await tickUntil(tick: { executor.drain() }, until: { collected.count == 1 }), "the frame's outcome reached the stream")

        let outcome = try #require(collected.values.first)
        let timing = try outcome.result.get()
        expectRealTiming(gpuStart: timing.gpuStart, gpuEnd: timing.gpuEnd)
        #expect(pool.release(input) && pool.release(target), "the leases stayed the caller's")
    }
}

/// Checks one pass's GPU timing. A Paravirtual device (a CI VM) reports no real clock, so only the order is checked
/// there. Any other device must report a start after zero and an end after the start, strictly.
private func expectRealTiming(gpuStart: Double, gpuEnd: Double) {
    if MetalDeviceProbe.makeDevice()?.name.contains("Paravirtual") == true {
        #expect(gpuEnd >= gpuStart, "gpuStart \(gpuStart), gpuEnd \(gpuEnd)")
    } else {
        #expect(gpuStart > 0, "gpuStart \(gpuStart) is not a GPU timestamp")
        #expect(gpuEnd > gpuStart, "gpuStart \(gpuStart), gpuEnd \(gpuEnd)")
    }
}
