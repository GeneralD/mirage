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
}
