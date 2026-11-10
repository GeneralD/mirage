import CameraDataSource
import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("CameraDataSource configuration", .timeLimit(.minutes(1)))
struct CameraDataSourceConfigureTests {
    private static let other = CameraCapture(deviceID: "cam-2", format: nil)
    private static let third = CameraCapture(deviceID: "cam-3", format: nil)

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
                $0.errorLog = log
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

    @Test("a capture configured before start is the one the gateway starts with")
    func configuredBeforeStartIsUsed() throws {
        let rig = Rig()
        rig.subject.configure(Self.other)
        try rig.start()
        #expect(rig.gateway.capture == Self.other)
        #expect(rig.gateway.startCount == 1)
    }

    @Test("a capture configured while running restarts the session on it, and the new session's frames still arrive")
    func configuredWhileRunningRestarts() throws {
        let rig = Rig()
        try rig.start()
        rig.emit(1, seconds: 10.0)
        rig.executor.drain()
        rig.subject.configure(Self.other)
        rig.executor.drain()
        #expect(rig.gateway.capture == Self.other)
        #expect(rig.gateway.startCount == 2)
        #expect(rig.gateway.stopCount == 1)
        #expect(rig.ends.count == 0)
        // The new session starts from a clean monotonic floor, so an earlier PTS is accepted.
        rig.emit(2, seconds: 1.0)
        rig.executor.drain()
        #expect(rig.frames.values.map(\.presentationTime.nanoseconds) == [10_000_000_000, 1_000_000_000])
    }

    @Test("configuring the capture the running session already uses restarts nothing")
    func sameCaptureRestartsNothing() throws {
        let rig = Rig()
        try rig.start()
        rig.subject.configure(.standard)
        rig.executor.drain()
        #expect(rig.gateway.startCount == 1)
        #expect(rig.gateway.stopCount == 0)
    }

    @Test("configures queued before the executor drains apply once, as the last capture")
    func burstOfConfiguresAppliesTheLast() throws {
        let rig = Rig()
        try rig.start()
        rig.subject.configure(Self.other)
        rig.subject.configure(Self.third)
        rig.executor.drain()
        #expect(rig.gateway.capture == Self.third)
        #expect(rig.gateway.startCount == 2)
    }

    @Test("a configure after the gateway ended the session restarts it, even with the same capture")
    func configureAfterGatewayEndRestarts() throws {
        let rig = Rig()
        try rig.start()
        rig.gateway.end(.deviceDisconnected)
        rig.executor.drain()
        rig.subject.configure(.standard)
        rig.executor.drain()
        #expect(rig.gateway.startCount == 2)
        #expect(rig.gateway.capture == .standard)
        #expect(rig.ends.values == [.deviceDisconnected])
    }

    @Test("a configure after stop starts nothing")
    func configureAfterStopStartsNothing() throws {
        let rig = Rig()
        try rig.start()
        rig.subject.stop()
        rig.executor.drain()
        rig.subject.configure(Self.other)
        rig.executor.drain()
        #expect(rig.gateway.startCount == 1)
        #expect(rig.ends.values == [.stopped])
    }

    @Test("a failed restart logs the error, ends the session once, and the next configure retries")
    func failedRestartIsRetriedByNextConfigure() throws {
        let rig = Rig()
        try rig.start()
        rig.gateway.failStart(with: .deviceUnavailable)
        rig.subject.configure(Self.other)
        rig.executor.drain()
        #expect(rig.log.contains("capture restart failed: deviceUnavailable"))
        #expect(rig.ends.values == [.runtimeError("deviceUnavailable")])
        rig.gateway.failStart(with: nil)
        rig.subject.configure(Self.other)
        rig.executor.drain()
        #expect(rig.gateway.isRunning)
        #expect(rig.gateway.capture == Self.other)
        #expect(rig.ends.values == [.runtimeError("deviceUnavailable")])
    }

    @Test("each restart leaves one developer log line")
    func eachRestartLogsOnce() throws {
        let rig = Rig()
        try rig.start()
        rig.subject.configure(Self.other)
        rig.executor.drain()
        rig.subject.configure(Self.third)
        rig.executor.drain()
        let lines = rig.log.messages(in: .camera).filter { $0 == "restarting the capture session" }
        #expect(lines.count == 2)
    }

    @Test("a configure that lands before start's first executor block is not lost")
    func configureBeforeFirstBlockIsNotLost() throws {
        let gateway = FakeCaptureSessionGateway()
        let executor = HookedExecutor()
        let subject = withDependencies {
            $0.captureSessionGateway = gateway
            $0.frameExecutor = executor
            $0.developerLog = RecordingLog()
            $0.errorLog = RecordingLog()
        } operation: {
            CameraDataSourceImpl()
        }
        executor.beforeFirstRun = { subject.configure(Self.other) }
        try subject.start(descriptor: .hd720, onFrame: { _ in }, onEnd: { _ in })
        executor.drain()
        #expect(gateway.capture == Self.other)
        #expect(gateway.startCount == 2)
        #expect(gateway.stopCount == 1)
    }

    @Test("a configure that lands while the gateway is starting is honoured by the new session")
    func configureDuringGatewayStartIsHonoured() throws {
        let gateway = LingeringCaptureGateway()
        let executor = ManualFrameExecutor()
        let subject = withDependencies {
            $0.captureSessionGateway = gateway
            $0.frameExecutor = executor
            $0.developerLog = RecordingLog()
            $0.errorLog = RecordingLog()
        } operation: {
            CameraDataSourceImpl()
        }
        gateway.whileStarting { subject.configure(Self.other) }
        try subject.start(descriptor: .hd720, onFrame: { _ in }, onEnd: { _ in })
        executor.drain()
        #expect(gateway.startCount == 2)
        #expect(gateway.stopCount == 1)
    }

    @Test("the fake camera source records every configured capture in call order")
    func fakeRecordsConfigureOrder() {
        let source = FakeCameraSource()
        source.configure(Self.other)
        source.configure(Self.third)
        #expect(source.captures == [Self.other, Self.third])
    }
}

/// A frame executor that runs `beforeFirstRun` once, ahead of the first work it is
/// given: the moment a `configure` from another thread can land between `start`'s
/// read of the capture and its first executor block.
private final class HookedExecutor: FrameExecutor, @unchecked Sendable {
    private let inner = ManualFrameExecutor()
    var beforeFirstRun: (@Sendable () -> Void)?

    func run(_ work: @escaping @Sendable () -> Void) {
        if let hook = beforeFirstRun {
            beforeFirstRun = nil
            hook()
        }
        inner.run(work)
    }

    func drain() {
        inner.drain()
    }
}
