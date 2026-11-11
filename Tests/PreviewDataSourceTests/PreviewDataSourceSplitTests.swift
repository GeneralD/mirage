import Domain
import TestDoubles
import TestSupport
import Testing

@testable import PreviewDataSource

/// The split draw: a frame presented with an original is drawn by the split kernel with the
/// original bound beside it. Every other case falls back to the blit, with the frame as its own
/// original, and gives back every texture it bound.
@Suite("PreviewDataSourceImpl split", .timeLimit(.minutes(1)))
struct PreviewDataSourceSplitTests {
    private let rig = PreviewRig()

    @Test("a present with an original is drawn with the split kernel, the frame at texture 0 and the original at texture 2")
    func splitDrawsTheOriginalBesideTheFrame() async throws {
        try await rig.attach()
        rig.executor.drain()
        let frame = try rig.frame(1)
        let original = try rig.frame(2)
        let frameSurface = try #require(rig.pool.handle(for: frame.token))
        let originalSurface = try #require(rig.pool.handle(for: original.token))

        rig.present(frame, original: original)
        rig.executor.drain()

        let draw = try #require(rig.preview.pending.first)
        #expect(draw.kernel.source == PreviewKernel.splitSource)
        #expect(draw.kernel.options == PreviewKernel.splitOptions)
        #expect(ObjectIdentifier(draw.texture.surface) == ObjectIdentifier(frameSurface))
        #expect(ObjectIdentifier(draw.original.surface) == ObjectIdentifier(originalSurface))
        #expect(ObjectIdentifier(draw.original) != ObjectIdentifier(draw.texture), "one binding per surface")
    }

    @Test("a present without an original is drawn with the blit kernel, its original being the frame texture")
    func withoutAnOriginalTheBlitDrawsTheFrame() async throws {
        try await rig.attach()
        rig.executor.drain()
        rig.present(try rig.frame(1))
        rig.executor.drain()

        let draw = try #require(rig.preview.pending.first)
        #expect(draw.kernel.options == PreviewKernel.options)
        #expect(ObjectIdentifier(draw.original) == ObjectIdentifier(draw.texture))
        #expect(rig.textures.bindCount == 1)
    }

