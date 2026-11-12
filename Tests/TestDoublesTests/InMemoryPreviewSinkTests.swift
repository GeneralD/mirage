import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("InMemoryPreviewSink", .timeLimit(.minutes(1)))
struct InMemoryPreviewSinkTests {
    private let sink = InMemoryPreviewSink()

    private func frame(_ index: Int) -> FrameRef {
        FrameRef(token: SurfaceToken(index: index, generation: 1), descriptor: .hd720, presentationTime: HostTimestamp(nanoseconds: UInt64(index)))
    }

    @Test("present holds the completion until the test releases it, exactly once")
    func completionIsHeld() throws {
        let completions = Collector<Void>()
        sink.present(frame(1), original: nil) { completions.append(()) }
        #expect(completions.count == 0)
        let presentation = try #require(sink.pending.first)
        #expect(presentation.frame == frame(1))

        #expect(sink.complete(presentation))
        #expect(completions.count == 1)
        #expect(!sink.complete(presentation))
        #expect(completions.count == 1)
        #expect(sink.pending.isEmpty)
    }

    @Test("present keeps the original it is given on the presentation, and its completion is held and returns true exactly once")
    func originalIsRecorded() throws {
        let completions = Collector<Void>()
        sink.present(frame(1), original: frame(2)) { completions.append(()) }
        let presentation = try #require(sink.pending.first)
        #expect(presentation.original == frame(2))
        #expect(presentation.frame == frame(1), "the original does not replace the frame")

        #expect(sink.complete(presentation))
        #expect(!sink.complete(presentation))
        #expect(completions.count == 1)
    }

    @Test("present with no original records nil on the presentation")
    func missingOriginalIsNil() throws {
        sink.present(frame(1), original: nil) {}
        let presentation = try #require(sink.presented.values.first)
        #expect(presentation.original == nil)
    }

    @Test("frames are recorded in presentation order and complete in the order the test chooses")
    func outOfOrderCompletion() throws {
        let completed = Collector<Int>()
        for index in 1...3 { sink.present(frame(index), original: nil) { completed.append(index) } }
        #expect(sink.presented.values.map(\.frame.token.index) == [1, 2, 3])

        let pending = sink.pending
        sink.complete(pending[2])
        sink.complete(pending[0])
        #expect(completed.values == [3, 1])
        #expect(sink.pending.map(\.frame.token.index) == [2])
    }

    @Test("a presentation from another sink completes nothing here")
    func foreignPresentationIsRefused() throws {
        let other = InMemoryPreviewSink()
        let completions = Collector<Void>()
        sink.present(frame(1), original: nil) { completions.append(()) }
        other.present(frame(1), original: nil) {}
        // Both sinks number their first presentation 1, so only provenance tells them apart.
        let stranger = try #require(other.pending.first)
        #expect(stranger.id == sink.pending.first?.id)

        #expect(!sink.complete(stranger))
        #expect(completions.count == 0)
        #expect(sink.pending.count == 1, "the sink's own presentation is still pending")
        #expect(other.pending.count == 1)
    }

    @Test("attach records the fake target and refuses a foreign one")
    func attach() throws {
        let target = FakePreviewTargetHandle()
        try sink.attach(target)
        #expect(sink.attached.first === target)

        #expect(throws: PreviewError.foreignTarget) { try sink.attach(ForeignPreviewTarget()) }
        #expect(sink.attached.count == 1)
    }

    @Test("holding once attached: until a target is attached every frame completes inside present, is recorded and cannot complete again")
    func completesAtOnceUntilAttached() throws {
        let sink = InMemoryPreviewSink(holding: .onceAttached)
        let completions = Collector<Int>()
        sink.present(frame(1), original: nil) { completions.append(1) }
        #expect(completions.values == [1], "completed before present returned")
        #expect(sink.presented.values.map(\.frame) == [frame(1)])
        #expect(sink.pending.isEmpty)
        let early = try #require(sink.presented.values.first)
        #expect(!sink.complete(early), "a frame that completed at once is not completed twice")

        #expect(throws: PreviewError.foreignTarget) { try sink.attach(ForeignPreviewTarget()) }
        sink.present(frame(2), original: nil) { completions.append(2) }
        #expect(completions.values == [1, 2], "a refused attach leaves the sink completing at once")

        try sink.attach(FakePreviewTargetHandle())
        sink.present(frame(3), original: nil) { completions.append(3) }
        #expect(completions.values == [1, 2], "once attached the completion is held")
        let held = try #require(sink.pending.first)
        #expect(held.frame == frame(3))
        #expect(sink.complete(held))
        #expect(completions.values == [1, 2, 3])
        #expect(sink.presented.values.map(\.frame) == [frame(1), frame(2), frame(3)])
    }

