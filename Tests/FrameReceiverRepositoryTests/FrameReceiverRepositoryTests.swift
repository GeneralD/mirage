import Dependencies
import Domain
import FrameReceiverRepository
import TestDoubles
import TestSupport
import Testing

@Suite("FrameReceiverRepository", .timeLimit(.minutes(1)))
struct FrameReceiverRepositoryTests {
    private struct Rig {
        let receiver = FakeFrameReceiver()
        let pool = FakeSurfacePool(capacity: 1)
        let errors = RecordingLog()
        let frames = Collector<FrameRef>()
        let events = Collector<ReceiverEvent>()
        let subject: FrameReceiverRepositoryImpl

        init() {
            let receiver = receiver
            let pool = pool
            let errors = errors
            subject = withDependencies {
                $0.frameReceiver = receiver
                $0.surfacePool = pool
                $0.errorLog = errors
            } operation: {
                FrameReceiverRepositoryImpl()
            }
        }

        func start() -> Task<Void, any Error> {
            let subject = subject
            let frames = frames
            let events = events
            return Task { try await subject.start(onFrame: { frames.append($0) }, onEvent: { events.append($0) }) }
        }

        func finish(_ task: Task<Void, any Error>) async throws {
            subject.stop()
            try await task.value
        }
    }

    @Test("a received surface is adopted into the pool and handed up with its timing")
    func adopts() async throws {
        let rig = Rig()
        let task = rig.start()
        await rig.receiver.started.waitForCount(1)

        let handle = FakeSurfaceHandle(id: 1)
        let descriptor = SurfaceDescriptor.bgra(width: 640, height: 360)
        let time = HostTimestamp(nanoseconds: 123)
        rig.receiver.emit(handle, descriptor: descriptor, at: time)

        let frame = try #require(rig.frames.values.first)
        #expect(frame.descriptor == descriptor)
        #expect(frame.presentationTime == time)
        #expect(rig.pool.handle(for: frame.token) === handle)
        #expect(rig.pool.descriptor(for: frame.token) == descriptor)
        #expect(rig.pool.liveCount == 1)
        try await rig.finish(task)
    }

    @Test("an exhausted pool drops the frame, logs it, and recovers once a lease is released")
    func poolExhausted() async throws {
        let rig = Rig()
        let task = rig.start()
        await rig.receiver.started.waitForCount(1)

        rig.receiver.emit(FakeSurfaceHandle(id: 1), at: HostTimestamp(nanoseconds: 1))
        rig.receiver.emit(FakeSurfaceHandle(id: 2), at: HostTimestamp(nanoseconds: 2))

        #expect(rig.frames.count == 1)
        #expect(rig.errors.messages(in: .receiver).count == 1)
        #expect(rig.pool.liveCount == 1)

        let first = try #require(rig.frames.values.first)
        #expect(rig.pool.release(first.token))
        rig.receiver.emit(FakeSurfaceHandle(id: 3), at: HostTimestamp(nanoseconds: 3))

        #expect(rig.frames.values.map(\.presentationTime) == [HostTimestamp(nanoseconds: 1), HostTimestamp(nanoseconds: 3)])
        try await rig.finish(task)
    }

    @Test("receiver events pass through untouched")
    func eventsPassThrough() async throws {
        let rig = Rig()
        let task = rig.start()
        await rig.receiver.started.waitForCount(1)
        let sent: [ReceiverEvent] = [.listening, .hostConnected, .hostLost(.frameGap(.seconds(2))), .frameDropped(.staleToken)]

        for event in sent { rig.receiver.emit(event) }

        #expect(rig.events.values == sent)
        try await rig.finish(task)
    }

    @Test("stop is forwarded to the receiver, which ends start")
    func stopForwards() async throws {
        let rig = Rig()
        let task = rig.start()
        await rig.receiver.started.waitForCount(1)

        try await rig.finish(task)

        #expect(rig.receiver.stopCount == 1)
    }

    @Test("a receiver that cannot start fails start with its error")
    func startFails() async {
        let rig = Rig()
        rig.receiver.failStart(with: .registerFailed(code: 7))

        let error = await #expect(throws: MachError.self) { try await rig.start().value }

        #expect(error == .registerFailed(code: 7))
        #expect(rig.frames.values.isEmpty)
    }
}
