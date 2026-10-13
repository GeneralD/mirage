import BundledEffectDataSource
import CameraRepository
import Clocks
import Dependencies
import Domain
import EffectRuntimeRepository
import EffectRuntimeStateDataSource
import ExtensionRelayUseCase
import FramePipelineUseCase
import FrameReceiverDataSource
import FrameReceiverRepository
import FrameTransportDataSource
import GPURenderDataSource
import PreviewDataSource
import PreviewRepository
import ShaderCompilationDataSource
import StreamOutputDataSource
import StreamOutputRepository
import SurfacePoolDataSource
import SurfaceRepository
import TestDoubles
import TestSupport
import Testing
import VirtualCameraRepository

/// Which `PreviewSink` the host's pipeline presents to.
enum HostPreview {
    /// `HostSide.preview`: an `InMemoryPreviewSink` that completes every frame inside
    /// `present` until a test attaches it — stricter than the live sink with no view open,
    /// which does so in a later executor job (`.rendered` has that timing).
    case inMemory
    /// The real preview — `PreviewRepositoryImpl` over `PreviewDataSourceImpl`, on the
    /// host's executor and pool — drawing through the fake GPU layer (`HostSide.gpu`,
    /// `shaders`, `textures`, `previewGateway`).
    case rendered
}

/// Which `EffectRuntimeRepository` the host's pipeline applies its effect with.
enum HostEffects {
    /// `HostSide.effects`, a `FakeEffectRuntimeRepository`: every `apply` waits until the
    /// test answers it with whatever result it likes (`LoopbackRig.capture`).
    case fake
    /// The real runtime: `EffectRuntimeRepositoryImpl` over `EffectRuntimeStateDataSourceImpl`,
    /// `ShaderCompilationDataSourceImpl`, `GPURenderDataSourceImpl` and
    /// `BundledEffectDataSourceImpl`, on the host's executor, pool and work runner, over the
    /// fake GPU layer (`HostSide.gpu`, `shaders`, `textures`). The test answers what the GPU
    /// would: a compile it scripts (`shaders.failCompile`) and the command buffer it completes
    /// (`LoopbackRig.captureThroughRuntime`).
    case real
}

/// The host process: camera → pipeline (effect stage) → transport and preview, on its own
/// executor, scheduler, pool and clock.
struct HostSide {
    let executor = ManualFrameExecutor()
    let scheduler = ManualFrameScheduler()
    let work = RecordingWorkRunner()
    let clock = TestClock<Duration>()
    let camera = FakeCameraSource()
    /// The effect runtime of a `.fake` host: every `apply` waits until the test answers it
    /// (`LoopbackRig.capture`). Unused by a `.real` one.
    let effects = FakeEffectRuntimeRepository()
    /// The preview of a `.inMemory` host.
    let preview = InMemoryPreviewSink(holding: .onceAttached)
    /// The fake GPU layer a `.rendered` preview and a `.real` effect runtime go through: a
    /// draw stays pending on `previewGateway`, and an effect pass on `gpu`, until the test
    /// completes it.
    let gpu = FakeGPUGateway()
    let shaders = FakeShaderLibraryGateway()
    let textures = FakeTextureCacheGateway()
    let previewGateway = FakePreviewGateway()
    let errors = RecordingLog()
    let developer = RecordingLog()
    let pool: SurfacePoolDataSourceImpl
    /// What the pipeline presents to: `preview`, or the real preview over the fake GPU layer.
    let previewSink: any PreviewSink
    let pipeline: FramePipelineUseCaseImpl

    init(
        kernel: InMemoryFrameTransport, ioSurface: FakeIOSurfaceGateway, capacity: Int, preview choice: HostPreview,
        effects effectsChoice: HostEffects
    ) {
        let executor = executor
        let scheduler = scheduler
        let work = work
        let clock = clock
        let camera = camera
        let effects = effects
        let preview = preview
        let gpu = gpu
        let shaders = shaders
        let textures = textures
        let previewGateway = previewGateway
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
        (previewSink, pipeline) = withDependencies {
            $0.ioSurfaceGateway = ioSurface
            $0.machBootstrapGateway = kernel.bootstrap(for: .host)
            $0.machMessageGateway = kernel.messaging(for: .host)
            $0.surfacePool = pool
            $0.frameExecutor = executor
            $0.frameScheduler = scheduler
            $0.workRunner = work
            $0.continuousClock = clock
            $0.cameraSource = camera
            $0.cameraPermission = FakeCameraPermission(status: .authorized)
            $0.gpuGateway = gpu
            $0.shaderLibraryGateway = shaders
            $0.textureCacheGateway = textures
            $0.previewGateway = previewGateway
            $0.errorLog = errors
            $0.developerLog = developer
        } operation: {
            withDependencies {
                $0.cameraRepository = CameraRepositoryImpl()
                $0.frameTransport = FrameTransportDataSourceImpl()
                $0.surfaceRepository = SurfaceRepositoryImpl()
                $0.previewRenderer = PreviewDataSourceImpl()
            } operation: {
                let sink: any PreviewSink =
                    switch choice {
                    case .inMemory: preview
                    case .rendered: PreviewRepositoryImpl()
                    }
                let runtime: any EffectRuntimeRepository =
                    switch effectsChoice {
                    case .fake: effects
                    case .real: Self.realRuntime()
                    }
                return withDependencies {
                    $0.virtualCameraSink = VirtualCameraRepositoryImpl()
                    $0.previewSink = sink
                    $0.effectRuntimeRepository = runtime
                } operation: {
                    (sink, FramePipelineUseCaseImpl())
                }
            }
        }
    }
}

