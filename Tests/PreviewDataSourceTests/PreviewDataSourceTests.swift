import Domain
import TestDoubles
import TestSupport
import Testing

@testable import PreviewDataSource

@Suite("PreviewDataSourceImpl", .timeLimit(.minutes(1)))
struct PreviewDataSourceTests {
    private let rig = PreviewRig()

    // MARK: - Attach

    @Test("with nothing attached every frame completes at once, undrawn")
    func unattachedCompletesAtOnce() throws {
        rig.present(try rig.frame(1))
        rig.present(try rig.frame(2))
        #expect(rig.completed.count == 0, "nothing happens before the executor runs")

        rig.executor.drain()

        #expect(rig.completed.values == [1, 2])
        #expect(rig.preview.draws.count == 0)
        #expect(rig.textures.bindCount == 0)
        #expect(rig.pool.liveCount == 0)
    }

    @Test("attach readies the view on a fresh context and compiles the preview kernel on the executor, off the main thread")
    func attachPreparesAndCompiles() async throws {
        let target = FakePreviewTargetHandle()
        try await rig.attach(target)

        #expect(rig.gpu.contextCount == 1)
        let layer = try #require(rig.preview.prepared.values.first)
        #expect(ObjectIdentifier(layer.target) == ObjectIdentifier(target))
        #expect(rig.compiler.calls.count == 0, "the compile waits for the executor")

        rig.executor.drain()

        let call = try #require(rig.compiler.calls.values.first)
        #expect(rig.compiler.calls.count == 1)
        #expect(call.source == PreviewKernel.source)
        #expect(call.options == PreviewKernel.options)
        #expect(!call.onMainThread)
    }

    @Test("a foreign target is thrown to the caller and nothing is attached")
    func foreignTargetIsRefused() async throws {
        await #expect(throws: PreviewError.foreignTarget) { try await rig.attach(ForeignTarget()) }
        rig.executor.drain()
        rig.present(try rig.frame(1))
        rig.executor.drain()

        #expect(rig.compiler.calls.count == 0)
        #expect(rig.completed.values == [1])
        #expect(rig.preview.draws.count == 0)
    }

    @Test("a machine without a GPU is thrown to the caller before the view is touched")
    func noDeviceIsRefused() async throws {
        rig.gpu.failMakeContext(with: .noDevice)
        await #expect(throws: GPUError.noDevice) { try await rig.attach() }
        #expect(rig.preview.prepared.count == 0)
    }

    @Test("a refused attach leaves the previous one in effect")
    func refusedAttachKeepsThePrevious() async throws {
        try await rig.attach()
        rig.executor.drain()
        let layer = try #require(rig.preview.prepared.values.first)

        await #expect(throws: PreviewError.foreignTarget) { try await rig.attach(ForeignTarget()) }
        rig.present(try rig.frame(1))
        rig.executor.drain()

        let draw = try #require(rig.preview.pending.first)
        #expect(ObjectIdentifier(draw.layer) == ObjectIdentifier(layer))
    }

    @Test("a kernel that does not compile leaves the preview detached and is logged")
    func compileFailureDetaches() async throws {
        rig.compiler.failCompile(of: PreviewKernel.source, with: ShaderDiagnostics(message: "program_source:1: error", code: 3))
        try await rig.attach()
        rig.executor.drain()
        rig.present(try rig.frame(1))
        rig.executor.drain()

        #expect(rig.completed.values == [1])
        #expect(rig.preview.draws.count == 0)
        #expect(rig.log.messages(in: .preview).contains { $0.contains("did not compile") })
    }

    @Test("a re-attach whose kernel does not compile detaches the previous view too")
    func failedReattachDetaches() async throws {
        try await rig.attach()
        rig.executor.drain()
        rig.compiler.failCompile(of: PreviewKernel.source, with: ShaderDiagnostics(message: "device lost", code: 1))
        try await rig.attach()
        rig.executor.drain()

        rig.present(try rig.frame(1))
        rig.executor.drain()
        #expect(rig.completed.values == [1])
        #expect(rig.preview.draws.count == 0)
    }

    @Test("frames are handled in executor order: one presented before the attach lands completes undrawn")
    func attachIsOrderedOnTheExecutor() async throws {
        rig.present(try rig.frame(1))
        try await rig.attach()
        rig.present(try rig.frame(2))

        rig.executor.drain()

        #expect(rig.completed.values == [1])
        let draw = try #require(rig.preview.pending.first)
        #expect(rig.frameNumber(of: draw) == 2)
    }

    // MARK: - Drawing

    @Test("a frame is drawn from its pooled surface with the compiled kernel into the attached layer, and completes once the GPU is done")
    func frameIsDrawnThenCompleted() async throws {
        try await rig.attach()
        rig.executor.drain()
        let frame = try rig.frame(1)
        let surface = try #require(rig.pool.handle(for: frame.token))

        rig.present(frame)
        rig.executor.drain()

        let draw = try #require(rig.preview.pending.first)
        let layer = try #require(rig.preview.prepared.values.first)
        #expect(ObjectIdentifier(draw.texture.surface) == ObjectIdentifier(surface))
        #expect(draw.kernel.source == PreviewKernel.source)
        #expect(draw.kernel.options == PreviewKernel.options)
        #expect(ObjectIdentifier(draw.layer) == ObjectIdentifier(layer))
        #expect(ObjectIdentifier(draw.context) == ObjectIdentifier(layer.context), "bound and drawn on the attach's context")
        #expect(rig.completed.count == 0, "the surface is borrowed until the GPU is done")

        rig.preview.complete(draw)
        #expect(rig.completed.count == 0, "the completion hops onto the executor")
        rig.executor.drain()

        #expect(rig.completed.values == [1])
        #expect(rig.textures.isBalanced)
        #expect(rig.pool.liveCount == 0)
    }

