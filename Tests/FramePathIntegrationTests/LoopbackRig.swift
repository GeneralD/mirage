import CameraRepository
import Clocks
import Dependencies
import Domain
import ExtensionRelayUseCase
import FramePipelineUseCase
import FrameReceiverDataSource
import FrameReceiverRepository
import FrameTransportDataSource
import StreamOutputDataSource
import StreamOutputRepository
import SurfacePoolDataSource
import SurfaceRepository
import TestDoubles
import TestSupport
import VirtualCameraRepository

/// The host process: camera → pipeline → transport, on its own executor,
/// scheduler, pool and clock.
struct HostSide {
    let executor = ManualFrameExecutor()
    let scheduler = ManualFrameScheduler()
    let clock = TestClock<Duration>()
    let camera = FakeCameraSource()
    let errors = RecordingLog()
    let developer = RecordingLog()
    let pool: SurfacePoolDataSourceImpl
    let pipeline: FramePipelineUseCaseImpl

    init(kernel: InMemoryFrameTransport, ioSurface: FakeIOSurfaceGateway, capacity: Int) {
        let executor = executor
        let scheduler = scheduler
        let clock = clock
        let camera = camera
        let errors = errors
        let developer = developer
        pool = withDependencies {
            $0.ioSurfaceGateway = ioSurface
        } operation: {
            SurfacePoolDataSourceImpl(capacity: capacity)
        }
        let pool = pool
        // Each layer is built inside the scope of the one below it, so every
        // `@Dependency` captures the real neighbour rather than a default.
        pipeline = withDependencies {
            $0.ioSurfaceGateway = ioSurface
            $0.machBootstrapGateway = kernel.bootstrap(for: .host)
            $0.machMessageGateway = kernel.messaging(for: .host)
            $0.surfacePool = pool
            $0.frameExecutor = executor
            $0.frameScheduler = scheduler
            $0.continuousClock = clock
            $0.cameraSource = camera
            $0.cameraPermission = FakeCameraPermission(status: .authorized)
            $0.errorLog = errors
            $0.developerLog = developer
        } operation: {
            withDependencies {
                $0.cameraRepository = CameraRepositoryImpl()
                $0.frameTransport = FrameTransportDataSourceImpl()
                $0.surfaceRepository = SurfaceRepositoryImpl()
            } operation: {
                withDependencies {
                    $0.virtualCameraSink = VirtualCameraRepositoryImpl()
                } operation: {
                    FramePipelineUseCaseImpl()
                }
            }
        }
    }
}

/// The extension process: receiver → relay → stream, on its own executor, pool
/// and clock.
struct ExtensionSide {
    let executor = ManualFrameExecutor()
    let scheduler = ManualFrameScheduler()
    let clock = TestClock<Duration>()
    let stream = FakeStreamOutputGateway()
    /// The extension's host-time axis (slate bases read it); a test moves it by hand.
    let hostTime = FixedHostTime()
    let errors = RecordingLog()
    let developer = RecordingLog()
    let pool: SurfacePoolDataSourceImpl
    let relay: ExtensionRelayUseCaseImpl

    init(kernel: InMemoryFrameTransport, ioSurface: FakeIOSurfaceGateway, capacity: Int, frameGap: Duration) {
        let executor = executor
        let scheduler = scheduler
        let clock = clock
        let stream = stream
        let hostTime = hostTime
        let errors = errors
        let developer = developer
        pool = withDependencies {
            $0.ioSurfaceGateway = ioSurface
        } operation: {
            SurfacePoolDataSourceImpl(capacity: capacity)
        }
        let pool = pool
        relay = withDependencies {
            $0.hostTime = hostTime
            $0.ioSurfaceGateway = ioSurface
            $0.machBootstrapGateway = kernel.bootstrap(for: .extension)
            $0.machMessageGateway = kernel.messaging(for: .extension)
            $0.surfacePool = pool
            $0.frameExecutor = executor
            $0.frameScheduler = scheduler
            $0.continuousClock = clock
            $0.streamOutputGateway = stream
            $0.errorLog = errors
            $0.developerLog = developer
        } operation: {
            withDependencies {
                $0.frameReceiver = FrameReceiverDataSourceImpl(frameGap: frameGap)
                $0.streamOutput = StreamOutputDataSourceImpl()
                $0.surfaceRepository = SurfaceRepositoryImpl()
            } operation: {
                withDependencies {
                    $0.frameReceiverRepository = FrameReceiverRepositoryImpl()
                    $0.streamOutputRepository = StreamOutputRepositoryImpl()
                } operation: {
                    ExtensionRelayUseCaseImpl()
                }
            }
        }
    }
}

/// Both processes wired end to end over `InMemoryFrameTransport`. They share only the
/// kernel and the IOSurface table (`ioSurface`), as the real processes share
/// only the kernel: executors, pools and clocks are separate on each side.
struct LoopbackRig {
    let kernel = InMemoryFrameTransport()
    let ioSurface = FakeIOSurfaceGateway()
    let host: HostSide
    let ext: ExtensionSide

    init(capacity: Int = 4, frameGap: Duration = .seconds(2)) {
        host = HostSide(kernel: kernel, ioSurface: ioSurface, capacity: capacity)
        ext = ExtensionSide(kernel: kernel, ioSurface: ioSurface, capacity: capacity, frameGap: frameGap)
    }
}

extension LoopbackRig {
    /// Starts the extension and pumps its executor until it is parked on a
    /// receive; with `clientStreaming` a client has also opened the stream.
    @MainActor
    func startExtension(clientStreaming: Bool = true) async -> Task<Void, any Error> {
        let relay = ext.relay
        // Relative, so a second run of the same extension (after an exit) waits for its own receive.
        let receivesBefore = kernel.receiveCalls.count
        let task = Task { try await relay.run(descriptor: .hd720, frameRate: .standard) }
        await tickUntil(tick: { ext.executor.drain() }, until: { kernel.receiveCalls.count > receivesBefore })
        guard clientStreaming else { return task }
        ext.stream.emit(.streamStarted)
        ext.executor.drain()
        return task
    }

    /// Starts the host; the look-up succeeds at once because the extension
    /// has checked in, so this returns connected.
    func startHost() async throws {
        try await host.pipeline.start(descriptor: .hd720, frameRate: .standard)
        host.executor.drain()
    }

    /// One camera frame into the host's slot, then one scheduler tick to send it.
    func capture(_ handle: FakeSurfaceHandle, at nanoseconds: UInt64) {
        host.camera.emit(handle, at: HostTimestamp(nanoseconds: nanoseconds))
        host.scheduler.tick()
    }

    /// Pumps the extension until its relay has counted `count` received frames.
    @MainActor
    @discardableResult
    func pumpExtension(untilReceived count: Int) async -> Bool {
        await tickUntil(tick: { ext.executor.drain() }, until: { ext.relay.stats.framesReceived >= count })
    }

    /// Ends the extension's run the way the extension does: `stop()` destroys
    /// the receive right, the pending receive dies and `run` returns.
    func stopExtension(_ task: Task<Void, any Error>) async throws {
        ext.relay.stop()
        ext.executor.drain()
        try await task.value
        ext.executor.drain()
    }

    func stopHost() {
        host.pipeline.stop()
        host.executor.drain()
    }

    /// The presentation times the stream has received, in arrival order.
    var streamedTimes: [UInt64] {
        ext.stream.sent.values.map(\.presentationTime.nanoseconds)
    }
}
