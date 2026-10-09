import Domain
import PreviewRepository
import TestDoubles
import TestSupport
import Testing

@Suite("DiscardingPreviewSink", .timeLimit(.minutes(1)))
struct DiscardingPreviewSinkTests {
    private let subject = DiscardingPreviewSink()
    private let frame = FrameRef(token: SurfaceToken(index: 0, generation: 1), descriptor: .hd720, presentationTime: .zero)

    @Test("present calls the completion exactly once, before returning")
    func presentCompletesAtOnce() {
        let completions = Collector<Void>()
        subject.present(frame) { completions.append(()) }
        #expect(completions.count == 1)
    }

    @Test("every frame completes on its own, so leases are never held")
    func eachFrameCompletes() {
        let completions = Collector<UInt64>()
        let frames = (1...3).map {
            FrameRef(token: SurfaceToken(index: $0, generation: 1), descriptor: .hd720, presentationTime: HostTimestamp(nanoseconds: UInt64($0)))
        }
        for frame in frames { subject.present(frame) { completions.append(frame.presentationTime.nanoseconds) } }
        #expect(completions.values == [1, 2, 3])
    }

    @Test("attach accepts any target; there is nothing to draw on")
    func attachAcceptsAnyTarget() throws {
        try subject.attach(FakePreviewTargetHandle())
    }
}
