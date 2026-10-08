import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FrameTransportDataSource send", .timeLimit(.minutes(1)))
struct FrameTransportSendTests {
    private let port = MachPortToken(name: 0x2000)

    @Test("a frame before connect is dropped as notConnected and costs no right")
    func beforeConnect() throws {
        let fixture = TransportFixture()

        let outcome = fixture.subject.send(try fixture.makeSurface(), descriptor: .hd720, presentationTime: .zero)

        #expect(outcome == .dropped(.notConnected))
        #expect(fixture.messaging.sent.count == 0)
        #expect(fixture.surfaces.outstandingRights == 0)
    }

    @Test("a frame after connect goes to the connected port with its descriptor, timestamp and the surface's own right")
    func afterConnect() async throws {
        let fixture = TransportFixture()
        try await fixture.connect()
        let surface = try fixture.makeSurface()
        let descriptor = SurfaceDescriptor.bgra(width: 640, height: 360)
        let stamp = HostTimestamp(nanoseconds: 987_654)

        let outcome = fixture.subject.send(surface, descriptor: descriptor, presentationTime: stamp)

        let sent = try #require(fixture.messaging.sent.last)
        #expect(outcome == .sent)
        #expect(sent.port == port)
        #expect(sent.message.descriptor == descriptor)
        #expect(sent.message.presentationTime == stamp)
        #expect(try fixture.surfaces.resolve(sent.message.surface) === surface)
    }

    @Test("a surface the gateway cannot export is dropped with code -1 and logged")
    func exportFails() async throws {
        let fixture = TransportFixture()
        try await fixture.connect()

        let outcome = fixture.subject.send(ForeignHandle(), descriptor: .hd720, presentationTime: .zero)

        #expect(outcome == .dropped(.sendFailed(code: -1)))
        #expect(fixture.messaging.sent.count == 0)
        #expect(fixture.log.contains("no send right"))
    }

    @Test("a lost destination releases the port, reports it, and later frames are notConnected")
    func destinationLost() async throws {
        let fixture = TransportFixture()
        try await fixture.connect()
        fixture.messaging.failSend(with: .destinationLost)

        let outcome = fixture.subject.send(try fixture.makeSurface(), descriptor: .hd720, presentationTime: .zero)

        #expect(outcome == .dropped(.extensionUnavailable))
        #expect(!fixture.subject.isConnected)
        #expect(fixture.bootstrap.deallocated.values == [port])
        #expect(fixture.events.values == [.connected, .disconnected(.destinationLost)])
        #expect(fixture.log.contains("destination lost"))
        fixture.messaging.failSend(with: nil)
        #expect(fixture.subject.send(try fixture.makeSurface(), descriptor: .hd720, presentationTime: .zero) == .dropped(.notConnected))
    }

    @Test("after a lost destination a new connect makes the link usable again")
    func recovers() async throws {
        let fixture = TransportFixture()
        try await fixture.connect()
        fixture.messaging.failSend(with: .destinationLost)
        _ = fixture.subject.send(try fixture.makeSurface(), descriptor: .hd720, presentationTime: .zero)
        fixture.messaging.failSend(with: nil)

        try await fixture.connect()

        #expect(fixture.subject.send(try fixture.makeSurface(), descriptor: .hd720, presentationTime: .zero) == .sent)
        #expect(fixture.messaging.sent.last?.port == MachPortToken(name: 0x2001))
    }

    @Test("a refused send drops the frame with the raw code, keeps the link and logs the failure")
    func sendRefused() async throws {
        let fixture = TransportFixture()
        try await fixture.connect()
        fixture.messaging.failSend(with: .sendFailed(code: 5))

        let outcome = fixture.subject.send(try fixture.makeSurface(), descriptor: .hd720, presentationTime: .zero)

        #expect(outcome == .dropped(.sendFailed(code: 5)))
        #expect(fixture.subject.isConnected)
        #expect(fixture.bootstrap.deallocated.count == 0)
        #expect(fixture.log.contains("code 5"))
    }

    @Test("an unexpected gateway error drops the frame with code -1 and keeps the link")
    func unexpectedError() async throws {
        let fixture = TransportFixture()
        try await fixture.connect()
        fixture.messaging.failSend(with: .malformedMessage)

        let outcome = fixture.subject.send(try fixture.makeSurface(), descriptor: .hd720, presentationTime: .zero)

        #expect(outcome == .dropped(.sendFailed(code: -1)))
        #expect(fixture.subject.isConnected)
        #expect(fixture.log.contains("send failed"))
    }

    @Test("frames reach the gateway in order with their timestamps untouched", arguments: standardSeeds)
    func order(seed: UInt64) async throws {
        var generator = SeededGenerator(seed: seed)
        let stamps = (0..<Int.random(in: 1...20, using: &generator)).map { _ in
            HostTimestamp(nanoseconds: UInt64.random(in: 0...UInt64.max, using: &generator))
        }
        let fixture = TransportFixture()
        try await fixture.connect()

        let outcomes = try stamps.map { fixture.subject.send(try fixture.makeSurface(), descriptor: .hd720, presentationTime: $0) }

        #expect(outcomes == stamps.map { _ in SendOutcome.sent })
        #expect(fixture.messaging.sent.values.map(\.message.presentationTime) == stamps)
    }
}
