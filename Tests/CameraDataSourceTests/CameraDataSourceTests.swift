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
            // Starting queues the session bookkeeping on the executor; settle it so tests count frames only.
            executor.drain()
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

    @Test("whole nanoseconds survive the seconds round trip exactly", arguments: standardSeeds)
    func convertsSecondsToNanoseconds(seed: UInt64) throws {
        let rig = Rig()
        try rig.start()
        var generator = SeededGenerator(seed: seed)
        let nanoseconds = UInt64.random(in: 1_000_000...100_000_000_000_000, using: &generator)
        rig.emit(1, seconds: Double(nanoseconds) / 1_000_000_000)
        rig.executor.drain()
        #expect(rig.frames.last?.presentationTime.nanoseconds == nanoseconds)
    }

    @Test("sub-nanosecond remainders round to the nearest nanosecond")
    func roundsToNearestNanosecond() throws {
        let rig = Rig()
        try rig.start()
        rig.emit(1, seconds: 1.000_000_000_7)
        rig.emit(2, seconds: 1.000_000_001_3)
        rig.executor.drain()
        #expect(rig.frames.values.map(\.presentationTime.nanoseconds) == [1_000_000_001])
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

    @Test(
        "end is delivered on the executor and resets the monotonic floor for every reason",
        arguments: [CaptureEnd.stopped, .deviceDisconnected, .runtimeError("boom")]
    )
    func endResetsFloor(reason: CaptureEnd) throws {
        let rig = Rig()
        try rig.start()
        rig.emit(1, seconds: 10.0)
        rig.executor.drain()
        rig.gateway.end(reason)
        #expect(rig.ends.count == 0)
        rig.executor.drain()
        #expect(rig.ends.values == [reason])
        // No restart: the very next frame, older than the last one, is accepted.
        rig.emit(2, seconds: 1.0)
        rig.executor.drain()
        #expect(rig.frames.count == 2)
        #expect(rig.log.entries.count == 0)
    }

    @Test("a descriptor other than the M0 format is refused before the gateway is touched")
    func rejectsUnsupportedDescriptor() {
        let rig = Rig()
        let other = SurfaceDescriptor.bgra(width: 1920, height: 1080)
        #expect(throws: CaptureSessionError.configurationFailed("unsupported descriptor 1920x1080")) {
            try rig.subject.start(descriptor: other, onFrame: { _ in }, onEnd: { _ in })
        }
        #expect(rig.gateway.startCount == 0)
    }

    @Test("a padded row stride is still the M0 format")
    func acceptsPaddedStride() throws {
        let rig = Rig()
        let padded = SurfaceDescriptor(width: 1280, height: 720, pixelFormat: .bgra32, bytesPerRow: 5_120 + 64)
        try rig.subject.start(descriptor: padded, onFrame: { _ in }, onEnd: { _ in })
        #expect(rig.gateway.startCount == 1)
    }

    @Test("stop retires the session: a frame the gateway still delivers afterwards is dropped")
    func stopDropsLateFrames() throws {
        let gateway = LingeringCaptureGateway()
        let executor = ManualFrameExecutor()
        let frames = Collector<IncomingSurface>()
        let subject = withDependencies {
            $0.captureSessionGateway = gateway
            $0.frameExecutor = executor
            $0.developerLog = RecordingLog()
        } operation: {
            CameraDataSourceImpl()
        }
        try subject.start(descriptor: .hd720, onFrame: { frames.append($0) }, onEnd: { _ in })
        executor.drain()
        gateway.emit(FakeSurfaceHandle(id: 1), seconds: 1.0)
        subject.stop()
        gateway.emit(FakeSurfaceHandle(id: 2), seconds: 2.0)
        executor.drain()
        #expect(frames.values.map(\.presentationTime.nanoseconds) == [1_000_000_000])
    }

    @Test("stop clears the monotonic floor for the next session")
    func stopResetsFloor() throws {
        let rig = Rig()
        try rig.start()
        rig.emit(1, seconds: 10.0)
        rig.executor.drain()
        rig.subject.stop()
        rig.executor.drain()
        try rig.start()
        rig.emit(2, seconds: 1.0)
        rig.executor.drain()
        #expect(rig.frames.count == 2)
        #expect(rig.log.entries.count == 0)
    }

    @Test("a second start replaces the session: the new floor applies and the old end is ignored")
    func doubleStartReplacesSession() throws {
        let gateway = LingeringCaptureGateway()
        let executor = ManualFrameExecutor()
        let frames = Collector<IncomingSurface>()
        let ends = Collector<CaptureEnd>()
        let subject = withDependencies {
            $0.captureSessionGateway = gateway
            $0.frameExecutor = executor
            $0.developerLog = RecordingLog()
        } operation: {
            CameraDataSourceImpl()
        }
        try subject.start(descriptor: .hd720, onFrame: { frames.append($0) }, onEnd: { ends.append($0) })
        gateway.emit(FakeSurfaceHandle(id: 1), seconds: 10.0)
        executor.drain()
        try subject.start(descriptor: .hd720, onFrame: { frames.append($0) }, onEnd: { ends.append($0) })
        gateway.emitFirstSession(FakeSurfaceHandle(id: 2), seconds: 20.0)
        gateway.endFirstSession(.deviceDisconnected)
        gateway.emit(FakeSurfaceHandle(id: 3), seconds: 1.0)
        executor.drain()
        #expect(gateway.startCount == 2)
        #expect(frames.values.map(\.presentationTime.nanoseconds) == [10_000_000_000, 1_000_000_000])
        #expect(ends.count == 0)
    }

    @Test("a failed start leaves no session behind")
    func failedStartRetiresSession() {
        let gateway = LingeringCaptureGateway()
        gateway.failNextStart()
        let executor = ManualFrameExecutor()
        let frames = Collector<IncomingSurface>()
        let subject = withDependencies {
            $0.captureSessionGateway = gateway
            $0.frameExecutor = executor
            $0.developerLog = RecordingLog()
        } operation: {
            CameraDataSourceImpl()
        }
        #expect(throws: CaptureSessionError.deviceUnavailable) {
            try subject.start(descriptor: .hd720, onFrame: { frames.append($0) }, onEnd: { _ in })
        }
        gateway.emitFirstSession(FakeSurfaceHandle(id: 1), seconds: 1.0)
        executor.drain()
        #expect(frames.count == 0)
    }

    @Test("a start error from the gateway propagates")
    func startErrorPropagates() {
        let rig = Rig()
        rig.gateway.failStart(with: .configurationFailed("busy"))
        #expect(throws: CaptureSessionError.configurationFailed("busy")) { try rig.start() }
        #expect(rig.gateway.startCount == 1)
    }

    @Test("stop ends the gateway session on the executor")
    func stopForwards() throws {
        let rig = Rig()
        try rig.start()
        rig.subject.stop()
        #expect(rig.gateway.stopCount == 0)
        rig.executor.drain()
        #expect(rig.gateway.stopCount == 1)
        #expect(!rig.gateway.isRunning)
    }

    @Test("a second start ends the session it replaces; stop afterwards ends only the new one")
    func replacingStartStopsTheOldSession() throws {
        let gateway = LingeringCaptureGateway()
        let executor = ManualFrameExecutor()
        let subject = withDependencies {
            $0.captureSessionGateway = gateway
            $0.frameExecutor = executor
            $0.developerLog = RecordingLog()
        } operation: {
            CameraDataSourceImpl()
        }
        try subject.start(descriptor: .hd720, onFrame: { _ in }, onEnd: { _ in })
        try subject.start(descriptor: .hd720, onFrame: { _ in }, onEnd: { _ in })
        executor.drain()
        #expect(gateway.stopCount == 1)
        subject.stop()
        executor.drain()
        #expect(gateway.stopCount == 2)
        subject.stop()
        executor.drain()
        #expect(gateway.stopCount == 2)
    }

    @Test("a stop that lands while the gateway is still starting ends the session once its handle arrives")
    func stopDuringStart() throws {
        let gateway = LingeringCaptureGateway()
        let executor = ManualFrameExecutor()
        let frames = Collector<IncomingSurface>()
        let subject = withDependencies {
            $0.captureSessionGateway = gateway
            $0.frameExecutor = executor
            $0.developerLog = RecordingLog()
        } operation: {
            CameraDataSourceImpl()
        }
        // Queued between the session's begin and the arrival of its handle.
        gateway.whileStarting { subject.stop() }
        try subject.start(descriptor: .hd720, onFrame: { frames.append($0) }, onEnd: { _ in })
        executor.drain()
        #expect(gateway.stopCount == 1)
        gateway.emit(FakeSurfaceHandle(id: 1), seconds: 1.0)
        executor.drain()
        #expect(frames.count == 0)
    }

    @Test("stop reports .stopped once, after the frames queued before it")
    func stopReportsStoppedOnce() throws {
        let rig = Rig()
        let order = Collector<String>()
        try rig.subject.start(
            descriptor: .hd720, onFrame: { _ in order.append("frame") }, onEnd: { order.append("end \($0)") })
        rig.executor.drain()
        rig.emit(1, seconds: 1.0)
        rig.subject.stop()
        rig.subject.stop()
        #expect(order.count == 0)
        rig.executor.drain()
        #expect(order.values == ["frame", "end stopped"])
    }

    @Test("a gateway end arriving after the stop is ignored")
    func endAfterStopIsIgnored() throws {
        let rig = Rig()
        try rig.start()
        rig.subject.stop()
        rig.executor.drain()
        rig.gateway.end(.deviceDisconnected)
        rig.executor.drain()
        #expect(rig.ends.values == [.stopped])
    }

    @Test("stop stays silent after the gateway already ended the session")
    func stopAfterGatewayEndIsSilent() throws {
        let rig = Rig()
        try rig.start()
        rig.gateway.end(.deviceDisconnected)
        rig.executor.drain()
        rig.subject.stop()
        rig.executor.drain()
        #expect(rig.ends.values == [.deviceDisconnected])
    }

    @Test("stop with nothing running reports nothing")
    func stopWithoutSessionIsSilent() {
        let rig = Rig()
        rig.subject.stop()
        rig.executor.drain()
        #expect(rig.ends.count == 0)
    }

    @Test("a failed start emits no end, even when stop follows")
    func failedStartEmitsNothing() {
        let gateway = LingeringCaptureGateway()
        gateway.failNextStart()
        let executor = ManualFrameExecutor()
        let ends = Collector<CaptureEnd>()
        let subject = withDependencies {
            $0.captureSessionGateway = gateway
            $0.frameExecutor = executor
            $0.developerLog = RecordingLog()
        } operation: {
            CameraDataSourceImpl()
        }
        #expect(throws: CaptureSessionError.deviceUnavailable) {
            try subject.start(descriptor: .hd720, onFrame: { _ in }, onEnd: { ends.append($0) })
        }
        subject.stop()
        executor.drain()
        #expect(ends.count == 0)
    }

    @Test("a session replaced by a new start emits nothing; stop then reports only the new session")
    func replacedSessionEmitsNothing() throws {
        let gateway = LingeringCaptureGateway()
        let executor = ManualFrameExecutor()
        let first = Collector<CaptureEnd>()
        let second = Collector<CaptureEnd>()
        let subject = withDependencies {
            $0.captureSessionGateway = gateway
            $0.frameExecutor = executor
            $0.developerLog = RecordingLog()
        } operation: {
            CameraDataSourceImpl()
        }
        try subject.start(descriptor: .hd720, onFrame: { _ in }, onEnd: { first.append($0) })
        try subject.start(descriptor: .hd720, onFrame: { _ in }, onEnd: { second.append($0) })
        executor.drain()
        #expect(first.count == 0 && second.count == 0)
        subject.stop()
        executor.drain()
        #expect(first.count == 0)
        #expect(second.values == [.stopped])
    }
}
