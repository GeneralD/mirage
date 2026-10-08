import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import CameraInteractor

private struct StartFailure: Error {}

@Suite("CameraInteractorImpl", .timeLimit(.minutes(1)))
struct CameraInteractorTests {
    // Separate sinks so the error/developer routing is observable, not just the text.
    private let errorLog = RecordingLog()
    private let developerLog = RecordingLog()
    // Call order shared by the three use-case fakes.
    private let order = Collector<String>()

    private struct Rig {
        let install: FakeInstallUseCase
        let camera: FakeCameraControlUseCase
        let pipeline: FakeFramePipelineUseCase
        let subject: CameraInteractorImpl
    }

    private func makeRig(install: InstallStatus, authorization: CameraAuthorizationStatus, startFails: Bool = false) -> Rig {
        let installUseCase = FakeInstallUseCase(script: [.installing, install], outcome: install, order: order)
        let camera = FakeCameraControlUseCase(decision: authorization, order: order)
        let pipeline = FakeFramePipelineUseCase(failure: startFails ? StartFailure() : nil, order: order)
        let subject = withDependencies {
            $0.extensionInstallUseCase = installUseCase
            $0.cameraControlUseCase = camera
            $0.framePipelineUseCase = pipeline
            $0.errorLog = errorLog
            $0.developerLog = developerLog
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

    @Test("launch runs install, then authorization, then the pipeline start")
    func launchOrder() async {
        let rig = makeRig(install: .installed, authorization: .authorized)
        _ = await rig.subject.launch(descriptor: .hd720, frameRate: .standard)
        #expect(order.values == ["install", "authorize", "start"])
    }

    @Test("a failed install still authorizes but never starts")
    func launchOrderAfterFailedInstall() async {
        let rig = makeRig(install: .failed(reason: "denied"), authorization: .authorized)
        _ = await rig.subject.launch(descriptor: .hd720, frameRate: .standard)
        #expect(order.values == ["install", "authorize"])
    }

    @Test("every install status reaches the developer log and only a failure reaches the error log")
    func logsInstallProgress() async {
        let rig = makeRig(install: .failed(reason: "denied"), authorization: .denied)
        _ = await rig.subject.launch(descriptor: .hd720, frameRate: .standard)
        let progress = developerLog.messages(in: .install)
        #expect(progress.count == 2)
        #expect(progress.contains { $0.contains("installing") })
        #expect(errorLog.messages(in: .install).count == 1)
        #expect(errorLog.messages(in: .install).first?.contains("extension install failed: denied") == true)
        #expect(!developerLog.contains("extension install failed"))
    }

    @Test("a successful run logs nothing to the error log")
    func successLogsNoFailure() async {
        let rig = makeRig(install: .installed, authorization: .authorized)
        _ = await rig.subject.launch(descriptor: .hd720, frameRate: .standard)
        #expect(errorLog.entries.count == 0)
        #expect(developerLog.contains("pipeline started"))
    }

    @Test("the authorization decision is logged for developers only")
    func logsAuthorization() async {
        let rig = makeRig(install: .installed, authorization: .restricted)
        _ = await rig.subject.launch(descriptor: .hd720, frameRate: .standard)
        #expect(developerLog.messages(in: .camera).contains { $0.contains("restricted") })
        #expect(errorLog.messages(in: .camera).isEmpty)
    }

    @Test("a skipped pipeline logs why, for developers only")
    func logsSkipReason() async {
        let rig = makeRig(install: .failed(reason: "denied"), authorization: .denied)
        _ = await rig.subject.launch(descriptor: .hd720, frameRate: .standard)
        let skip = developerLog.messages(in: .pipeline)
        #expect(skip.count == 1)
        #expect(skip.first?.contains("pipeline not started") == true)
        #expect(skip.first?.contains("denied") == true)
        #expect(errorLog.messages(in: .pipeline).isEmpty)
    }

    @Test("a pipeline start failure goes to the error log only")
    func logsStartFailure() async {
        let rig = makeRig(install: .installed, authorization: .authorized, startFails: true)
        _ = await rig.subject.launch(descriptor: .hd720, frameRate: .standard)
        #expect(errorLog.messages(in: .pipeline).contains { $0.contains("pipeline failed to start") })
        #expect(!developerLog.contains("pipeline failed to start"))
        #expect(!developerLog.contains("pipeline started"))
    }

    @Test("shutDown stops the pipeline")
    func shutDownStops() {
        let rig = makeRig(install: .installed, authorization: .authorized)
        rig.subject.shutDown()
        #expect(rig.pipeline.stops.count == 1)
    }
}
