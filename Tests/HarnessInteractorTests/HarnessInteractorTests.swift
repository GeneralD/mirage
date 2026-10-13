import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import HarnessInteractor

@Suite("HarnessInteractorImpl", .timeLimit(.minutes(1)))
struct HarnessInteractorTests {
    // MARK: - Launch

    @Test("launch asks for the camera once, then starts the pipeline at the descriptor and rate")
    func launchOrder() async {
        let rig = HarnessInteractorRig()
        await rig.subject.launch(descriptor: .hd720, frameRate: .standard)

        #expect(rig.order.values == ["authorize", "start"])
        #expect(rig.camera.asks.count == 1)
        #expect(rig.pipeline.starts.values == [.hd720])
        #expect(rig.pipeline.rates.values == [.standard])
        #expect(rig.pipeline.stops.count == 0)
    }

    @Test("a granted answer and the started pipeline are logged for developers only")
    func grantedAnswer() async {
        let rig = HarnessInteractorRig(answer: .authorized)
        await rig.subject.launch(descriptor: .hd720, frameRate: .standard)

        #expect(rig.developerLog.messages(in: .camera) == ["camera authorization: authorized"])
        #expect(rig.developerLog.messages(in: .pipeline) == ["pipeline started"])
        #expect(rig.errorLog.entries.count == 0)
    }

    @Test(
        "an answer that does not grant the camera starts nothing and is an error-log line too",
        arguments: [CameraAuthorizationStatus.denied, .restricted, .notDetermined, .unrecognized])
    func refusedAnswer(answer: CameraAuthorizationStatus) async {
        let rig = HarnessInteractorRig(answer: answer)
        await rig.subject.launch(descriptor: .hd720, frameRate: .standard)

        #expect(rig.pipeline.starts.count == 0, "no camera, no pipeline")
        #expect(rig.developerLog.messages(in: .camera) == ["camera authorization: \(answer)"])
        #expect(rig.developerLog.messages(in: .pipeline).isEmpty)
        #expect(rig.errorLog.messages(in: .camera).count == 1)
        #expect(rig.errorLog.messages(in: .camera).first?.hasPrefix("camera access not granted (\(answer))") == true)
    }

    @Test("a pipeline that cannot start is an error-log line, and is not reported as started")
    func pipelineFailsToStart() async {
        let rig = HarnessInteractorRig(pipelineFailure: CaptureSessionError.deviceUnavailable)
        await rig.subject.launch(descriptor: .hd720, frameRate: .standard)

        #expect(rig.errorLog.messages(in: .pipeline) == ["pipeline failed to start: \(CaptureSessionError.deviceUnavailable)"])
        #expect(rig.developerLog.messages(in: .pipeline).isEmpty)
    }

    @Test("a pipeline start the caller cancelled is not an error")
    func cancelledStartIsSilent() async {
        let rig = HarnessInteractorRig(pipelineFailure: CancellationError())
        await rig.subject.launch(descriptor: .hd720, frameRate: .standard)

        #expect(rig.pipeline.starts.count == 1)
        #expect(rig.errorLog.entries.count == 0)
        #expect(rig.developerLog.messages(in: .pipeline).isEmpty)
    }

    @Test("the pipeline waits for the prompt: nothing starts while the camera question is open")
    func pipelineWaitsForThePrompt() async {
        let prompt = PromptLeftOpen()
        let rig = HarnessInteractorRig(camera: prompt)
        let launch = Task { await rig.subject.launch(descriptor: .hd720, frameRate: .standard) }
        await prompt.asks.waitForCount(1)

        #expect(rig.pipeline.starts.count == 0)

        launch.cancel()
        await launch.value
    }

    @Test("an answer that arrives after the launch was cancelled is not reported, and starts nothing")
    func cancelledLaunchReportsNothing() async {
        let prompt = PromptLeftOpen()
        let rig = HarnessInteractorRig(camera: prompt)
        let launch = Task { await rig.subject.launch(descriptor: .hd720, frameRate: .standard) }
        await prompt.asks.waitForCount(1)

        launch.cancel()
        await launch.value

        #expect(prompt.cancelled.count == 1, "the prompt saw the cancellation")
        #expect(rig.pipeline.starts.count == 0)
        #expect(rig.developerLog.entries.count == 0)
        #expect(rig.errorLog.entries.count == 0)
    }

