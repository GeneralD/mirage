import Domain
import TestSupport

/// Replays a scripted install flow through `onStatus` and returns the scripted
/// outcome, so the interactor is tested without the installer chain.
final class FakeInstallUseCase: ExtensionInstallUseCase, Sendable {
    private let script: [InstallStatus]
    private let outcome: InstallStatus
    let installs = Collector<Void>()
    private let order: Collector<String>

    init(script: [InstallStatus], outcome: InstallStatus, order: Collector<String> = Collector()) {
        self.script = script
        self.outcome = outcome
        self.order = order
    }

    var status: InstallStatus { outcome }

    func install(onStatus: @escaping @Sendable (InstallStatus) -> Void) async -> InstallStatus {
        installs.append(())
        order.append("install")
        for status in script { onStatus(status) }
        return outcome
    }
}

/// Records pipeline starts and stops; `start` throws when told to.
final class FakeFramePipelineUseCase: FramePipelineUseCase, Sendable {
    private let failure: (any Error)?
    let starts = Collector<SurfaceDescriptor>()
    let rates = Collector<FrameRate>()
    let stops = Collector<Void>()
    private let order: Collector<String>

    init(failure: (any Error)? = nil, order: Collector<String> = Collector()) {
        self.failure = failure
        self.order = order
    }

    var stats: PipelineStats { .empty }

    func start(descriptor: SurfaceDescriptor, frameRate: FrameRate) async throws {
        order.append("start")
        starts.append(descriptor)
        rates.append(frameRate)
        try failure.map { throw $0 }
    }

    func stop() {
        stops.append(())
    }
}
