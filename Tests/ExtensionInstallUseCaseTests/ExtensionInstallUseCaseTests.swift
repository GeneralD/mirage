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
        let (result, reported) = await run([.installing, .failed(reason: "denied")])
        #expect(result == .failed(reason: "denied"))
        #expect(reported == [.installing, .failed(reason: "denied")])
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
        #expect(result == .failed(reason: "no terminal status"))
        #expect(reported.isEmpty)
    }

    @Test("a stream that stops on a non-terminal status is a failure", arguments: [InstallStatus.notInstalled, .installing, .needsApproval])
    func endedNonTerminal(last: InstallStatus) async {
        let (result, reported) = await run([last])
        #expect(result == .failed(reason: "no terminal status"))
        #expect(reported == [last])
    }

    @Test("status forwards the repository's status")
    func statusForwards() async {
        let repository = FakeCameraExtensionInstaller(status: .installed)
        #expect(await makeSubject(repository).status == .installed)
    }
}
