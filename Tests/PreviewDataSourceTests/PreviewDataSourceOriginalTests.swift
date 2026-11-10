import Domain
import TestDoubles
import TestSupport
import Testing

@testable import PreviewDataSource

/// The original a draw is given. For now the frame is its own original: the
/// preview kernel does not read index 2 yet, so nothing is drawn differently.
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
}
