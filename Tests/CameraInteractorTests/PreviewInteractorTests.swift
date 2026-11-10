import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import CameraInteractor

@Suite("PreviewInteractorImpl", .timeLimit(.minutes(1)))
struct PreviewInteractorTests {
    // MARK: - Attach

    @Test("attach hands the view to the pipeline once, returns attached, and logs it for developers only")
    func attachHandsTheViewOver() async {
        let rig = PreviewInteractorRig()
        let target = FakePreviewTargetHandle()
        let result = await MainActor.run { rig.subject.attach(target) }

        #expect(result == .attached)
        #expect(rig.pipeline.attached.values == [ObjectIdentifier(target)])
        #expect(rig.developerLog.messages(in: .preview) == ["preview pane attached"])
        #expect(rig.errorLog.entries.count == 0)
    }

    @Test("a foreign target is refused as foreignTarget, with one error line and no developer line")
    func foreignTargetIsRefused() async {
        let rig = PreviewInteractorRig(attachRefusal: .foreignTarget)
        let result = await MainActor.run { rig.subject.attach(FakePreviewTargetHandle()) }

        #expect(result == .refused(.foreignTarget))
        #expect(rig.pipeline.attached.values.isEmpty)
        #expect(rig.errorLog.messages(in: .preview) == ["preview pane not attached: foreignTarget"])
        #expect(rig.developerLog.entries.count == 0)
    }

    @Test("a missing GPU device is refused as noDevice, with one error line")
    func noDeviceIsRefused() async {
        let rig = PreviewInteractorRig(attachFailure: GPUError.noDevice)
        let result = await MainActor.run { rig.subject.attach(FakePreviewTargetHandle()) }

        #expect(result == .refused(.noDevice))
        #expect(rig.errorLog.messages(in: .preview) == ["preview pane not attached: noDevice"])
        #expect(rig.developerLog.entries.count == 0)
    }

    @Test("an error no refusal case names is refused as unavailable, and is logged with its own name")
    func otherErrorIsUnavailable() async {
        let rig = PreviewInteractorRig(attachFailure: GPUError.commandBufferUnavailable)
        let result = await MainActor.run { rig.subject.attach(FakePreviewTargetHandle()) }

        #expect(result == .refused(.unavailable))
        #expect(rig.pipeline.attached.values.isEmpty)
        #expect(rig.errorLog.messages(in: .preview) == ["preview pane not attached: commandBufferUnavailable"])
        #expect(rig.developerLog.entries.count == 0)
    }

    // MARK: - Detach

    @Test("detach hands the view to the pipeline's detachPreview once and logs it for developers only")
    func detachHandsTheViewBack() {
        let rig = PreviewInteractorRig()
        let target = FakePreviewTargetHandle()
        rig.subject.detach(target)

        #expect(rig.pipeline.detached.values == [ObjectIdentifier(target)])
        #expect(rig.developerLog.messages(in: .preview) == ["preview pane detached"])
        #expect(rig.errorLog.entries.count == 0)
    }

    @Test("detach keeps no state, so a second detach reaches the pipeline again")
    func secondDetachReachesThePipelineAgain() {
        let rig = PreviewInteractorRig()
        let target = FakePreviewTargetHandle()
        rig.subject.detach(target)
        rig.subject.detach(target)

        #expect(rig.pipeline.detached.values == [ObjectIdentifier(target), ObjectIdentifier(target)])
    }
}

/// `PreviewInteractorImpl` over a recording `FramePipelineUseCase` whose preview refuses or fails
/// as the test asks, and two separate log sinks so the error and developer routing is observable.
private struct PreviewInteractorRig {
    let errorLog: RecordingLog
    let developerLog: RecordingLog
    let pipeline: FakeFramePipelineUseCase
    let subject: PreviewInteractorImpl

    init(attachRefusal: PreviewError? = nil, attachFailure: (any Error)? = nil) {
        let errorLog = RecordingLog()
        let developerLog = RecordingLog()
        let pipeline = FakeFramePipelineUseCase(attachRefusal: attachRefusal, attachFailure: attachFailure)
        self.errorLog = errorLog
        self.developerLog = developerLog
        self.pipeline = pipeline
        subject = withDependencies {
            $0.framePipelineUseCase = pipeline
            $0.errorLog = errorLog
            $0.developerLog = developerLog
        } operation: {
            PreviewInteractorImpl()
        }
    }
}
