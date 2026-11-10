import Dependencies
import Domain
import TestDoubles
import Testing

@testable import ExtensionInstallRepository

@Suite("ExtensionInstallRepositoryImpl", .timeLimit(.minutes(1)))
struct ExtensionInstallRepositoryTests {
    private func makeSubject(_ installer: FakeCameraExtensionInstaller) -> ExtensionInstallRepositoryImpl {
        withDependencies {
            $0.cameraExtensionInstaller = installer
        } operation: {
            ExtensionInstallRepositoryImpl()
        }
    }

    @Test("status forwards the installer's status")
    func statusForwards() async {
        let installer = FakeCameraExtensionInstaller(status: .needsApproval)
        #expect(await makeSubject(installer).status == .needsApproval)
    }

    @Test("install forwards the installer's transitions in order and calls it once")
    func installForwards() async {
        let installer = FakeCameraExtensionInstaller(script: [.installing, .needsApproval, .installed])
        let subject = makeSubject(installer)
        let statuses = await subject.install().reduce(into: [InstallStatus]()) { $0.append($1) }
        #expect(statuses == [.installing, .needsApproval, .installed])
        #expect(installer.installs.count == 1)
        #expect(await subject.status == .installed)
    }

    @Test("an empty installer stream stays empty")
    func emptyStream() async {
        let installer = FakeCameraExtensionInstaller(script: [])
        let statuses = await makeSubject(installer).install().reduce(into: [InstallStatus]()) { $0.append($1) }
        #expect(statuses.isEmpty)
    }

    @Test("updates streams the current status first, then the installer's transitions in order")
    func updatesStreamCurrentThenTransitions() async {
        let installer = FakeCameraExtensionInstaller(status: .needsApproval, script: [.installing, .installed])
        let subject = makeSubject(installer)
        let stream = await subject.updates()
        _ = await subject.install()
        installer.finishUpdates()
        let statuses = await stream.reduce(into: [InstallStatus]()) { $0.append($1) }
        #expect(statuses == [.needsApproval, .installing, .installed])
    }

    @Test("openApprovalSettings hands the pane to the installer and returns its answer")
    func openApprovalSettingsForwardsAnswer() async {
        let accepting = FakeCameraExtensionInstaller()
        #expect(await makeSubject(accepting).openApprovalSettings(.privacyAndSecurity) == true)
        #expect(accepting.openedPanes.values == [.privacyAndSecurity])

        let refusing = FakeCameraExtensionInstaller(opensSettings: false)
        #expect(await makeSubject(refusing).openApprovalSettings(.loginItemsAndExtensions) == false)
        #expect(refusing.openedPanes.values == [.loginItemsAndExtensions])
    }
}
