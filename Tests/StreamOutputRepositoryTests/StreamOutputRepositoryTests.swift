import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import StreamOutputRepository

@Suite("StreamOutputRepository")
struct StreamOutputRepositoryTests {
    private struct Rig {
        let output = FakeStreamOutput()
        let pool = FakeSurfacePool()
        let log = RecordingLog()
        let subject: StreamOutputRepositoryImpl

        init() {
            let output = output
            let pool = pool
            let log = log
            subject = withDependencies {
                $0.streamOutput = output
                $0.surfacePool = pool
                $0.errorLog = log
            } operation: {
                StreamOutputRepositoryImpl()
            }
        }

        func adopt(at nanoseconds: UInt64, descriptor: SurfaceDescriptor = .hd720) throws -> (frame: FrameRef, surface: FakeSurfaceHandle) {
            let surface = FakeSurfaceHandle(id: 1)
            let token = try #require(pool.adopt(surface, descriptor: descriptor))
            return (FrameRef(token: token, descriptor: descriptor, presentationTime: HostTimestamp(nanoseconds: nanoseconds)), surface)
        }
    }

    @Test("start forwards the format, the frame rate and the event callback")
    func startForwards() throws {
        let rig = Rig()
        let events = Collector<StreamOutputEvent>()
        try rig.subject.start(descriptor: .bgra(width: 640, height: 360), frameRate: FrameRate(framesPerSecond: 15)) { events.append($0) }
        #expect(rig.output.descriptor == .bgra(width: 640, height: 360))
        #expect(rig.output.frameRate == FrameRate(framesPerSecond: 15))
        rig.output.setStreaming(true)
        #expect(events.values == [.streamStarted])
    }

    @Test("a failed start is rethrown")
    func startFailureIsRethrown() {
        let rig = Rig()
        rig.output.failStart(with: .providerSetupFailed("no service"))
        #expect(throws: StreamOutputError.providerSetupFailed("no service")) {
            try rig.subject.start(descriptor: .hd720, frameRate: .standard) { _ in }
        }
    }

    @Test("isStreaming follows the stream")
    func isStreamingForwards() throws {
        let rig = Rig()
        try rig.subject.start(descriptor: .hd720, frameRate: .standard) { _ in }
        #expect(!rig.subject.isStreaming)
        rig.output.setStreaming(true)
        #expect(rig.subject.isStreaming)
    }

    @Test("send resolves the lease and passes the surface, descriptor and presentation time on")
    func sendResolvesLease() throws {
        let rig = Rig()
        try rig.subject.start(descriptor: .hd720, frameRate: .standard) { _ in }
        rig.output.setStreaming(true)
        let descriptor = SurfaceDescriptor.bgra(width: 640, height: 360)
        let (frame, surface) = try rig.adopt(at: 42_000, descriptor: descriptor)
        #expect(rig.subject.send(frame) == .sent)
        let sent = try #require(rig.output.sent.last)
        #expect(sent.surface === surface)
        #expect(sent.descriptor == descriptor)
        #expect(sent.presentationTime == HostTimestamp(nanoseconds: 42_000))
    }

    @Test("the stream's own drop reason is passed back unchanged")
    func forwardsDropReason() throws {
        let rig = Rig()
        let (frame, _) = try rig.adopt(at: 1)
        #expect(rig.subject.send(frame) == .dropped(.noClient))
        #expect(rig.output.sent.count == 0)
        #expect(rig.log.entries.count == 0)
    }

    @Test("a token that no longer resolves is dropped as stale, logged, and never reaches the stream")
    func staleToken() throws {
        let rig = Rig()
        rig.output.setStreaming(true)
        let (frame, _) = try rig.adopt(at: 1)
        rig.pool.release(frame.token)
        #expect(rig.subject.send(frame) == .dropped(.staleToken))
        #expect(rig.output.sent.count == 0)
        #expect(rig.log.messages(in: .stream).count == 1)
    }

    @Test("a released slot's old token stays stale after the slot is reused")
    func reusedSlotDoesNotRevive() throws {
        let rig = Rig()
        rig.output.setStreaming(true)
        let (stale, _) = try rig.adopt(at: 1)
        rig.pool.release(stale.token)
        _ = try rig.adopt(at: 2)
        #expect(rig.subject.send(stale) == .dropped(.staleToken))
        #expect(rig.output.sent.count == 0)
    }
}