    @Test("detach records the fake target and keeps the attach history")
    func detachIsRecorded() throws {
        let target = FakePreviewTargetHandle()
        try sink.attach(target)
        sink.detach(target)

        #expect(sink.detached.map(ObjectIdentifier.init) == [ObjectIdentifier(target)])
        #expect(sink.attached.map(ObjectIdentifier.init) == [ObjectIdentifier(target)])
    }

    @Test("after the attached target is detached, a frame completes inside present again, as before any attach")
    func detachedTargetCompletesFramesAtOnce() throws {
        let sink = InMemoryPreviewSink(holding: .onceAttached)
        let target = FakePreviewTargetHandle()
        try sink.attach(target)
        sink.detach(target)

        let completions = Collector<Int>()
        sink.present(frame(1), original: nil) { completions.append(1) }
        #expect(completions.values == [1], "completed before present returned")
        #expect(sink.pending.isEmpty)
    }

    @Test("detaching a target other than the attached one records the call and keeps the attachment, so a later frame stays held")
    func detachingAnotherTargetKeepsAttachment() throws {
        let sink = InMemoryPreviewSink(holding: .onceAttached)
        let attached = FakePreviewTargetHandle()
        let stranger = FakePreviewTargetHandle()
        try sink.attach(attached)
        sink.detach(stranger)

        #expect(sink.detached.map(ObjectIdentifier.init) == [ObjectIdentifier(stranger)], "the call is recorded whether or not it unbinds")
        sink.present(frame(1), original: nil) {}
        #expect(sink.pending.map(\.frame) == [frame(1)], "the attached target still holds the frame")
    }

    @Test("a presentation held when its target is detached stays pending until complete, which returns true exactly once")
    func heldPresentationOutlivesDetach() throws {
        let target = FakePreviewTargetHandle()
        try sink.attach(target)
        let completions = Collector<Void>()
        sink.present(frame(1), original: nil) { completions.append(()) }
        sink.detach(target)

        #expect(completions.count == 0, "detach does not complete a held frame")
        let presentation = try #require(sink.pending.first)
        #expect(sink.complete(presentation))
        #expect(!sink.complete(presentation))
        #expect(completions.count == 1)
    }

    @Test("with holding always, detaching the attached target leaves every later frame held")
    func alwaysHoldingIgnoresDetach() throws {
        let target = FakePreviewTargetHandle()
        try sink.attach(target)
        sink.detach(target)
        sink.present(frame(1), original: nil) {}

        #expect(sink.pending.map(\.frame) == [frame(1)])
    }

    @Test("a frame presented after the target is detached and attached again is held again")
    func reattachHoldsFramesAgain() throws {
        let sink = InMemoryPreviewSink(holding: .onceAttached)
        let first = FakePreviewTargetHandle()
        try sink.attach(first)
        sink.detach(first)
        sink.present(frame(1), original: nil) {}
        #expect(sink.pending.isEmpty)

        try sink.attach(FakePreviewTargetHandle())
        sink.present(frame(2), original: nil) {}
        #expect(sink.pending.map(\.frame) == [frame(2)])
    }

    @Test("detaching a target that is not a fake records nothing and lets go of nothing")
    func foreignDetachIsIgnored() throws {
        let sink = InMemoryPreviewSink(holding: .onceAttached)
        try sink.attach(FakePreviewTargetHandle())
        sink.detach(ForeignPreviewTarget())

        #expect(sink.detached.isEmpty)
        sink.present(frame(1), original: nil) {}
        #expect(sink.pending.map(\.frame) == [frame(1)], "the attached target is still attached, so the frame is held")
    }
}

private final class ForeignPreviewTarget: PreviewTargetHandle, Sendable {
    var backing: AnyObject { self }
}