    // MARK: - Attach

    @Test("attach hands the view to the pipeline's preview and logs it")
    func attachHandsTheViewOver() async {
        let rig = HarnessInteractorRig()
        let target = FakePreviewTargetHandle()
        await MainActor.run { rig.subject.attach(target) }

        #expect(rig.pipeline.attached.values == [ObjectIdentifier(target)])
        #expect(rig.developerLog.messages(in: .preview) == ["preview window attached"])
        #expect(rig.errorLog.entries.count == 0)
    }

    @Test("an attach before the launch is fine: the window may exist before the camera question is answered")
    func attachNeedsNoLaunch() async {
        let rig = HarnessInteractorRig()
        let target = FakePreviewTargetHandle()
        await MainActor.run { rig.subject.attach(target) }

        #expect(rig.pipeline.attached.count == 1)
        #expect(rig.pipeline.starts.count == 0)
        #expect(rig.camera.asks.count == 0)
    }

    @Test("a refused attach is logged, not thrown")
    func refusedAttachIsLogged() async {
        let rig = HarnessInteractorRig(attachRefusal: .foreignTarget)
        await MainActor.run { rig.subject.attach(FakePreviewTargetHandle()) }

        #expect(rig.pipeline.attached.values.isEmpty)
        #expect(rig.errorLog.messages(in: .preview) == ["preview window not attached: \(PreviewError.foreignTarget)"])
        #expect(rig.developerLog.messages(in: .preview).isEmpty)
    }

    // MARK: - Shut down

    @Test("shutDown stops the pipeline and asks nothing")
    func shutDownStopsThePipeline() {
        let rig = HarnessInteractorRig()
        rig.subject.shutDown()

        #expect(rig.pipeline.stops.count == 1)
        #expect(rig.camera.asks.count == 0)
        #expect(rig.pipeline.starts.count == 0)
    }
}

/// `HarnessInteractorImpl` over a recording `FramePipelineUseCase` and a camera
/// prompt that answers at once (or the one the test passes in). The extension
/// installer is deliberately not wired: it keeps its unimplemented default, so a
/// launch that reached for it would fail the test.
private struct HarnessInteractorRig {
    let order = Collector<String>()
    let pipeline: FakeFramePipelineUseCase
    /// The answering prompt; unused when the rig was given a prompt of its own.
    let camera: FakeCameraControlUseCase
    let errorLog = RecordingLog()
    let developerLog = RecordingLog()
    let subject: HarnessInteractorImpl

    init(
        answer: CameraAuthorizationStatus = .authorized,
        camera prompt: (any CameraControlUseCase)? = nil,
        pipelineFailure: (any Error)? = nil,
        attachRefusal: PreviewError? = nil
    ) {
        let pipeline = FakeFramePipelineUseCase(failure: pipelineFailure, attachRefusal: attachRefusal, order: order)
        let camera = FakeCameraControlUseCase(decision: answer, order: order)
        let (errorLog, developerLog) = (errorLog, developerLog)
        self.pipeline = pipeline
        self.camera = camera
        subject = withDependencies {
            $0.framePipelineUseCase = pipeline
            $0.cameraControlUseCase = prompt ?? camera
            $0.errorLog = errorLog
            $0.developerLog = developerLog
        } operation: {
            HarnessInteractorImpl()
        }
    }
}

/// A camera prompt the user never answers: `ensureAuthorized()` returns only
/// when its task is cancelled, and then with `.notDetermined`.
private final class PromptLeftOpen: CameraControlUseCase, Sendable {
    let asks = Collector<Void>()
    let cancelled = Collector<Void>()

    func ensureAuthorized() async -> CameraAuthorizationStatus {
        asks.append(())
        if await suspendUntilCancelled() { cancelled.append(()) }
        return .notDetermined
    }
}
