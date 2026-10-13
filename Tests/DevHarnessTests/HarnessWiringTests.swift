import Dependencies
import Domain
import FramePipelineUseCase
import HarnessInteractor
import HostDependencyInjection
import TestDoubles
import TestSupport
import Testing
import VirtualCameraRepository

@testable import DevHarness

/// The harness's own graph on fakes: a `HarnessSession` over the real
/// `HarnessInteractorImpl` and the real `FramePipelineUseCaseImpl`, built by hand inside the
/// scope of the harness's one substitution (`useDiscardingVirtualCameraSink`). It does not
/// call `HarnessSession.live()`: that route, through the live registrations, is
/// `HarnessLiveWiringTests`'. Everything below the pipeline is a fake, so what is proven
/// here is the harness's sequence — camera question, pipeline, preview, stop — and that
/// frames cross the pipeline into the discarding sink and the preview, with the sink left
/// at its unimplemented default that would fail the test if the substitution did not reach
/// the pipeline.
/// The real effect runtime and GPU layer are the loopback's (`FramePathIntegrationTests`).
@MainActor
@Suite("Dev harness wiring", .timeLimit(.minutes(1)))
struct HarnessWiringTests {
    @Test("the substitution replaces the sink the pipeline sends to with the discarding one")
    func substitutionInstallsTheDiscardingSink() {
        let sink = withDependencies {
            $0.useDiscardingVirtualCameraSink()
        } operation: {
            @Dependency(\.virtualCameraSink) var sink
            return sink
        }

        #expect(sink is DiscardingVirtualCameraSink)
    }

    @Test("a granted camera starts the pipeline, and a frame goes through the effect stage into the discarding sink and the preview")
    func cameraFrameReachesTheSinkAndThePreview() async throws {
        let rig = HarnessWiringRig()
        try await rig.launch()

        let frame = try #require(rig.surfaces.frame(at: HostTimestamp(nanoseconds: 1_000)))
        rig.camera.emit(frame)
        rig.scheduler.tick()
        await rig.effects.applyRequests.waitForCount(1)
        let request = try #require(rig.effects.applyRequests.values.first)
        rig.effects.completeApply(request, with: .success(()))
        let applied = await tickUntil(tick: { rig.executor.drain() }, until: { rig.pipeline.stats.effectsApplied == 1 })
        #expect(applied, "the effect pass was never taken")

        #expect(rig.pipeline.stats.framesReceived == 1)
        #expect(rig.pipeline.stats.framesSent == 1, "the discarding sink reports the frame as sent, not dropped as notConnected")
        #expect(rig.pipeline.stats.framesDropped == 0)
        #expect(rig.preview.presented.values.map(\.frame) == [request.output], "the preview is shown the effect's output")
        #expect(rig.surfaces.liveCount == 0, "with no view open the preview gives the frame back, and every lease ends")
        #expect(rig.errors.entries.count == 0)
        #expect(rig.developer.messages(in: .camera) == ["camera authorization: authorized"])
        #expect(rig.camera.descriptor == .hd720)
    }

    @Test("the window's view reaches the pipeline's preview, before or after the launch")
    func viewReachesThePreview() async throws {
        let rig = HarnessWiringRig()
        let early = FakePreviewTargetHandle()
        let late = FakePreviewTargetHandle()

        rig.session.attach(early)
        try await rig.launch()
        rig.session.attach(late)

        #expect(rig.preview.attached.map(ObjectIdentifier.init) == [ObjectIdentifier(early), ObjectIdentifier(late)])
        #expect(rig.developer.messages(in: .preview) == ["preview window attached", "preview window attached"])
    }

    @Test("stopping the session stops the camera and the scheduler")
    func stopEndsThePipeline() async throws {
        let rig = HarnessWiringRig()
        try await rig.launch()
        #expect(rig.camera.isRunning)
        #expect(rig.scheduler.isRunning)

        rig.session.stop()

        #expect(rig.camera.isRunning == false)
        #expect(rig.scheduler.isRunning == false)
    }

    @Test("a camera that is not granted starts no pipeline and says why")
    func deniedCameraStartsNothing() async {
        let rig = HarnessWiringRig(answer: .denied)

        rig.session.start()
        await rig.errors.entries.waitForCount(1)

        #expect(rig.camera.startCount == 0)
        #expect(rig.scheduler.isRunning == false)
        #expect(rig.errors.messages(in: .camera).first?.hasPrefix("camera access not granted (denied)") == true)
    }
}

/// A `HarnessSession` over the real interactor and pipeline, and fakes for everything below.
@MainActor
private struct HarnessWiringRig {
    let camera = FakeCameraRepository()
    let preview = InMemoryPreviewSink(holding: .onceAttached)
    let surfaces = FakeSurfaceRepository()
    let effects = FakeEffectRuntimeRepository()
    let executor = ManualFrameExecutor()
    let scheduler = ManualFrameScheduler()
    let work = RecordingWorkRunner()
    let errors = RecordingLog()
    let developer = RecordingLog()
    let pipeline: FramePipelineUseCaseImpl
    let session: HarnessSession

    init(answer: CameraAuthorizationStatus = .authorized) {
        let camera = camera
        let preview = preview
        let surfaces = surfaces
        let effects = effects
        let executor = executor
        let scheduler = scheduler
        let work = work
        let errors = errors
        let developer = developer
        let permission = FakeCameraControlUseCase(decision: answer)
        // Each layer is built inside the scope of the one below it, as the live graph resolves.
        (pipeline, session) = withDependencies {
            $0.cameraRepository = camera
            $0.previewSink = preview
            $0.surfaceRepository = surfaces
            $0.effectRuntimeRepository = effects
            $0.frameExecutor = executor
            $0.frameScheduler = scheduler
            $0.workRunner = work
            $0.cameraControlUseCase = permission
            $0.errorLog = errors
            $0.developerLog = developer
            $0.useDiscardingVirtualCameraSink()
        } operation: {
            let pipeline = FramePipelineUseCaseImpl()
            return withDependencies {
                $0.framePipelineUseCase = pipeline
            } operation: {
                withDependencies {
                    $0.harnessInteractor = HarnessInteractorImpl()
                } operation: {
                    (pipeline, HarnessSession())
                }
            }
        }
    }

    /// Starts the session and drains the executor until the interactor has started the
    /// pipeline (it logs that last).
    func launch() async throws {
        session.start()
        let started = await tickUntil(tick: { executor.drain() }, until: { developer.contains("pipeline started") })
        try #require(started, "the launch never reached the pipeline")
    }
}
