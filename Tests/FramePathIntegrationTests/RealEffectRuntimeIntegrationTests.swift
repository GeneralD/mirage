import BundledEffectDataSource
import Domain
import GPURenderDataSource
import ShaderCompilationDataSource
import TestDoubles
import TestSupport
import Testing

/// The host's effect stage on the real stack: `EffectRuntimeRepositoryImpl` over
/// `EffectRuntimeStateDataSourceImpl`, `ShaderCompilationDataSourceImpl`,
/// `GPURenderDataSourceImpl` and `BundledEffectDataSourceImpl`, with only the GPU layer
/// faked (`FakeGPUGateway`, `FakeShaderLibraryGateway`, `FakeTextureCacheGateway`), joined
/// to the extension by `InMemoryFrameTransport` in place of Mach (`LoopbackRig(effects: .real)`).
/// What the device adds is the Metal compile and the command buffer, which `GPUSmokeTests`
/// runs on the real gateway over the same DataSources.
///
/// The rest of the loopback suites keep a `FakeEffectRuntimeRepository`, because they need
/// to choose each pass's result; here the result is whatever the real runtime derives from
/// what the GPU layer reports.
@MainActor
@Suite("Real effect runtime on the loopback", .timeLimit(.minutes(1)))
struct RealEffectRuntimeIntegrationTests {
    /// The source the compiler is handed for the bundled effect: the prelude, the line
    /// directive and the author's source.
    private static let bundledSource = ShaderSourceAssembly.assemble(BundledEffectDataSourceImpl().defaultEffect.source)

    // MARK: The effect's output is what the extension streams

    @Test func theExtensionStreamsTheEffectsOutputNotTheCamerasSurface() async throws {
        let rig = LoopbackRig(effects: .real)
        let relay = await rig.startExtension()
        try await rig.startHost()
        let camera = FakeSurfaceHandle(id: 7)

        await rig.captureThroughRuntime(camera, at: 1_000)
        await rig.pumpExtension(untilReceived: 1)

        let pass = try #require(rig.host.gpu.submissions.values.first?.pass, "the effect committed one command buffer")
        let (input, output) = try surfaces(of: pass)
        let streamed = try #require(rig.ext.stream.sent.values.first?.surface as? FakeSurfaceHandle)
        #expect(ObjectIdentifier(input) == ObjectIdentifier(camera), "the pass read the camera's surface")
        #expect(ObjectIdentifier(streamed) == ObjectIdentifier(output), "the extension streams the effect's output")
        #expect(ObjectIdentifier(streamed) != ObjectIdentifier(camera), "...and not the camera's input")
        #expect(rig.streamedTimes == [1_000], "the output carries the input's presentation time")
        #expect(rig.host.gpu.submissions.count == 1)

        let kernel = try #require(pass.kernel as? FakeLibraryHandle)
        #expect(kernel.source == Self.bundledSource, "the bundled effect, behind the prelude")
        #expect(pass.uniforms == EffectUniforms(time: 0, frameIndex: 0, resolution: SIMD2(1280, 720), seed: 0))
        #expect(rig.host.shaders.calls.values.map(\.onMainThread) == [false], "compiled once, off the main thread")

        #expect(rig.host.pipeline.stats.effectsApplied == 1)
        #expect(rig.host.pipeline.stats.effectFailures.isEmpty)
        #expect(rig.host.pipeline.stats.framesSent == 1)
        #expect(rig.host.developer.messages(in: .effect) == ["effect '\(ChromaticGrainEffect.name)' compiled"])
        #expect(rig.host.errors.entries.count == 0)
        #expect(rig.host.textures.isBalanced, "both textures went back")
        #expect(rig.host.pool.liveCount == 0, "the host released the input at the answer and the output after the send")
        #expect(rig.ext.pool.liveCount == 0)

        try await rig.stopExtension(relay)
        rig.stopHost()
    }

    @Test func laterFramesReuseTheCompiledEffectAndTheSessionClockRuns() async throws {
        let rig = LoopbackRig(effects: .real)
        let relay = await rig.startExtension()
        try await rig.startHost()

        await rig.captureThroughRuntime(FakeSurfaceHandle(id: 1), at: 2_000_000_000)
        await rig.captureThroughRuntime(FakeSurfaceHandle(id: 2), at: 2_500_000_000)
        await rig.pumpExtension(untilReceived: 2)

        let passes = rig.host.gpu.submissions.values.map(\.pass)
        #expect(passes.count == 2)
        #expect(passes.map(\.uniforms.frameIndex) == [0, 1])
        #expect(passes.map(\.uniforms.time) == [0, 0.5], "time is seconds since the session's first frame")
        let kernels = passes.compactMap { $0.kernel as? FakeLibraryHandle }.map(ObjectIdentifier.init)
        #expect(kernels.count == 2 && kernels[0] == kernels[1], "one compiled library serves every frame")
        #expect(rig.host.shaders.calls.count == 1, "the second frame did not compile again")

        let outputs = try passes.map { try surfaces(of: $0).output }.map(ObjectIdentifier.init)
        let streamed = rig.ext.stream.sent.values.compactMap { $0.surface as? FakeSurfaceHandle }.map(ObjectIdentifier.init)
        #expect(streamed == outputs, "each frame's output reached the extension, in order")
        #expect(rig.host.pool.liveCount == 0)
        #expect(rig.host.textures.isBalanced)

        try await rig.stopExtension(relay)
        rig.stopHost()
    }

    // MARK: A broken effect never costs the picture