    @Test("a split draw completes once, after the GPU is done, and then both of its textures are unbound")
    func splitGivesBothTexturesBack() async throws {
        try await rig.attach()
        rig.executor.drain()
        rig.present(try rig.frame(1), original: try rig.frame(2))
        rig.executor.drain()
        #expect(rig.textures.bindCount == 2)
        #expect(rig.textures.liveCount == 2)

        rig.preview.complete(try #require(rig.preview.pending.first))
        #expect(rig.completed.count == 0, "the completion hops onto the executor")
        rig.executor.drain()

        #expect(rig.completed.values == [1])
        #expect(rig.textures.liveCount == 0)
        #expect(rig.textures.isBalanced)
        #expect(rig.pool.liveCount == 0)
    }

    @Test("without a split kernel an original is not bound, and the frame is drawn with the blit as its own original")
    func noSplitKernelDrawsTheBlit() async throws {
        rig.compiler.failCompile(of: PreviewKernel.splitSource, with: ShaderDiagnostics(message: "split: error", code: 5))
        try await rig.attach()
        rig.executor.drain()
        rig.present(try rig.frame(1), original: try rig.frame(2))
        rig.executor.drain()

        let draw = try #require(rig.preview.pending.first)
        #expect(draw.kernel.options == PreviewKernel.options)
        #expect(ObjectIdentifier(draw.original) == ObjectIdentifier(draw.texture))
        #expect(rig.textures.bindCount == 1, "the original is not bound")
    }

    @Test("a stale original token is drawn with the blit, logs one line, and gives the frame texture back once it completes")
    func staleOriginalFallsBackToTheBlit() async throws {
        try await rig.attach()
        rig.executor.drain()
        let original = try rig.frame(2)
        rig.pool.release(original.token)

        rig.present(try rig.frame(1), original: original)
        rig.executor.drain()

        let draw = try #require(rig.preview.pending.first)
        #expect(draw.kernel.options == PreviewKernel.options)
        #expect(rig.textures.bindCount == 1, "the frame is bound, the stale original is not")
        #expect(rig.log.messages(in: .preview).filter { $0.hasPrefix("split not shown") }.count == 1)

        rig.preview.complete(draw)
        rig.executor.drain()

        #expect(rig.completed.values == [1])
        #expect(rig.textures.isBalanced)
    }

    @Test("a failed bind of the original is drawn with the blit, logs one line, and gives the frame texture back once it completes")
    func failedOriginalBindFallsBackToTheBlit() async throws {
        try await rig.attach()
        rig.executor.drain()
        let original = try rig.frame(2)
        let originalSurface = try #require(rig.pool.handle(for: original.token) as? FakeSurfaceHandle)
        rig.textures.failBind(ofSurface: originalSurface, with: .textureBindingFailed)

        rig.present(try rig.frame(1), original: original)
        rig.executor.drain()

        let draw = try #require(rig.preview.pending.first)
        #expect(draw.kernel.options == PreviewKernel.options)
        #expect(ObjectIdentifier(draw.original) == ObjectIdentifier(draw.texture))
        #expect(rig.log.messages(in: .preview).filter { $0.hasPrefix("split not shown") }.count == 1)

        rig.preview.complete(draw)
        rig.executor.drain()

        #expect(rig.completed.values == [1])
        #expect(rig.textures.bindCount == 1)
        #expect(rig.textures.isBalanced)
    }

    @Test("a failed bind of the frame completes it undrawn and leaves the original unbound")
    func failedFrameBindLeavesTheOriginalUnbound() async throws {
        try await rig.attach()
        rig.executor.drain()
        let frame = try rig.frame(1)
        let frameSurface = try #require(rig.pool.handle(for: frame.token) as? FakeSurfaceHandle)
        rig.textures.failBind(ofSurface: frameSurface, with: .textureBindingFailed)

        rig.present(frame, original: try rig.frame(2))
        rig.executor.drain()

        #expect(rig.completed.values == [1])
        #expect(rig.preview.draws.count == 0)
        #expect(rig.textures.bindCount == 0, "the original is not bound once the frame is not")
        #expect(rig.textures.isBalanced)
        #expect(rig.pool.liveCount == 0)
    }

    @Test("an encoding failure of the split gives both textures back and completes the frame once")
    func failedSplitEncodeGivesBothTexturesBack() async throws {
        try await rig.attach()
        rig.executor.drain()
        rig.preview.failDraw(with: GPUError.encoderUnavailable)
        rig.present(try rig.frame(1), original: try rig.frame(2))
        rig.executor.drain()

        #expect(rig.completed.values == [1])
        #expect(rig.textures.bindCount == 2)
        #expect(rig.textures.isBalanced)
        #expect(rig.pool.liveCount == 0)
        #expect(rig.log.messages(in: .preview).contains { $0.contains("encoding") })
    }

    @Test("a frame with an original that is replaced while it waits completes once, undrawn, and its original is never bound")
    func replacedWaitingOriginalIsNotBound() async throws {
        try await rig.attach()
        rig.executor.drain()
        rig.present(try rig.frame(1))
        rig.executor.drain()
        let first = try #require(rig.preview.pending.first)

        rig.present(try rig.frame(2), original: try rig.frame(3))
        rig.present(try rig.frame(4))
        rig.executor.drain()
        #expect(rig.completed.values == [2])

        rig.preview.complete(first)
        rig.executor.drain()
        let next = try #require(rig.preview.pending.first)
        #expect(rig.frameNumber(of: next) == 4)
        rig.preview.complete(next)
        rig.executor.drain()

        #expect(rig.completed.values == [2, 1, 4])
        #expect(rig.textures.bindCount == 2, "frames 1 and 4 are bound; the replaced frame and its original are not")
        #expect(rig.textures.isBalanced)
        #expect(rig.pool.liveCount == 0)
    }
}
