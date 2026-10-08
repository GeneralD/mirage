import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import ExtensionInstallDataSource

@Suite("ExtensionInstallDataSourceImpl", .timeLimit(.minutes(1)))
struct ExtensionInstallDataSourceTests {
    private let gateway = AnnouncingGateway()
    private let log = RecordingLog()

    private func makeSubject() -> ExtensionInstallDataSourceImpl {
        withDependencies {
            $0.systemExtensionGateway = gateway
            $0.developerLog = log
        } operation: {
            ExtensionInstallDataSourceImpl()
        }
    }

    private func drain(_ stream: AsyncStream<InstallStatus>) async -> [InstallStatus] {
        await stream.reduce(into: []) { $0.append($1) }
    }

    @Test("starts out not installed")
    func initialStatus() async {
        #expect(await makeSubject().status == .notInstalled)
    }

    @Test("happy path goes installing then installed and requests the extension bundle")
    func happyPath() async {
        let subject = makeSubject()
        let stream = await subject.install()
        #expect(await subject.status == .installing)
        await gateway.activated.waitForCount(1)
        gateway.emit(.completed)
        #expect(await drain(stream) == [.installing, .installed])
        #expect(await subject.status == .installed)
        #expect(gateway.activations.values == [ProductIdentity.extensionBundleID])
    }

    @Test("completing after a reboot still counts as installed")
    func completesAfterReboot() async {
        let subject = makeSubject()
        let stream = await subject.install()
        await gateway.activated.waitForCount(1)
        gateway.emit(.completesAfterReboot)
        #expect(await drain(stream) == [.installing, .installed])
    }

    @Test("approval path reports needsApproval before installed, and status follows each step")
    func approvalPath() async {
        let subject = makeSubject()
        var iterator = await subject.install().makeAsyncIterator()
        #expect(await iterator.next() == .installing)
        await gateway.activated.waitForCount(1)
        gateway.emit(.needsApproval)
        #expect(await iterator.next() == .needsApproval)
        #expect(await subject.status == .needsApproval)
        gateway.emit(.completed)
        #expect(await iterator.next() == .installed)
        #expect(await subject.status == .installed)
        #expect(await iterator.next() == nil)
    }

    @Test("a failure carries the reason and ends the stream")
    func failurePath() async {
        let subject = makeSubject()
        let stream = await subject.install()
        await gateway.activated.waitForCount(1)
        gateway.emit(.failed(reason: "denied"))
        #expect(await drain(stream) == [.installing, .failed(reason: "denied")])
        #expect(await subject.status == .failed(reason: "denied"))
    }

    @Test("a gateway stream that ends without a result fails instead of hanging")
    func endedWithoutResult() async {
        let subject = makeSubject()
        let stream = await subject.install()
        await gateway.activated.waitForCount(1)
        gateway.finish()
        let reason = "activation ended without a result"
        #expect(await drain(stream) == [.installing, .failed(reason: reason)])
        #expect(await subject.status == .failed(reason: reason))
    }

    @Test("a gateway stream that ends while approval is pending also fails")
    func endedWhileAwaitingApproval() async {
        let subject = makeSubject()
        let stream = await subject.install()
        await gateway.activated.waitForCount(1)
        gateway.emit(.needsApproval)
        gateway.finish()
        #expect(await drain(stream).last == .failed(reason: "activation ended without a result"))
    }

    @Test("events after the terminal one are ignored")
    func ignoresEventsAfterTerminal() async {
        let subject = makeSubject()
        let stream = await subject.install()
        await gateway.activated.waitForCount(1)
        gateway.emit(.completed)
        gateway.emit(.failed(reason: "late"))
        #expect(await drain(stream) == [.installing, .installed])
        #expect(await subject.status == .installed)
    }

    @Test("install after installed replays installed without a new activation")
    func installedIsSticky() async {
        let subject = makeSubject()
        let first = await subject.install()
        await gateway.activated.waitForCount(1)
        gateway.emit(.completed)
        _ = await drain(first)
        #expect(await drain(await subject.install()) == [.installed])
        #expect(gateway.activations.count == 1)
    }

    @Test("install after a failure submits a fresh request")
    func retryAfterFailure() async {
        let subject = makeSubject()
        let first = await subject.install()
        await gateway.activated.waitForCount(1)
        gateway.emit(.failed(reason: "boom"))
        _ = await drain(first)

        let second = await subject.install()
        await gateway.activated.waitForCount(2)
        gateway.emit(.completed)
        #expect(await drain(second) == [.installing, .installed])
        #expect(gateway.activations.count == 2)
    }

    @Test("a second install while approval is pending joins the request and sees the terminal status")
    func concurrentInstallsShareOneActivation() async {
        let subject = makeSubject()
        var first = await subject.install().makeAsyncIterator()
        await gateway.activated.waitForCount(1)
        gateway.emit(.needsApproval)
        #expect(await first.next() == .installing)
        #expect(await first.next() == .needsApproval)

        let second = await subject.install()
        gateway.emit(.completed)

        #expect(await first.next() == .installed)
        #expect(await first.next() == nil)
        #expect(await drain(second) == [.needsApproval, .installed])
        #expect(gateway.activations.count == 1)
    }

    @Test("a second install right after the first replays installing and shares the activation")
    func joinsBeforeAnyGatewayEvent() async {
        let subject = makeSubject()
        let first = await subject.install()
        let second = await subject.install()
        await gateway.activated.waitForCount(1)
        gateway.emit(.completed)
        #expect(await drain(first) == [.installing, .installed])
        #expect(await drain(second) == [.installing, .installed])
        #expect(gateway.activations.count == 1)
    }

    @Test("every transition is logged for developers")
    func logsTransitions() async {
        let subject = makeSubject()
        let stream = await subject.install()
        await gateway.activated.waitForCount(1)
        gateway.emit(.needsApproval)
        gateway.emit(.completed)
        _ = await drain(stream)
        let messages = log.messages(in: .install)
        #expect(messages.count == 3)
        #expect(messages.allSatisfy { $0.contains("extension install status") })
    }
}
