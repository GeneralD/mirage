import CameraRepository
import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("CameraRepository", .timeLimit(.minutes(1)))
struct CameraRepositoryTests {
    private struct Rig {
        let source = FakeCameraSource()
        let permission: FakeCameraPermission
        let pool: FakeSurfacePool
        let log = RecordingLog()
        let frames = Collector<FrameRef>()
        let ends = Collector<CaptureEnd>()
        let subject: CameraRepositoryImpl

        init(capacity: Int = 1, permission: FakeCameraPermission = FakeCameraPermission(status: .authorized)) {
            let source = source
            let pool = FakeSurfacePool(capacity: capacity)
            let log = log
            self.permission = permission
            self.pool = pool
            subject = withDependencies {
                $0.cameraSource = source
                $0.cameraPermission = permission
                $0.surfacePool = pool
                $0.errorLog = log
            } operation: {
                CameraRepositoryImpl()
            }
        }

        func start() throws {
            let frames = frames
            let ends = ends
            try subject.start(descriptor: .hd720, onFrame: { frames.append($0) }, onEnd: { ends.append($0) })
        }
    }

    @Test("authorization status and request forward to the permission port", arguments: CameraAuthorizationStatus.allCases)
    func forwardsAuthorization(status: CameraAuthorizationStatus) async {
        let rig = Rig(permission: FakeCameraPermission(status: status, decision: .denied))
        #expect(rig.subject.authorizationStatus() == status)
        let requested = await rig.subject.requestAuthorization()
        #expect(requested == (status == .notDetermined ? .denied : status))
        #expect(rig.permission.requests.count == 1)
    }

    @Test("start forwards the descriptor to the source")
    func startForwardsDescriptor() throws {
        let rig = Rig()
        try rig.start()
        #expect(rig.source.descriptor == .hd720)
        #expect(rig.source.startCount == 1)
    }

    @Test("a frame is adopted into the pool and delivered with its timing")
    func adoptsFrame() throws {
        let rig = Rig()
        try rig.start()
        let handle = FakeSurfaceHandle(id: 1)
        let time = HostTimestamp(nanoseconds: 42)
        rig.source.emit(handle, at: time)
        let frame = try #require(rig.frames.last)
        #expect(frame.presentationTime == time)
        #expect(frame.descriptor == .hd720)
        #expect(rig.pool.handle(for: frame.token) === handle)
        #expect(rig.pool.liveCount == 1)
        #expect(rig.log.entries.count == 0)
    }

    @Test("a frame the pool cannot lease is dropped and reported as pool exhausted")
    func dropsWhenPoolFull() throws {
        let rig = Rig(capacity: 1)
        try rig.start()
        rig.source.emit(FakeSurfaceHandle(id: 1), at: HostTimestamp(nanoseconds: 1))
        rig.source.emit(FakeSurfaceHandle(id: 2), at: HostTimestamp(nanoseconds: 2))
        #expect(rig.frames.count == 1)
        #expect(rig.pool.liveCount == 1)
        #expect(rig.log.messages(in: .camera).count == 1)
        #expect(rig.log.contains("pool exhausted"))
    }

    @Test("releasing the lease lets the next frame through")
    func releaseFreesCapacity() throws {
        let rig = Rig(capacity: 1)
        try rig.start()
        rig.source.emit(FakeSurfaceHandle(id: 1), at: HostTimestamp(nanoseconds: 1))
        let first = try #require(rig.frames.last)
        rig.pool.release(first.token)
        rig.source.emit(FakeSurfaceHandle(id: 2), at: HostTimestamp(nanoseconds: 2))
        #expect(rig.frames.count == 2)
        #expect(rig.log.entries.count == 0)
    }

    @Test("end reasons are forwarded untouched", arguments: [CaptureEnd.stopped, .deviceDisconnected, .runtimeError("boom")])
    func forwardsEnd(reason: CaptureEnd) throws {
        let rig = Rig()
        try rig.start()
        rig.source.end(reason)
        #expect(rig.ends.values == [reason])
    }

    @Test("a start error from the source propagates")
    func startErrorPropagates() {
        let rig = Rig()
        rig.source.failStart(with: .deviceUnavailable)
        #expect(throws: CaptureSessionError.deviceUnavailable) { try rig.start() }
    }

    @Test("stop forwards to the source")
    func stopForwards() throws {
        let rig = Rig()
        try rig.start()
        rig.subject.stop()
        #expect(rig.source.stopCount == 1)
        #expect(!rig.source.isRunning)
    }
}
