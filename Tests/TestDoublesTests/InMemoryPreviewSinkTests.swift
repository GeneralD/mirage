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
        sink.present(frame(1)) { completions.append(()) }
        #expect(completions.count == 0)
        let presentation = try #require(sink.pending.first)
        #expect(presentation.frame == frame(1))

        #expect(sink.complete(presentation))
        #expect(completions.count == 1)
        #expect(!sink.complete(presentation))
        #expect(completions.count == 1)
        #expect(sink.pending.isEmpty)
    }

    @Test("frames are recorded in presentation order and complete in the order the test chooses")
    func outOfOrderCompletion() throws {
        let completed = Collector<Int>()
        for index in 1...3 { sink.present(frame(index)) { completed.append(index) } }
        #expect(sink.presented.values.map(\.frame.token.index) == [1, 2, 3])

        let pending = sink.pending
        sink.complete(pending[2])
        sink.complete(pending[0])
        #expect(completed.values == [3, 1])
        #expect(sink.pending.map(\.frame.token.index) == [2])
    }

    @Test("attach records the fake target and refuses a foreign one")
    func attach() throws {
        let target = FakePreviewTargetHandle()
        try sink.attach(target)
        #expect(sink.attached.first === target)

        #expect(throws: PreviewError.foreignTarget) { try sink.attach(ForeignPreviewTarget()) }
        #expect(sink.attached.count == 1)
    }
}

private final class ForeignPreviewTarget: PreviewTargetHandle, Sendable {
    var backing: AnyObject { self }
}
