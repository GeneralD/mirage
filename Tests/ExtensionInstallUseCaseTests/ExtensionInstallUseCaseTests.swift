import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import ExtensionInstallUseCase

@Suite("ExtensionInstallUseCaseImpl", .timeLimit(.minutes(1)))
struct ExtensionInstallUseCaseTests {
    private func makeSubject(_ repository: FakeCameraExtensionInstaller) -> ExtensionInstallUseCaseImpl {
        withDependencies {
            $0.extensionInstallRepository = repository
        } operation: {
            ExtensionInstallUseCaseImpl()
        }
    }

    private func run(_ script: [InstallStatus]) async -> (result: InstallStatus, reported: [InstallStatus]) {
        let reported = Collector<InstallStatus>()
        let result = await makeSubject(FakeCameraExtensionInstaller(script: script)).install { reported.append($0) }
        return (result, reported.values)
    }

    @Test("reports every transition and returns installed")
    func installed() async {
        let (result, reported) = await run([.installing, .needsApproval, .installed])
        #expect(result == .installed)
        #expect(reported == [.installing, .needsApproval, .installed])
    }

    @Test("a failure is returned with its reason")
    func failed() async {
        let (result, reported) = await run([.installing, .failed(.denied)])
        #expect(result == .failed(.denied))
        #expect(reported == [.installing, .failed(.denied)])
    }

    @Test("reboot-required ends the install as its own terminal status, which is not installed")
    func rebootRequired() async {
        let (result, reported) = await run([.installing, .rebootRequired])
        #expect(result == .rebootRequired)
        #expect(!result.isInstalled)
        #expect(reported == [.installing, .rebootRequired])
    }

    @Test("an empty stream is a failure, not a stale status")
    func emptyStream() async {
        let (result, reported) = await run([])
        #expect(result == .failed(.other(code: -1, description: "no terminal status")))
        #expect(reported.isEmpty)
    }

    @Test("a stream that stops on a non-terminal status is a failure", arguments: [InstallStatus.notInstalled, .installing, .needsApproval])
    func endedNonTerminal(last: InstallStatus) async {
        let (result, reported) = await run([last])
        #expect(result == .failed(.other(code: -1, description: "no terminal status")))
        #expect(reported == [last])
    }

    @Test("status forwards the repository's status")
    func statusForwards() async {
        let repository = FakeCameraExtensionInstaller(status: .installed)
        #expect(await makeSubject(repository).status == .installed)
    }

    @Test("updates reports consecutive equal statuses as one")
    func updatesMergesConsecutiveDuplicates() async {
        let repository = FakeCameraExtensionInstaller(status: .installing, script: [.installing, .needsApproval])
        let subject = makeSubject(repository)
        let stream = await subject.updates()
        _ = await subject.install { _ in }
        repository.finishUpdates()
        let statuses = await stream.reduce(into: [InstallStatus]()) { $0.append($1) }
        #expect(statuses == [.installing, .needsApproval])
    }

    @Test("updates keeps a status that returns after another status")
    func updatesKeepsRepeatAfterOther() async {
        let repository = FakeCameraExtensionInstaller(status: .installing, script: [.needsApproval, .installing])
        let subject = makeSubject(repository)
        let stream = await subject.updates()
        _ = await subject.install { _ in }
        repository.finishUpdates()
        let statuses = await stream.reduce(into: [InstallStatus]()) { $0.append($1) }
        #expect(statuses == [.installing, .needsApproval, .installing])
    }

    @Test("updates always starts with the current status")
    func updatesStartsWithCurrentStatus() async {
        let repository = FakeCameraExtensionInstaller(status: .needsApproval, script: [])
        let stream = await makeSubject(repository).updates()
        repository.finishUpdates()
        let statuses = await stream.reduce(into: [InstallStatus]()) { $0.append($1) }
        #expect(statuses == [.needsApproval])
    }

    @Test("updates finishes when its source finishes")
    func updatesFinishesWithSource() async {
        let repository = FakeCameraExtensionInstaller(status: .notInstalled)
        let stream = await makeSubject(repository).updates()
        repository.finishUpdates()
        let statuses = await stream.reduce(into: [InstallStatus]()) { $0.append($1) }
        #expect(statuses == [.notInstalled])
    }

    @Test("openApprovalSettings hands the pane to the repository and returns its answer")
    func openApprovalSettingsForwardsAnswer() async {
        let accepting = FakeCameraExtensionInstaller()
        #expect(await makeSubject(accepting).openApprovalSettings(.privacyAndSecurity) == true)
        #expect(accepting.openedPanes.values == [.privacyAndSecurity])

        let refusing = FakeCameraExtensionInstaller(opensSettings: false)
        #expect(await makeSubject(refusing).openApprovalSettings(.loginItemsAndExtensions) == false)
        #expect(refusing.openedPanes.values == [.loginItemsAndExtensions])
    }
}
