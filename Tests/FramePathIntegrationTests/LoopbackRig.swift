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

/// The kernel between the two processes, in-process: one bootstrap table in
/// which the extension's check-in and the host's look-up name the same port,
/// and one message queue in which the host's `send` is the extension's next
/// `receive`. Destroying the receive right fails the pending receive with
/// `.portDied`, as the kernel does.
final class LoopbackKernel: Sendable {
    let bootstrap = FakeMachBootstrapGateway()
    let messages = FakeMachMessageGateway()
    let port = MachPortToken(name: 0x2000)

    init() {
        bootstrap.scriptCheckIn([.success(port)])
        bootstrap.scriptLookUp([.success(port)])
    }
}

/// The bootstrap gateway as either process sees it.
struct LoopbackBootstrap: MachBootstrapGateway {
    let kernel: LoopbackKernel

    func lookUp(serviceName: String) throws -> MachPortToken {
        try kernel.bootstrap.lookUp(serviceName: serviceName)
    }

    func checkIn(serviceName: String) throws -> MachPortToken {
        try kernel.bootstrap.checkIn(serviceName: serviceName)
    }

    func register(serviceName: String) throws -> MachPortToken {
        try kernel.bootstrap.register(serviceName: serviceName)
    }

    func deallocate(_ port: MachPortToken) {
        kernel.bootstrap.deallocate(port)
    }

    func destroyReceiveRight(_ port: MachPortToken) {
        kernel.bootstrap.destroyReceiveRight(port)
        kernel.messages.failReceive(with: .portDied, on: port)
    }
}

/// The message gateway as either process sees it: a send lands in the queue
/// the other side is receiving on.
struct LoopbackMessaging: MachMessageGateway {
    let kernel: LoopbackKernel

    func send(_ message: FrameMessage, to port: MachPortToken) throws {
        try kernel.messages.send(message, to: port)
        kernel.messages.deliver(message, on: port)
    }

    func receive(on port: MachPortToken) async throws -> FrameMessage {
        try await kernel.messages.receive(on: port)
    }
}

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

    init(kernel: LoopbackKernel, ioSurface: FakeIOSurfaceGateway, capacity: Int) {
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
            $0.machBootstrapGateway = LoopbackBootstrap(kernel: kernel)
            $0.machMessageGateway = LoopbackMessaging(kernel: kernel)
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
    let clock = TestClock<Duration>()
    let stream = FakeStreamOutputGateway()
    let errors = RecordingLog()
    let developer = RecordingLog()
    let pool: SurfacePoolDataSourceImpl
    let relay: ExtensionRelayUseCaseImpl

    init(kernel: LoopbackKernel, ioSurface: FakeIOSurfaceGateway, capacity: Int, frameGap: Duration) {
        let executor = executor
        let clock = clock
        let stream = stream
        let errors = errors
        let developer = developer
        pool = withDependencies {
            $0.ioSurfaceGateway = ioSurface
        } operation: {
            SurfacePoolDataSourceImpl(capacity: capacity)
        }
        let pool = pool
        relay = withDependencies {
            $0.ioSurfaceGateway = ioSurface
            $0.machBootstrapGateway = LoopbackBootstrap(kernel: kernel)
            $0.machMessageGateway = LoopbackMessaging(kernel: kernel)
            $0.surfacePool = pool
            $0.frameExecutor = executor
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

/// Both processes wired end to end over `LoopbackKernel`. They share only the
/// kernel and the IOSurface table (`ioSurface`), as the real processes share
/// only the kernel: executors, pools and clocks are separate on each side.
struct LoopbackRig {
    let kernel = LoopbackKernel()
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
        let task = Task { try await relay.run(descriptor: .hd720, frameRate: .standard) }
        await tickUntil(tick: { ext.executor.drain() }, until: { kernel.messages.receiveCalls.count >= 1 })
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