extension HostSide {
    /// The real runtime and the DataSources under it, each built in the scope that holds the
    /// executor, the pool, the work runner, the logs and the fake GPU layer, so every
    /// `@Dependency` captures the real neighbour. One state and one renderer: both keep their
    /// memory (the compile cache and the session clock; the GPU context) for the whole run.
    fileprivate static func realRuntime() -> any EffectRuntimeRepository {
        let state = EffectRuntimeStateDataSourceImpl()
        let compiler = ShaderCompilationDataSourceImpl()
        let renderer = GPURenderDataSourceImpl()
        let bundled = BundledEffectDataSourceImpl()
        return withDependencies {
            $0.effectRuntimeState = state
            $0.shaderCompiler = compiler
            $0.gpuRenderer = renderer
            $0.bundledEffects = bundled
        } operation: {
            EffectRuntimeRepositoryImpl()
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

    init(capacity: Int = 4, frameGap: Duration = .seconds(2), preview: HostPreview = .inMemory, effects: HostEffects = .fake) {
        host = HostSide(kernel: kernel, ioSurface: ioSurface, capacity: capacity, preview: preview, effects: effects)
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

    /// Attaches a view to the host's preview on the main thread, as the view does, then
    /// drains the host's executor from here, off the main thread: a `.rendered` preview
    /// compiles its kernel there, and the fake shader library reports a compile on main.
    func attachPreview(_ target: FakePreviewTargetHandle = FakePreviewTargetHandle()) async throws {
        let sink = host.previewSink
        try await MainActor.run { try sink.attach(target) }
        host.executor.drain()
    }

    /// One camera frame into the host's slot, then one scheduler tick to send it. The
    /// tick hands the frame to the effect stage; the pass is answered with `effect`
    /// (by default an `.internalError`, a failure, so the camera's own surface goes
    /// on) and its result is drained, so the frame has reached the transport — and
    /// the preview — when this returns.
    @MainActor
    func capture(
        _ handle: FakeSurfaceHandle,
        at nanoseconds: UInt64,
        effect: Result<Void, EffectFailure> = .failure(.internalError)
    ) async {
        host.camera.emit(handle, at: HostTimestamp(nanoseconds: nanoseconds))
        // Only an effect pass starts work inside a tick (a reconnect starts on the executor),
        // so a new work item means this tick started one, and its number is the item's.
        let item = host.work.started.count
        let requests = host.effects.applyRequests.count
        host.scheduler.tick()
        guard host.work.started.count > item else { return }
        await host.effects.applyRequests.waitForCount(requests + 1)
        // Read without subscripting: if the time limit ends the wait, the test fails rather than crashing.
        guard let request = host.effects.applyRequests.values.dropFirst(requests).first else {
            Issue.record("the tick started a pass but its apply never came")
            return
        }
        host.effects.completeApply(request, with: effect)
        await host.work.finished.waitFor { $0 == item }
        host.executor.drain()
    }

    /// One camera frame through a `.real` host's effect runtime, the counterpart of `capture`.
    /// The tick hands the frame to the pipeline's effect stage, whose `apply` runs the real
    /// runtime on the host's executor: this drains it until the pass either answers without
    /// a GPU (a source that did not compile) or has committed its command buffer, completes
    /// that with `completion` — what the device would report — and drains until the pipeline
    /// has taken the answer. The frame has reached the transport, and the preview, when this
    /// returns. The first frame also compiles the bundled effect, on the work runner, off
    /// this thread; a compile that never arrives fails the test by its time limit.
    @MainActor
    func captureThroughRuntime(_ handle: FakeSurfaceHandle, at nanoseconds: UInt64, completing completion: GPUCompletion = .finished) async {
        let answers = { host.pipeline.stats.effectsApplied + host.pipeline.stats.effectFailures.values.reduce(0, +) }
        let (answered, submitted) = (answers(), host.gpu.submissions.count)
        host.camera.emit(handle, at: HostTimestamp(nanoseconds: nanoseconds))
        host.scheduler.tick()
        let moved = await tickUntil(tick: { host.executor.drain() }, until: { answers() > answered || host.gpu.submissions.count > submitted })
        guard moved else {
            Issue.record("the tick started a pass but it neither answered nor committed a command buffer")
            return
        }
        guard answers() == answered else { return }
        guard let submission = host.gpu.pending.last else {
            Issue.record("a command buffer was committed but is not pending")
            return
        }
        host.gpu.complete(submission, with: completion)
        let taken = await tickUntil(tick: { host.executor.drain() }, until: { answers() > answered })
        if !taken { Issue.record("the pipeline never took the answer to the pass") }
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

extension GPUCompletion {
    /// A command buffer that ran to the end.
    static let finished = GPUCompletion(gpuStart: 10, gpuEnd: 10.004, error: nil)

    /// A command buffer that reported `code` in the command-buffer error domain (3 is a page fault).
    static func failed(code: Int) -> GPUCompletion {
        GPUCompletion(gpuStart: 10, gpuEnd: 12, error: RawGPUError(domain: GPUCompletionMapping.commandBufferErrorDomain, code: code))
    }
}
