import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import HarnessInteractor

@Suite("HarnessInteractorImpl", .timeLimit(.minutes(1)))
struct HarnessInteractorTests {
    // MARK: - Launch

    @Test("launch starts the solid frame at the descriptor and rate, then asks for the camera once")
    func launchOrder() async {
        let rig = HarnessInteractorRig()
        await rig.subject.launch(descriptor: .hd720, frameRate: .standard)

        #expect(rig.order.values == ["solid frame", "authorize"])
        #expect(rig.solidFrame.starts.values == [SolidFrameStart(descriptor: .hd720, frameRate: .standard)])
        #expect(rig.camera.asks.count == 1)
        #expect(rig.solidFrame.stops.count == 0)
    }

    @Test("a granted answer is logged for developers only")
    func grantedAnswer() async {
        let rig = HarnessInteractorRig(answer: .authorized)
        await rig.subject.launch(descriptor: .hd720, frameRate: .standard)

        #expect(rig.developerLog.messages(in: .camera) == ["camera authorization: authorized"])
        #expect(rig.errorLog.entries.count == 0)
    }

    @Test(
        "an answer that does not grant the camera is an error-log line too",
        arguments: [CameraAuthorizationStatus.denied, .restricted, .notDetermined, .unrecognized])
    func refusedAnswer(answer: CameraAuthorizationStatus) async {
        let rig = HarnessInteractorRig(answer: answer)
        await rig.subject.launch(descriptor: .hd720, frameRate: .standard)

        #expect(rig.developerLog.messages(in: .camera) == ["camera authorization: \(answer)"])
        #expect(rig.errorLog.messages(in: .camera).count == 1)
        #expect(rig.errorLog.messages(in: .camera).first?.hasPrefix("camera access not granted (\(answer))") == true)
    }

    @Test("the solid frame runs while the camera prompt is still open")
    func frameDoesNotWaitForThePrompt() async {
        let prompt = PromptLeftOpen()
        let rig = HarnessInteractorRig(camera: prompt)
        let launch = Task { await rig.subject.launch(descriptor: .hd720, frameRate: .standard) }
        await prompt.asks.waitForCount(1)

        #expect(rig.solidFrame.starts.count == 1)

        launch.cancel()
        await launch.value
    }

    @Test("an answer that arrives after the launch was cancelled is not reported")
    func cancelledLaunchReportsNothing() async {
        let prompt = PromptLeftOpen()
        let rig = HarnessInteractorRig(camera: prompt)
        let launch = Task { await rig.subject.launch(descriptor: .hd720, frameRate: .standard) }
        await prompt.asks.waitForCount(1)

        launch.cancel()
        await launch.value

        #expect(prompt.cancelled.count == 1, "the prompt saw the cancellation")
        #expect(rig.developerLog.messages(in: .camera).isEmpty)
        #expect(rig.errorLog.messages(in: .camera).isEmpty)
    }

    // MARK: - Attach

    @Test("attach hands the view to the solid frame's sink and logs it")
    func attachHandsTheViewOver() async {
        let rig = HarnessInteractorRig()
        let target = FakePreviewTargetHandle()
        await MainActor.run { rig.subject.attach(target) }

        #expect(rig.solidFrame.attached.values == [ObjectIdentifier(target)])
        #expect(rig.developerLog.messages(in: .preview) == ["preview window attached"])
        #expect(rig.errorLog.entries.count == 0)
    }

    @Test("a refused attach is logged, not thrown")
    func refusedAttachIsLogged() async {
        let rig = HarnessInteractorRig(attachRefusal: .foreignTarget)
        await MainActor.run { rig.subject.attach(FakePreviewTargetHandle()) }

        #expect(rig.solidFrame.attached.values.isEmpty)
        #expect(rig.errorLog.messages(in: .preview) == ["preview window not attached: \(PreviewError.foreignTarget)"])
        #expect(rig.developerLog.messages(in: .preview).isEmpty)
    }

    // MARK: - Shut down

    @Test("shutDown stops the solid frame")
    func shutDownStopsTheFrame() {
        let rig = HarnessInteractorRig()
        rig.subject.shutDown()

        #expect(rig.solidFrame.stops.count == 1)
        #expect(rig.camera.asks.count == 0)
    }
}

/// `HarnessInteractorImpl` over a recording `SolidFrameUseCase` and a camera
/// prompt that answers at once (or the one the test passes in).
private struct HarnessInteractorRig {
    let order = Collector<String>()
    let solidFrame: FakeSolidFrameUseCase
    /// The answering prompt; unused when the rig was given a prompt of its own.
    let camera: FakeCameraControlUseCase
    let errorLog = RecordingLog()
    let developerLog = RecordingLog()
    let subject: HarnessInteractorImpl

    init(
        answer: CameraAuthorizationStatus = .authorized,
        camera prompt: (any CameraControlUseCase)? = nil,
        attachRefusal: PreviewError? = nil
    ) {
        let solidFrame = FakeSolidFrameUseCase(attachRefusal: attachRefusal, order: order)
        let camera = FakeCameraControlUseCase(decision: answer, order: order)
        let (errorLog, developerLog) = (errorLog, developerLog)
        self.solidFrame = solidFrame
        self.camera = camera
        subject = withDependencies {
            $0.solidFrameUseCase = solidFrame
            $0.cameraControlUseCase = prompt ?? camera
            $0.errorLog = errorLog
            $0.developerLog = developerLog
        } operation: {
            HarnessInteractorImpl()
        }
    }
}

private struct SolidFrameStart: Equatable, Sendable {
    let descriptor: SurfaceDescriptor
    let frameRate: FrameRate
}

/// Records starts, stops and attaches; an attach throws the refusal it was given.
private final class FakeSolidFrameUseCase: SolidFrameUseCase, Sendable {
    let starts = Collector<SolidFrameStart>()
    let stops = Collector<Void>()
    let attached = Collector<ObjectIdentifier>()
    private let attachRefusal: PreviewError?
    private let order: Collector<String>

    init(attachRefusal: PreviewError?, order: Collector<String>) {
        self.attachRefusal = attachRefusal
        self.order = order
    }

    @MainActor
    func attach(_ target: any PreviewTargetHandle) throws {
        if let attachRefusal { throw attachRefusal }
        attached.append(ObjectIdentifier(target))
    }

    func start(descriptor: SurfaceDescriptor, frameRate: FrameRate) {
        order.append("solid frame")
        starts.append(SolidFrameStart(descriptor: descriptor, frameRate: frameRate))
    }

    func stop() {
        stops.append(())
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
