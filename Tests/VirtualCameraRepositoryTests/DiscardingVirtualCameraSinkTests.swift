import Domain
import TestSupport
import Testing
import VirtualCameraRepository

@Suite("DiscardingVirtualCameraSink", .timeLimit(.minutes(1)))
struct DiscardingVirtualCameraSinkTests {
    private let subject = DiscardingVirtualCameraSink()

    private func frame(token: SurfaceToken = SurfaceToken(index: 0, generation: 1), at nanoseconds: UInt64 = 7) -> FrameRef {
        FrameRef(token: token, descriptor: .hd720, presentationTime: HostTimestamp(nanoseconds: nanoseconds))
    }

    @Test("connect succeeds at once, before and after a disconnect")
    func connectSucceeds() async throws {
        try await subject.connect()
        subject.disconnect()
        try await subject.connect()
    }

    @Test("a frame is reported as sent, whatever the link has done")
    func sendsAreSuccessful() async throws {
        #expect(subject.send(frame()) == .sent, "sent before any connect: there is no link to wait for")

        try await subject.connect()
        #expect(subject.send(frame(at: 2)) == .sent)

        subject.disconnect()
        #expect(subject.send(frame(at: 3)) == .sent, "nothing here can be lost, so a disconnect changes nothing")
    }

    @Test("a token no pool ever issued is sent too: the lease is the caller's and nothing here resolves it")
    func tokensAreNotResolved() {
        #expect(subject.send(frame(token: SurfaceToken(index: 4_096, generation: 99))) == .sent)
    }

    @Test("the observer hears nothing: no event is ever raised")
    func observerStaysSilent() async throws {
        let events = Collector<FrameTransportEvent>()
        subject.observe { events.append($0) }

        try await subject.connect()
        _ = subject.send(frame())
        subject.disconnect()

        #expect(events.count == 0, "a `connected` event would make the pipeline log a connection to an extension that does not exist")
    }
}
