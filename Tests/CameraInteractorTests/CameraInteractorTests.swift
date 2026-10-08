import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import CameraInteractor

private struct StartFailure: Error {}

@Suite("CameraInteractorImpl", .timeLimit(.minutes(1)))
struct CameraInteractorTests {
    private let log = RecordingLog()

    private struct Rig {
        let install: FakeInstallUseCase
        let camera: FakeCameraControlUseCase
        let pipeline: FakeFramePipelineUseCase
        let subject: CameraInteractorImpl
    }

    private func makeRig(install: InstallStatus, authorization: CameraAuthorizationStatus, startFails: Bool = false) -> Rig {
        let installUseCase = FakeInstallUseCase(script: [.installing, install], outcome: install)
        let camera = FakeCameraControlUseCase(decision: authorization)
        let pipeline = FakeFramePipelineUseCase(failure: startFails ? StartFailure() : nil)
        let subject = withDependencies {
            $0.extensionInstallUseCase = installUseCase
            $0.cameraControlUseCase = camera
            $0.framePipelineUseCase = pipeline
            $0.errorLog = log
            $0.developerLog = log
        } operation: {
            CameraInteractorImpl()
        }
        return Rig(install: installUseCase, camera: camera, pipeline: pipeline, subject: subject)
    }

    /// Every install x authorization x start-outcome combination.
    private struct Scenario: Sendable {
        let install: InstallStatus
        let authorization: CameraAuthorizationStatus
        let startFails: Bool

        static let all: [Scenario] = [InstallStatus.installed, .failed(reason: "denied")].flatMap { install in
            CameraAuthorizationStatus.allCases.flatMap { authorization in
                [false, true].map { Scenario(install: install, authorization: authorization, startFails: $0) }
            }
        }
    }

    @Test("launch reports exactly what happened for every install x authorization x start outcome", arguments: Scenario.all)
    private func launchMatrix(scenario: Scenario) async {
        let (install, authorization, startFails) = (scenario.install, scenario.authorization, scenario.startFails)
        let rig = makeRig(install: install, authorization: authorization, startFails: startFails)
        let report = await rig.subject.launch(descriptor: .hd720, frameRate: .standard)

        let shouldStart = install.isInstalled && authorization.isGranted
        #expect(report == LaunchReport(install: install, authorization: authorization, pipelineStarted: shouldStart && !startFails))
        #expect(rig.install.installs.count == 1)
        #expect(rig.camera.asks.count == 1)
        #expect(rig.pipeline.starts.values == (shouldStart ? [.hd720] : []))
        #expect(rig.pipeline.rates.values == (shouldStart ? [.standard] : []))
    }

    @Test("camera permission is still requested when the install failed")
    func permissionAfterFailedInstall() async {
        let rig = makeRig(install: .failed(reason: "denied"), authorization: .authorized)
        _ = await rig.subject.launch(descriptor: .hd720, frameRate: .standard)
        #expect(rig.camera.asks.count == 1)
        #expect(rig.pipeline.starts.count == 0)
    }

    @Test("every install status reaches the developer log and a failure reaches the error log")
    func logsInstallProgress() async {
        let rig = makeRig(install: .failed(reason: "denied"), authorization: .denied)
        _ = await rig.subject.launch(descriptor: .hd720, frameRate: .standard)
        let messages = log.messages(in: .install)
        #expect(messages.contains { $0.contains("installing") })
        #expect(messages.contains { $0.contains("extension install failed: denied") })
    }

    @Test("a successful install logs no failure")
    func successLogsNoFailure() async {
        let rig = makeRig(install: .installed, authorization: .authorized)
        _ = await rig.subject.launch(descriptor: .hd720, frameRate: .standard)
        #expect(!log.contains("extension install failed"))
        #expect(log.contains("pipeline started"))
    }

    @Test("the authorization decision is logged")
    func logsAuthorization() async {
        let rig = makeRig(install: .installed, authorization: .restricted)
        _ = await rig.subject.launch(descriptor: .hd720, frameRate: .standard)
        #expect(log.messages(in: .camera).contains { $0.contains("restricted") })
    }

    @Test("a skipped pipeline logs why")
    func logsSkipReason() async {
        let rig = makeRig(install: .failed(reason: "denied"), authorization: .denied)
        _ = await rig.subject.launch(descriptor: .hd720, frameRate: .standard)
        let skip = log.messages(in: .pipeline)
        #expect(skip.count == 1)
        #expect(skip.first?.contains("pipeline not started") == true)
        #expect(skip.first?.contains("denied") == true)
    }

    @Test("a pipeline start failure goes to the error log")
    func logsStartFailure() async {
        let rig = makeRig(install: .installed, authorization: .authorized, startFails: true)
        _ = await rig.subject.launch(descriptor: .hd720, frameRate: .standard)
        #expect(log.contains("pipeline failed to start"))
    }

    @Test("shutDown stops the pipeline")
    func shutDownStops() {
        let rig = makeRig(install: .installed, authorization: .authorized)
        rig.subject.shutDown()
        #expect(rig.pipeline.stops.count == 1)
    }
}