    @Test("while a draw is in flight only the newest frame waits; each frame it replaces completes at once, undrawn")
    func latestWins() async throws {
        try await rig.attach()
        rig.executor.drain()
        for number in 1...4 { rig.present(try rig.frame(number)) }
        rig.executor.drain()

        #expect(rig.preview.pending.count == 1, "one draw in flight")
        #expect(rig.completed.values == [2, 3])

        rig.preview.complete(try #require(rig.preview.pending.first))
        rig.executor.drain()
        #expect(rig.completed.values == [2, 3, 1])
        let next = try #require(rig.preview.pending.first)
        #expect(rig.frameNumber(of: next) == 4)

        rig.preview.complete(next)
        rig.executor.drain()
        #expect(rig.completed.values == [2, 3, 1, 4])
        #expect(rig.preview.draws.values.compactMap(rig.frameNumber(of:)) == [1, 4])
        #expect(rig.textures.isBalanced)
        #expect(rig.textures.bindCount == 2, "replaced frames are never bound")
    }

    @Test("a stale token completes at once without binding or drawing, and is logged")
    func staleTokenIsNotDrawn() async throws {
        try await rig.attach()
        rig.executor.drain()
        let frame = try rig.frame(1)
        rig.pool.release(frame.token)

        rig.present(frame)
        rig.executor.drain()

        #expect(rig.completed.values == [1])
        #expect(rig.textures.bindCount == 0)
        #expect(rig.preview.draws.count == 0)
        #expect(rig.log.messages(in: .preview).contains { $0.contains("stale") })
    }

    @Test("a bind failure completes the frame undrawn and is logged; the next frame still draws")
    func bindFailure() async throws {
        try await rig.attach()
        rig.executor.drain()
        rig.textures.failBind(with: .textureBindingFailed)
        rig.present(try rig.frame(1))
        rig.executor.drain()

        #expect(rig.completed.values == [1])
        #expect(rig.preview.draws.count == 0)
        #expect(rig.log.messages(in: .preview).contains { $0.contains("binding") })

        rig.textures.failBind(with: nil)
        rig.present(try rig.frame(2))
        rig.executor.drain()
        #expect(rig.preview.pending.count == 1)
    }

    @Test("an encoding failure gives the texture back, completes the frame and leaves the next one free to draw")
    func encodeFailure() async throws {
        try await rig.attach()
        rig.executor.drain()
        rig.preview.failDraw(with: GPUError.encoderUnavailable)
        rig.present(try rig.frame(1))
        rig.executor.drain()

        #expect(rig.completed.values == [1])
        #expect(rig.textures.isBalanced)
        #expect(rig.textures.bindCount == 1)
        #expect(rig.log.messages(in: .preview).contains { $0.contains("encoding") })

        rig.preview.failDraw(with: nil)
        rig.present(try rig.frame(2))
        rig.executor.drain()
        #expect(rig.preview.pending.count == 1, "the failed draw did not leave a draw in flight")
    }

    @Test("a GPU error is logged, and the frame still completes with its texture given back")
    func gpuErrorIsLogged() async throws {
        try await rig.attach()
        rig.executor.drain()
        rig.present(try rig.frame(1))
        rig.executor.drain()

        let fault = GPUCompletion(gpuStart: 0, gpuEnd: 0, error: RawGPUError(domain: "MTLCommandBufferErrorDomain", code: 3))
        rig.preview.complete(try #require(rig.preview.pending.first), with: fault)
        rig.executor.drain()

        #expect(rig.completed.values == [1])
        #expect(rig.textures.isBalanced)
        #expect(rig.log.messages(in: .preview).contains { $0.contains("MTLCommandBufferErrorDomain 3") })
    }

    @Test("a re-attach takes effect for the next draw; the draw in flight finishes on its own")
    func reattachWhileDrawing() async throws {
        try await rig.attach()
        rig.executor.drain()
        rig.present(try rig.frame(1))
        rig.executor.drain()
        let first = try #require(rig.preview.pending.first)

        try await rig.attach()
        rig.present(try rig.frame(2))
        rig.executor.drain()
        #expect(rig.preview.pending.count == 1, "frame 2 waits for the draw in flight")

        rig.preview.complete(first)
        rig.executor.drain()

        let second = try #require(rig.preview.pending.first)
        let newLayer = try #require(rig.preview.prepared.values.last)
        #expect(rig.completed.values == [1])
        #expect(rig.frameNumber(of: second) == 2)
        #expect(ObjectIdentifier(second.layer) == ObjectIdentifier(newLayer))
        #expect(ObjectIdentifier(second.context) == ObjectIdentifier(newLayer.context))
        #expect(ObjectIdentifier(second.context) != ObjectIdentifier(first.context))
        #expect(rig.gpu.contextCount == 2)
    }
}

private final class ForeignTarget: PreviewTargetHandle, Sendable {
    var backing: AnyObject { self }
}