    /// The automated twin of the device check "the effect source is broken and the video still
    /// shows": the compiler rejects the bundled source, and the extension still gets every
    /// camera frame, as it was captured.
    @Test func aSourceThatDoesNotCompileStillPassesTheCamerasFrameThrough() async throws {
        let rig = LoopbackRig(effects: .real)
        rig.host.shaders.failCompile(
            of: Self.bundledSource, with: ShaderDiagnostics(message: "effect:3:5: error: use of undeclared identifier 'oops'", code: 3))
        let relay = await rig.startExtension()
        try await rig.startHost()
        let frames = [FakeSurfaceHandle(id: 1), FakeSurfaceHandle(id: 2)]

        await rig.captureThroughRuntime(frames[0], at: 1_000)
        await rig.captureThroughRuntime(frames[1], at: 2_000)
        await rig.pumpExtension(untilReceived: 2)

        let streamed = rig.ext.stream.sent.values.compactMap { $0.surface as? FakeSurfaceHandle }.map(ObjectIdentifier.init)
        #expect(streamed == frames.map(ObjectIdentifier.init), "the extension got the camera's own surfaces, in order")
        #expect(rig.streamedTimes == [1_000, 2_000])
        #expect(rig.host.pipeline.stats.effectFailures == [.compileFailed: 2])
        #expect(rig.host.pipeline.stats.effectsApplied == 0)
        #expect(rig.host.pipeline.stats.framesSent == 2)
        #expect(rig.host.pipeline.stats.framesDropped == 0, "a broken effect drops nothing")

        #expect(rig.host.gpu.submissions.count == 0, "no command buffer was committed")
        #expect(rig.host.textures.bindCount == 0, "nothing was bound")
        #expect(rig.host.shaders.calls.count == 1, "the failure is final for the effect: the second frame does not compile again")
        #expect(rig.host.errors.messages(in: .effect).count == 1, "the failure is reported once, not once per frame")
        #expect(rig.host.errors.messages(in: .effect).first?.contains("effect:3:5: error: use of undeclared identifier 'oops'") == true)
        #expect(rig.host.pool.liveCount == 0, "the unused output went back at the answer, the input after the send")
        #expect(rig.ext.pool.liveCount == 0)

        try await rig.stopExtension(relay)
        rig.stopHost()
    }

    @Test func aCommandBufferThatFailsPassesTheFrameThroughAndTheNextFrameIsAppliedAgain() async throws {
        let rig = LoopbackRig(effects: .real)
        let relay = await rig.startExtension()
        try await rig.startHost()
        let failing = FakeSurfaceHandle(id: 1)
        let good = FakeSurfaceHandle(id: 2)

        await rig.captureThroughRuntime(failing, at: 1_000, completing: .failed(code: 3))
        await rig.captureThroughRuntime(good, at: 2_000)
        await rig.pumpExtension(untilReceived: 2)

        let passes = rig.host.gpu.submissions.values.map(\.pass)
        let streamed = rig.ext.stream.sent.values.compactMap { $0.surface as? FakeSurfaceHandle }.map(ObjectIdentifier.init)
        #expect(streamed.first == ObjectIdentifier(failing), "a page fault in the pass: the camera's frame goes on unchanged")
        let nextOutput = try surfaces(of: try #require(passes.last)).output
        #expect(streamed.last == ObjectIdentifier(nextOutput), "no memory of it: the next frame's output")
        #expect(rig.host.pipeline.stats.effectFailures == [.pageFault: 1])
        #expect(rig.host.pipeline.stats.effectsApplied == 1)
        #expect(rig.host.pipeline.stats.framesDropped == 0)
        #expect(rig.host.textures.isBalanced, "the failed pass unbound its textures exactly once")
        #expect(rig.host.pool.liveCount == 0)
        #expect(rig.ext.pool.liveCount == 0)

        try await rig.stopExtension(relay)
        rig.stopHost()
    }

    // MARK: With the real preview as well

    @Test func theStreamAndThePreviewShowTheSameOutputOfTheRealRuntime() async throws {
        let rig = LoopbackRig(preview: .rendered, effects: .real)
        let relay = await rig.startExtension()
        try await rig.startHost()
        try await rig.attachPreview()
        let camera = FakeSurfaceHandle(id: 7)

        await rig.captureThroughRuntime(camera, at: 1_000)
        await rig.pumpExtension(untilReceived: 1)

        let pass = try #require(rig.host.gpu.submissions.values.first?.pass)
        let output = try surfaces(of: pass).output
        let streamed = try #require(rig.ext.stream.sent.values.first?.surface as? FakeSurfaceHandle)
        let draw = try #require(rig.host.previewGateway.pending.first)
        #expect(ObjectIdentifier(streamed) == ObjectIdentifier(output), "the extension streams the effect's output")
        #expect(ObjectIdentifier(draw.texture.surface) == ObjectIdentifier(output), "the preview draws that same surface")
        #expect(rig.host.pool.liveCount == 1, "the camera's frame ended at the answer; the output waits for the draw")
        #expect(rig.host.shaders.calls.values.map(\.source).filter { $0 == Self.bundledSource }.count == 1)

        #expect(rig.host.previewGateway.complete(draw))
        rig.host.executor.drain()
        #expect(rig.host.pool.liveCount == 0)
        #expect(rig.host.textures.isBalanced, "the effect's two textures and the preview's one all went back")
        #expect(rig.host.errors.entries.count == 0)

        try await rig.stopExtension(relay)
        rig.stopHost()
    }

    // MARK: Helpers

    /// The surfaces a pass read and wrote: texture 0 is the input, the last texture the output.
    private func surfaces(of pass: ComputePass) throws -> (input: FakeSurfaceHandle, output: FakeSurfaceHandle) {
        let textures = try #require(pass.textures as? [FakeTextureHandle], "the pass bound the fake gateway's textures")
        #expect(textures.count == 2, "an effect pass binds its input and its output")
        return (try #require(textures.first).surface, try #require(textures.last).surface)
    }
}
