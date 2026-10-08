import CameraDataSource
import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("CameraDataSource", .timeLimit(.minutes(1)))
struct CameraDataSourceTests {
    private struct Rig {
        let gateway = FakeCaptureSessionGateway()
        let executor = ManualFrameExecutor()
        let log = RecordingLog()
        let frames = Collector<IncomingSurface>()
        let ends = Collector<CaptureEnd>()
        let subject: CameraDataSourceImpl

        init() {
            let gateway = gateway
            let executor = executor
            let log = log
            subject = withDependencies {
                $0.captureSessionGateway = gateway
                $0.frameExecutor = executor
                $0.developerLog = log
            } operation: {
                CameraDataSourceImpl()
            }
        }

        func start() throws {
            let frames = frames
            let ends = ends
            try subject.start(descriptor: .hd720, onFrame: { frames.append($0) }, onEnd: { ends.append($0) })
        }

        func emit(_ id: UInt32, seconds: Double) {
            gateway.emit(FakeSurfaceHandle(id: id), seconds: seconds)
        }
    }

    @Test("start forwards the descriptor to the gateway")
    func startForwardsDescriptor() throws {
        let rig = Rig()
        try rig.start()
        #expect(rig.gateway.descriptor == .hd720)
        #expect(rig.gateway.startCount == 1)
    }

    @Test("frames reach the caller only after the executor drains")
    func framesWaitForExecutor() throws {
        let rig = Rig()
        try rig.start()
        rig.emit(1, seconds: 1.0)
        #expect(rig.frames.count == 0)
        #expect(rig.executor.pendingCount == 1)
        rig.executor.drain()
        #expect(rig.frames.count == 1)
    }

    @Test("the handle and descriptor pass through untouched")
    func passesSurfaceThrough() throws {
        let rig = Rig()
        try rig.start()
        let handle = FakeSurfaceHandle(id: 7)
        let descriptor = SurfaceDescriptor(width: 1280, height: 720, pixelFormat: .bgra32, bytesPerRow: 5_120 + 64)
        rig.gateway.emit(handle, descriptor: descriptor, seconds: 2.5)
        rig.executor.drain()
        let frame = try #require(rig.frames.last)
        #expect(frame.handle === handle)
        #expect(frame.descriptor == descriptor)
    }

    @Test("seconds convert to host-time nanoseconds without drifting", arguments: standardSeeds)
    func convertsSecondsToNanoseconds(seed: UInt64) throws {
        let rig = Rig()
        try rig.start()
        var generator = SeededGenerator(seed: seed)
        let seconds = Double.random(in: 0.001...100_000, using: &generator)
        rig.emit(1, seconds: seconds)
        rig.executor.drain()
        let frame = try #require(rig.frames.last)
        #expect(frame.presentationTime == HostTimestamp.seconds(seconds))
        #expect(abs(frame.presentationTime.seconds - seconds) < 0.000_001)
    }

    @Test("a PTS of 1.5 seconds maps to exactly 1_500_000_000 ns")
    func exactNanoseconds() throws {
        let rig = Rig()
        try rig.start()
        rig.emit(1, seconds: 1.5)
        rig.executor.drain()
        #expect(rig.frames.last?.presentationTime == HostTimestamp(nanoseconds: 1_500_000_000))
    }

    @Test("a frame older than the last accepted one is dropped and logged")
    func dropsOutOfOrder() throws {
        let rig = Rig()
        try rig.start()
        rig.emit(1, seconds: 2.0)
        rig.emit(2, seconds: 1.0)
        rig.executor.drain()
        #expect(rig.frames.count == 1)
        #expect(rig.log.messages(in: .camera).count == 1)
    }

    @Test("a frame with an equal PTS is dropped")
    func dropsEqualPTS() throws {
        let rig = Rig()
        try rig.start()
        rig.emit(1, seconds: 2.0)
        rig.emit(2, seconds: 2.0)
        rig.executor.drain()
        #expect(rig.frames.count == 1)
        #expect(rig.log.entries.count == 1)
    }

    @Test("a dropped frame does not move the monotonic floor")
    func droppedFrameKeepsFloor() throws {
        let rig = Rig()
        try rig.start()
        rig.emit(1, seconds: 5.0)
        rig.emit(2, seconds: 3.0)
        rig.emit(3, seconds: 4.0)
        rig.emit(4, seconds: 6.0)
        rig.executor.drain()
        #expect(rig.frames.values.map(\.presentationTime.nanoseconds) == [5_000_000_000, 6_000_000_000])
    }

    @Test("a negative PTS clamps to zero and is accepted as the first frame")
    func firstFrameAtZero() throws {
        let rig = Rig()
        try rig.start()
        rig.emit(1, seconds: -1)
        rig.executor.drain()
        #expect(rig.frames.last?.presentationTime == .zero)
    }

    @Test("end is delivered on the executor and resets the monotonic floor")
    func endResetsFloor() throws {
        let rig = Rig()
        try rig.start()
        rig.emit(1, seconds: 10.0)
        rig.executor.drain()
        rig.gateway.end(.deviceDisconnected)
        #expect(rig.ends.count == 0)
        rig.executor.drain()
        #expect(rig.ends.values == [.deviceDisconnected])
        try rig.start()
        rig.emit(2, seconds: 1.0)
        rig.executor.drain()
        #expect(rig.frames.count == 2)
        #expect(rig.log.entries.count == 0)
    }

    @Test("a start error from the gateway propagates")
    func startErrorPropagates() {
        let rig = Rig()
        rig.gateway.failStart(with: .configurationFailed("busy"))
        #expect(throws: CaptureSessionError.configurationFailed("busy")) { try rig.start() }
        #expect(rig.gateway.startCount == 1)
    }

    @Test("stop forwards to the gateway")
    func stopForwards() throws {
        let rig = Rig()
        try rig.start()
        rig.subject.stop()
        #expect(rig.gateway.stopCount == 1)
        #expect(!rig.gateway.isRunning)
    }
}
