import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing
import VirtualCameraRepository

@Suite("VirtualCameraRepository", .timeLimit(.minutes(1)))
struct VirtualCameraSinkTests {
    private struct Fixture {
        let transport = FakeFrameTransport()
        let pool = FakeSurfacePool(capacity: 32)
        let log = RecordingLog()
        let subject: VirtualCameraRepositoryImpl

        init() {
            let transport = transport
            let pool = pool
            let log = log
            subject = withDependencies {
                $0.frameTransport = transport
                $0.surfacePool = pool
                $0.errorLog = log
            } operation: {
                VirtualCameraRepositoryImpl()
            }
        }

        func frame(at nanoseconds: UInt64 = 7) throws -> FrameRef {
            let token = try #require(try pool.allocate(.hd720))
            return FrameRef(token: token, descriptor: .hd720, presentationTime: HostTimestamp(nanoseconds: nanoseconds))
        }
    }

    @Test("connect and disconnect forward to the transport")
    func lifecycle() async throws {
        let fixture = Fixture()

        try await fixture.subject.connect()
        #expect(fixture.transport.connectCount == 1)
        #expect(fixture.transport.isConnected)

        fixture.subject.disconnect()
        #expect(fixture.transport.disconnectCount == 1)
        #expect(!fixture.transport.isConnected)
    }

    @Test("a failed connect surfaces the transport's error")
    func connectFails() async {
        let fixture = Fixture()
        fixture.transport.failConnect(with: .lookupFailed(code: 1102))

        await #expect(throws: MachError.lookupFailed(code: 1102)) { try await fixture.subject.connect() }
    }

    @Test("transport events reach the observer")
    func observe() async throws {
        let fixture = Fixture()
        let events = Collector<FrameTransportEvent>()

        fixture.subject.observe { events.append($0) }
        try await fixture.subject.connect()
        fixture.transport.emit(.disconnected(.destinationLost))

        #expect(events.values == [.connected, .disconnected(.destinationLost)])
    }

    @Test("a live frame is sent as the pooled surface with its own descriptor and timestamp")
    func sendsResolvedSurface() async throws {
        let fixture = Fixture()
        try await fixture.subject.connect()
        let frame = try fixture.frame(at: 31_415)

        let outcome = fixture.subject.send(frame)

        let sent = try #require(fixture.transport.sent.last)
        #expect(outcome == .sent)
        #expect(sent.surface === fixture.pool.handle(for: frame.token))
        #expect(sent.descriptor == frame.descriptor)
        #expect(sent.presentationTime == frame.presentationTime)
    }

    @Test("a released token is dropped as staleToken, logged, and never reaches the transport")
    func staleToken() async throws {
        let fixture = Fixture()
        try await fixture.subject.connect()
        let frame = try fixture.frame()
        fixture.pool.release(frame.token)

        let outcome = fixture.subject.send(frame)

        #expect(outcome == .dropped(.staleToken))
        #expect(fixture.transport.sent.count == 0)
        #expect(fixture.log.contains("stale"))
    }

    @Test("the transport's drop reason is returned unchanged")
    func transportDrops() async throws {
        let fixture = Fixture()
        let frame = try fixture.frame()
        #expect(fixture.subject.send(frame) == .dropped(.notConnected))

        try await fixture.subject.connect()
        fixture.transport.dropSends(with: .poolExhausted)
        #expect(fixture.subject.send(frame) == .dropped(.poolExhausted))
    }

    @Test("a frame is sent exactly when its lease is still held", arguments: standardSeeds)
    func sentIffLive(seed: UInt64) async throws {
        var generator = SeededGenerator(seed: seed)
        let fixture = Fixture()
        try await fixture.subject.connect()
        let frames = try (0..<Int.random(in: 1...16, using: &generator)).map { try fixture.frame(at: UInt64($0)) }
        let released = frames.map { _ in Bool.random(using: &generator) }
        for (frame, isReleased) in zip(frames, released) where isReleased { fixture.pool.release(frame.token) }

        let outcomes = frames.map(fixture.subject.send)

        #expect(outcomes == released.map { $0 ? SendOutcome.dropped(.staleToken) : .sent })
        #expect(fixture.transport.sent.count == released.filter { !$0 }.count)
    }
}
