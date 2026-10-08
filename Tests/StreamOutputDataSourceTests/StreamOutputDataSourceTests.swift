import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import StreamOutputDataSource

@Suite("StreamOutputDataSource")
struct StreamOutputDataSourceTests {
    private struct Rig {
        let gateway = FakeStreamOutputGateway()
        let executor = ManualFrameExecutor()
        let log = RecordingLog()
        let events = Collector<StreamOutputEvent>()
        let subject: StreamOutputDataSourceImpl

        init() {
            let gateway = gateway
            let executor = executor
            let log = log
            subject = withDependencies {
                $0.streamOutputGateway = gateway
                $0.frameExecutor = executor
                $0.errorLog = log
                $0.developerLog = log
            } operation: {
                StreamOutputDataSourceImpl()
            }
        }

        func start(_ descriptor: SurfaceDescriptor = .hd720, frameRate: FrameRate = .standard) throws {
            let events = events
            try subject.start(descriptor: descriptor, frameRate: frameRate) { events.append($0) }
        }

        func clientStarts() {
            gateway.emit(.streamStarted)
            executor.drain()
        }

        func clientStops() {
            gateway.emit(.streamStopped)
            executor.drain()
        }

        func send(_ id: UInt32 = 1, descriptor: SurfaceDescriptor = .hd720, at nanoseconds: UInt64 = 1_000) -> SendOutcome {
            subject.send(FakeSurfaceHandle(id: id), descriptor: descriptor, presentationTime: HostTimestamp(nanoseconds: nanoseconds))
        }
    }

    @Test("start declares the product device with the given format and frame rate")
    func startForwardsFormat() throws {
        let rig = Rig()
        let descriptor = SurfaceDescriptor.bgra(width: 640, height: 360)
        try rig.start(descriptor, frameRate: FrameRate(framesPerSecond: 24))
        let started = try #require(rig.gateway.started)
        #expect(started.deviceName == ProductIdentity.displayName)
        #expect(started.descriptor == descriptor)
        #expect(started.frameRate == FrameRate(framesPerSecond: 24))
    }

    @Test("a failed start is rethrown")
    func startFailureIsRethrown() {
        let rig = Rig()
        rig.gateway.failStart(with: .providerSetupFailed("no service"))
        #expect(throws: StreamOutputError.providerSetupFailed("no service")) { try rig.start() }
        #expect(!rig.subject.isStreaming)
    }

    @Test("frames before the first client are dropped as noClient and never reach the gateway")
    func dropsBeforeClient() throws {
        let rig = Rig()
        try rig.start()
        #expect(!rig.subject.isStreaming)
        #expect(rig.send() == .dropped(.noClient))
        #expect(rig.gateway.sent.count == 0)
    }

    @Test("once a client streams, frames are sent with the same surface and presentation time")
    func sendsWhileStreaming() throws {
        let rig = Rig()
        try rig.start()
        rig.clientStarts()
        let surface = FakeSurfaceHandle(id: 7)
        let outcome = rig.subject.send(surface, descriptor: .hd720, presentationTime: HostTimestamp(nanoseconds: 33_000_000))
        #expect(rig.subject.isStreaming)
        #expect(outcome == .sent)
        let sent = try #require(rig.gateway.sent.last)
        #expect(sent.surface === surface)
        #expect(sent.presentationTime == HostTimestamp(nanoseconds: 33_000_000))
    }

    @Test("the stream stopping drops frames again")
    func dropsAfterClientStops() throws {
        let rig = Rig()
        try rig.start()
        rig.clientStarts()
        rig.clientStops()
        #expect(!rig.subject.isStreaming)
        #expect(rig.send() == .dropped(.noClient))
        #expect(rig.gateway.sent.count == 0)
    }

    @Test("start and stop reach the caller only after the executor ran them")
    func relaysEventsOnTheExecutor() throws {
        let rig = Rig()
        try rig.start()
        rig.gateway.emit(.streamStarted)
        #expect(rig.events.count == 0)
        #expect(!rig.subject.isStreaming)
        rig.executor.drain()
        rig.clientStops()
        #expect(rig.events.values == [.streamStarted, .streamStopped])
    }

