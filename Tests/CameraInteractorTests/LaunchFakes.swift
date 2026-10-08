import Domain
import TestSupport

/// Replays a scripted install flow through `onStatus` and returns the scripted
/// outcome, so the interactor is tested without the installer chain.
final class FakeInstallUseCase: ExtensionInstallUseCase, Sendable {
    private let script: [InstallStatus]
    private let outcome: InstallStatus
    let installs = Collector<Void>()

    init(script: [InstallStatus], outcome: InstallStatus) {
        self.script = script
        self.outcome = outcome
    }

    var status: InstallStatus { outcome }

    func install(onStatus: @escaping @Sendable (InstallStatus) -> Void) async -> InstallStatus {
        installs.append(())
        for status in script { onStatus(status) }
        return outcome
    }
}

/// Answers `ensureAuthorized()` with a fixed decision and counts the asks.
final class FakeCameraControlUseCase: CameraControlUseCase, Sendable {
    private let decision: CameraAuthorizationStatus
    let asks = Collector<Void>()

    init(decision: CameraAuthorizationStatus) {
        self.decision = decision
    }

    func ensureAuthorized() async -> CameraAuthorizationStatus {
        asks.append(())
        return decision
    }
}

/// Records pipeline starts and stops; `start` throws when told to.
final class FakeFramePipelineUseCase: FramePipelineUseCase, Sendable {
    private let failure: (any Error)?
    let starts = Collector<SurfaceDescriptor>()
    let rates = Collector<FrameRate>()
    let stops = Collector<Void>()

    init(failure: (any Error)? = nil) {
        self.failure = failure
    }

    var stats: PipelineStats { .empty }

    func start(descriptor: SurfaceDescriptor, frameRate: FrameRate) async throws {
        starts.append(descriptor)
        rates.append(frameRate)
        try failure.map { throw $0 }
    }

    func stop() {
        stops.append(())
    }
}
