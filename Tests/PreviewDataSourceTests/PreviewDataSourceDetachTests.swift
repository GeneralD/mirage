import Domain
import TestDoubles
import TestSupport
import Testing

@testable import PreviewDataSource

@Suite("PreviewDataSourceImpl detach", .timeLimit(.minutes(1)))
struct PreviewDataSourceDetachTests {
    private let rig = PreviewRig()

    @Test("a frame presented after detach is not drawn and completes once at the next drain")
    func presentAfterDetachIsNotDrawn() async throws {
        let target = FakePreviewTargetHandle()
        try await rig.attach(target)
        rig.executor.drain()

        rig.subject.detach(target)
        rig.present(try rig.frame(1))
        #expect(rig.completed.count == 0, "nothing happens before the executor runs")

        rig.executor.drain()

        #expect(rig.completed.values == [1])
        #expect(rig.preview.draws.count == 0)
        #expect(rig.textures.bindCount == 0)
        #expect(rig.pool.liveCount == 0)
    }

    @Test("detaching while one frame draws and another waits completes the waiting frame at once, undrawn")
    func waitingFrameCompletesOnDetach() async throws {
        let target = FakePreviewTargetHandle()
        try await rig.attach(target)
        rig.executor.drain()
        rig.present(try rig.frame(1))
        rig.present(try rig.frame(2))
        rig.executor.drain()
        #expect(rig.completed.count == 0, "frame 1 is drawing and frame 2 waits")

        rig.subject.detach(target)
        rig.executor.drain()

        #expect(rig.completed.values == [2])
        #expect(rig.preview.pending.count == 1, "frame 1 is still in flight")

        rig.preview.complete(try #require(rig.preview.pending.first))
        rig.executor.drain()

        #expect(rig.completed.values == [2, 1], "frame 1 completes when the GPU is done")
        #expect(rig.preview.draws.count == 1, "frame 2 is never drawn")
        #expect(rig.textures.isBalanced)
        #expect(rig.pool.liveCount == 0)
    }

    @Test("a draw in flight at detach is not stopped: its texture is unbound and its frame completes once, with no next draw")
    func drawInFlightFinishesOnDetach() async throws {
        let target = FakePreviewTargetHandle()
        try await rig.attach(target)
        rig.executor.drain()
        rig.present(try rig.frame(1))
        rig.executor.drain()
        let draw = try #require(rig.preview.pending.first)

        rig.subject.detach(target)
        rig.executor.drain()
        #expect(rig.preview.pending.count == 1, "the draw is not cancelled")
        #expect(rig.completed.count == 0, "the frame stays borrowed until the GPU is done")

        rig.preview.complete(draw)
        rig.executor.drain()

        #expect(rig.completed.values == [1])
        #expect(rig.textures.isBalanced)
        #expect(rig.pool.liveCount == 0)
        #expect(rig.preview.pending.count == 0, "no draw starts after the detach")
        #expect(rig.preview.draws.count == 1)
    }

    @Test("detaching a target that is not the attached one does nothing, and the attached target keeps drawing")
    func otherTargetIsNotReleased() async throws {
        let attached = FakePreviewTargetHandle()
        try await rig.attach(attached)
        rig.executor.drain()
        rig.present(try rig.frame(1))
        rig.present(try rig.frame(2))
        rig.executor.drain()

        rig.subject.detach(FakePreviewTargetHandle())
        rig.executor.drain()
        #expect(rig.completed.count == 0, "the waiting frame is not completed by another target's detach")

        rig.preview.complete(try #require(rig.preview.pending.first))
        rig.executor.drain()

        #expect(rig.completed.values == [1])
        let next = try #require(rig.preview.pending.first)
        #expect(rig.frameNumber(of: next) == 2, "the attached target still draws the waiting frame")
    }

    @Test("detaching with nothing attached does nothing and logs nothing")
    func detachWithNothingAttachedIsSilent() throws {
        rig.subject.detach(FakePreviewTargetHandle())
        rig.executor.drain()

        #expect(rig.completed.count == 0)
        #expect(rig.preview.draws.count == 0)
        #expect(rig.log.messages(in: .preview).isEmpty)
    }

    @Test("detaching twice completes the waiting frame once, and the second detach does nothing")
    func secondDetachIsNoOp() async throws {
        let target = FakePreviewTargetHandle()
        try await rig.attach(target)
        rig.executor.drain()
        rig.present(try rig.frame(1))
        rig.present(try rig.frame(2))
        rig.executor.drain()

        rig.subject.detach(target)
        rig.subject.detach(target)
        rig.executor.drain()
        #expect(rig.completed.values == [2], "the waiting frame completes once")

        rig.preview.complete(try #require(rig.preview.pending.first))
        rig.executor.drain()

        #expect(rig.completed.values == [2, 1], "no frame completes a second time")
        #expect(rig.preview.draws.count == 1)
    }

    @Test(
        "attaching again after a detach compiles the kernel again and draws from the next frame, growing the compile count by the same amount as the first attach"
    )
    func reattachAfterDetachRecompiles() async throws {
        let first = FakePreviewTargetHandle()
        try await rig.attach(first)
        rig.executor.drain()
        let afterFirstAttach = rig.compiler.calls.count
        #expect(afterFirstAttach > 0, "the first attach compiles the kernel")

        rig.subject.detach(first)
        rig.executor.drain()
        try await rig.attach(FakePreviewTargetHandle())
        rig.executor.drain()

        #expect(rig.compiler.calls.count == 2 * afterFirstAttach, "the re-attach compiles the kernel once more")

        rig.present(try rig.frame(1))
        rig.executor.drain()

        let draw = try #require(rig.preview.pending.first)
        let newLayer = try #require(rig.preview.prepared.values.last)
        #expect(ObjectIdentifier(draw.layer) == ObjectIdentifier(newLayer), "the next frame is drawn into the new attach")
        #expect(rig.frameNumber(of: draw) == 1)
    }
}