    @Test("an event that arrives after the data source is gone is ignored")
    func ignoresEventsAfterRelease() throws {
        let gateway = FakeStreamOutputGateway()
        let executor = ManualFrameExecutor()
        let events = Collector<StreamOutputEvent>()
        try withDependencies {
            $0.streamOutputGateway = gateway
            $0.frameExecutor = executor
        } operation: {
            let subject = StreamOutputDataSourceImpl()
            try subject.start(descriptor: .hd720, frameRate: .standard) { events.append($0) }
        }
        gateway.emit(.streamStarted)
        #expect(executor.drain() == 0)
        #expect(events.count == 0)
    }

    @Test("state transitions are traced in the developer log")
    func logsTransitions() throws {
        let rig = Rig()
        try rig.start()
        rig.clientStarts()
        rig.clientStops()
        #expect(rig.log.messages(in: .stream) == ["client stream started", "client stream stopped"])
    }

    @Test("a frame whose geometry differs from the declared format is dropped and logged")
    func formatMismatch() throws {
        let rig = Rig()
        try rig.start()
        rig.clientStarts()
        #expect(rig.send(descriptor: .bgra(width: 640, height: 360)) == .dropped(.formatMismatch))
        #expect(rig.gateway.sent.count == 0)
        #expect(rig.log.contains("640x360"))
    }

    @Test("a different row stride alone is not a mismatch")
    func strideOnlyDifferenceIsSent() throws {
        let rig = Rig()
        try rig.start()
        rig.clientStarts()
        let padded = SurfaceDescriptor(width: 1280, height: 720, pixelFormat: .bgra32, bytesPerRow: 1280 * 4 + 64)
        #expect(rig.send(descriptor: padded) == .sent)
    }

    @Test("a sample-buffer failure becomes sendFailed with its code, and is logged")
    func sampleBufferFailureKeepsCode() throws {
        let rig = Rig()
        try rig.start()
        rig.clientStarts()
        rig.gateway.failSend(with: .sampleBufferFailed(code: -6661))
        #expect(rig.send() == .dropped(.sendFailed(code: -6661)))
        #expect(rig.log.contains("-6661"))
    }

    @Test("any other gateway failure becomes sendFailed(-1)")
    func otherFailureUsesMinusOne() throws {
        let rig = Rig()
        try rig.start()
        rig.clientStarts()
        rig.gateway.failSend(with: .notStarted)
        #expect(rig.send() == .dropped(.sendFailed(code: -1)))
        #expect(rig.log.entries.count == 2)
    }

    @Test("a send failure does not stop later frames from going out", arguments: standardSeeds)
    func recoversAfterFailure(seed: UInt64) throws {
        var generator = SeededGenerator(seed: seed)
        let rig = Rig()
        try rig.start()
        rig.clientStarts()
        let failures = (0..<16).map { _ in Bool.random(using: &generator) }
        let outcomes = failures.map { fails -> SendOutcome in
            rig.gateway.failSend(with: fails ? .sampleBufferFailed(code: 1) : nil)
            return rig.send()
        }
        #expect(outcomes == failures.map { $0 ? .dropped(.sendFailed(code: 1)) : .sent })
        #expect(rig.gateway.sent.count == failures.filter { !$0 }.count)
    }

    @Test("sends succeed exactly while the last client event was a start", arguments: standardSeeds)
    func sendFollowsLastEvent(seed: UInt64) throws {
        var generator = SeededGenerator(seed: seed)
        let rig = Rig()
        try rig.start()
        let steps = (0..<24).map { _ in Int.random(in: 0..<3, using: &generator) }
        let streamingAfter = steps.reduce(into: (streaming: false, sentCount: 0)) { model, step in
            switch step {
            case 0:
                rig.clientStarts()
                model.streaming = true
            case 1:
                rig.clientStops()
                model.streaming = false
            default:
                let outcome = rig.send()
                #expect(outcome == (model.streaming ? .sent : .dropped(.noClient)))
                model.sentCount += model.streaming ? 1 : 0
            }
        }
        #expect(rig.subject.isStreaming == streamingAfter.streaming)
        #expect(rig.gateway.sent.count == streamingAfter.sentCount)
    }
}
