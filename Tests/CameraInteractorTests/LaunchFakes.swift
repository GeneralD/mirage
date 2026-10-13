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
