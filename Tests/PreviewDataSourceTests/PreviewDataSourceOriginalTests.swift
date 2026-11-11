import Domain
import TestDoubles
import TestSupport
import Testing

@testable import PreviewDataSource

/// The original a draw is given. A frame presented alone is its own original;
/// one presented with an original is drawn by the split, which binds it
/// (PreviewDataSourceSplitTests).
@Suite("PreviewDataSourceImpl original", .timeLimit(.minutes(1)))
struct PreviewDataSourceOriginalTests {
    private let rig = PreviewRig()

    @Test("a drawn frame is passed to the gateway as its own original, the same handle as its texture")
    func originalIsTheFrameTexture() async throws {
        try await rig.attach()
        rig.executor.drain()
        rig.present(try rig.frame(1))
        rig.executor.drain()

        let draw = try #require(rig.preview.pending.first)
        #expect(rig.frameNumber(of: draw) == 1)
        #expect(ObjectIdentifier(draw.original) == ObjectIdentifier(draw.texture))
    }

    @Test("every draw passes the frame it shows as its original, frame after frame")
    func originalFollowsEachFrame() async throws {
        try await rig.attach()
        rig.executor.drain()

        for number in 1...2 {
            rig.present(try rig.frame(number))
            rig.executor.drain()
            let draw = try #require(rig.preview.pending.first)
            #expect(rig.frameNumber(of: draw) == number)
            #expect(ObjectIdentifier(draw.original) == ObjectIdentifier(draw.texture))
            rig.preview.complete(draw)
            rig.executor.drain()
        }
        #expect(rig.preview.draws.count == 2)
        #expect(rig.textures.isBalanced)
    }

    @Test("a frame presented with an original is drawn once, and completes once after the draw with both leases given back")
    func originalDoesNotAddADraw() async throws {
        try await rig.attach()
        rig.executor.drain()
        rig.present(try rig.frame(1), original: try rig.frame(2))
        rig.executor.drain()

        let draw = try #require(rig.preview.pending.first)
        #expect(rig.frameNumber(of: draw) == 1)
        #expect(rig.completed.count == 0, "both surfaces are borrowed until the GPU is done")
        rig.preview.complete(draw)
        rig.executor.drain()

        #expect(rig.completed.values == [1])
        #expect(rig.preview.draws.count == 1)
        #expect(rig.textures.bindCount == 2, "the original is bound beside the frame for the split")
        #expect(rig.textures.isBalanced)
        #expect(rig.pool.liveCount == 0)
    }

    @Test("a frame with an original that is replaced while it waits completes once, undrawn, with both leases given back")
    func replacedFrameWithOriginalIsNotDrawn() async throws {
        try await rig.attach()
        rig.executor.drain()
        rig.present(try rig.frame(1))
        rig.executor.drain()
        let first = try #require(rig.preview.pending.first)

        rig.present(try rig.frame(2), original: try rig.frame(3))
        rig.present(try rig.frame(4))
        rig.executor.drain()

        #expect(rig.completed.values == [2], "the waiting frame and its original are replaced at once, undrawn")
        #expect(rig.preview.pending.count == 1, "one draw in flight")

        rig.preview.complete(first)
        rig.executor.drain()
        let next = try #require(rig.preview.pending.first)
        #expect(rig.frameNumber(of: next) == 4)
        rig.preview.complete(next)
        rig.executor.drain()

        #expect(rig.completed.values == [2, 1, 4])
        #expect(rig.preview.draws.values.compactMap(rig.frameNumber(of:)) == [1, 4])
        #expect(rig.textures.bindCount == 2, "the replaced frame and its original are never bound")
        #expect(rig.textures.isBalanced)
        #expect(rig.pool.liveCount == 0)
    }
}
