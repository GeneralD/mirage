import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import ExtensionInstallDataSource

@Suite("ExtensionInstallDataSourceImpl", .timeLimit(.minutes(1)))
struct ExtensionInstallDataSourceTests {
    private let gateway = FakeSystemExtensionGateway()
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
        await gateway.activations.waitForCount(1)
        gateway.emit(.completed)
        #expect(await drain(stream) == [.installing, .installed])
        #expect(await subject.status == .installed)
        #expect(gateway.activations.values == [ProductIdentity.extensionBundleID])
    }

    @Test("completing after a reboot ends the install as reboot-required, not installed")
    func completesAfterReboot() async {
        let subject = makeSubject()
        let stream = await subject.install()
        await gateway.activations.waitForCount(1)
        gateway.emit(.completesAfterReboot)
        #expect(await drain(stream) == [.installing, .rebootRequired])
    }

    @Test("approval path reports needsApproval before installed, and status follows each step")
    func approvalPath() async {
        let subject = makeSubject()
        var iterator = await subject.install().makeAsyncIterator()
        #expect(await iterator.next() == .installing)
        await gateway.activations.waitForCount(1)
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
        await gateway.activations.waitForCount(1)
        gateway.emit(.failed(code: 99, description: "boom"))
        let failure = InstallStatus.failed(.other(code: 99, description: "boom"))
        #expect(await drain(stream) == [.installing, failure])
        #expect(await subject.status == failure)
    }

    @Test("a gateway stream that ends without a result fails instead of hanging")
    func endedWithoutResult() async {
        let subject = makeSubject()
        let stream = await subject.install()
        await gateway.activations.waitForCount(1)
        gateway.finish()
        let failure = InstallStatus.failed(.other(code: -1, description: "activation ended without a result"))
        #expect(await drain(stream) == [.installing, failure])
        #expect(await subject.status == failure)
    }

    @Test("a gateway stream that ends while approval is pending also fails")
    func endedWhileAwaitingApproval() async {
        let subject = makeSubject()
        let stream = await subject.install()
        await gateway.activations.waitForCount(1)
        gateway.emit(.needsApproval)
        gateway.finish()
        #expect(await drain(stream).last == .failed(.other(code: -1, description: "activation ended without a result")))
    }

    @Test("a system-policy refusal (code 10) is reported as denied")
    func needsApprovalThenDenied() async {
        let subject = makeSubject()
        let stream = await subject.install()
        await gateway.activations.waitForCount(1)
        gateway.emit(.needsApproval)
        gateway.emit(.failed(code: 10, description: "forbidden"))
        #expect(await drain(stream) == [.installing, .needsApproval, .failed(.denied)])
    }

    @Test("cancel and supersede codes (11, 12) are reported as canceled")
    func canceled() async {
        for code in [11, 12] {
            let subject = makeSubject()
            let stream = await subject.install()
            await gateway.activations.waitForCount(gateway.activations.count + 1)
            gateway.emit(.failed(code: code, description: "x"))
            #expect(await drain(stream).last == .failed(.canceled))
        }
    }

    @Test("a build problem keeps its code")
    func invalidBuild() async {
        let subject = makeSubject()
        let stream = await subject.install()
        await gateway.activations.waitForCount(1)
        gateway.emit(.failed(code: 9, description: "bad signature"))
        #expect(await drain(stream).last == .failed(.invalidBuild(code: 9)))
    }

    @Test("an unknown code keeps its description")
    func otherFailure() async {
        let subject = makeSubject()
        let stream = await subject.install()
        await gateway.activations.waitForCount(1)
        gateway.emit(.failed(code: 1, description: "unknown"))
        #expect(await drain(stream).last == .failed(.other(code: 1, description: "unknown")))
    }

    @Test("every documented system-extension error code maps to its class")
    func mappingTable() {
        let table: [(Int, InstallFailure)] = [
            (10, .denied), (11, .canceled), (12, .canceled),
            (2, .invalidBuild(code: 2)), (3, .invalidBuild(code: 3)), (4, .invalidBuild(code: 4)),
            (5, .invalidBuild(code: 5)), (8, .invalidBuild(code: 8)), (9, .invalidBuild(code: 9)),
            (1, .other(code: 1, description: "d")), (6, .other(code: 6, description: "d")),
            (7, .other(code: 7, description: "d")), (13, .other(code: 13, description: "d")),
        ]
        for (code, expected) in table {
            #expect(ExtensionInstallDataSourceImpl.failure(code: code, description: "d") == expected, "code \(code)")
        }
    }

    @Test("replacing an older build re-yields installing, then completes")
    func willReplaceExisting() async {
        let subject = makeSubject()
        let stream = await subject.install()
        await gateway.activations.waitForCount(1)
        gateway.emit(.willReplaceExisting)
        gateway.emit(.completed)
        #expect(await drain(stream) == [.installing, .installing, .installed])
        #expect(log.messages(in: .install).contains { $0.contains("replacing") })
    }

    @Test("replacing an older build after needsApproval keeps the approval status")
    func willReplaceAfterApprovalKeepsApproval() async {
        let subject = makeSubject()
        let stream = await subject.install()
        await gateway.activations.waitForCount(1)
        gateway.emit(.needsApproval)
        gateway.emit(.willReplaceExisting)
        gateway.emit(.completed)
        #expect(await drain(stream) == [.installing, .needsApproval, .installed])
    }

    @Test("a late event of a superseded request cannot change the new request")
    func supersededRequestIsIgnored() async {
        let subject = makeSubject()
        let first = await subject.install()
        await gateway.activations.waitForCount(1)
        gateway.emit(.failed(code: 1, description: "boom"), request: 0)
        _ = await drain(first)

        let second = await subject.install()
        await gateway.activations.waitForCount(2)
        gateway.emit(.completed, request: 0)
        gateway.emit(.failed(code: 1, description: "late"), request: 0)
        gateway.finish(request: 0)
        #expect(await subject.status == .installing)

        gateway.emit(.completed, request: 1)
        #expect(await drain(second) == [.installing, .installed])
        #expect(await subject.status == .installed)
    }

    @Test("a superseded request ending cannot fail the new request")
    func supersededEndIsIgnored() async {
        let subject = makeSubject()
        let first = await subject.install()
        await gateway.activations.waitForCount(1)
        gateway.emit(.failed(code: 1, description: "boom"), request: 0)
        _ = await drain(first)
        let second = await subject.install()
        await gateway.activations.waitForCount(2)
        gateway.finish(request: 0)
        gateway.emit(.completed, request: 1)
        #expect(await drain(second) == [.installing, .installed])
    }

    @Test("events after the terminal one are ignored")
    func ignoresEventsAfterTerminal() async {
        let subject = makeSubject()
        let stream = await subject.install()
        await gateway.activations.waitForCount(1)
        gateway.emit(.completed)
        gateway.emit(.failed(code: 1, description: "late"))
        #expect(await drain(stream) == [.installing, .installed])
        #expect(await subject.status == .installed)
    }

    @Test("install after installed replays installed without a new activation")
    func installedIsSticky() async {
        let subject = makeSubject()
        let first = await subject.install()
        await gateway.activations.waitForCount(1)
        gateway.emit(.completed)
        _ = await drain(first)
        #expect(await drain(await subject.install()) == [.installed])
        #expect(gateway.activations.count == 1)
    }

    @Test("install after a failure submits a fresh request")
    func retryAfterFailure() async {
        let subject = makeSubject()
        let first = await subject.install()
        await gateway.activations.waitForCount(1)
        gateway.emit(.failed(code: 1, description: "boom"))
        _ = await drain(first)

        let second = await subject.install()
        await gateway.activations.waitForCount(2)
        gateway.emit(.completed)
        #expect(await drain(second) == [.installing, .installed])
        #expect(gateway.activations.count == 2)
    }

    @Test("a second install while approval is pending joins the request and sees the terminal status")
    func concurrentInstallsShareOneActivation() async {
        let subject = makeSubject()
        var first = await subject.install().makeAsyncIterator()
        await gateway.activations.waitForCount(1)
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
        await gateway.activations.waitForCount(1)
        gateway.emit(.completed)
        #expect(await drain(first) == [.installing, .installed])
        #expect(await drain(second) == [.installing, .installed])
        #expect(gateway.activations.count == 1)
    }

    @Test("a consumer that stops reading is detached and the activation still reaches the others")
    func cancelledConsumerIsDetached() async {
        let subject = makeSubject()
        let survivor = await subject.install()
        await gateway.activations.waitForCount(1)
        do {
            var abandoned = await subject.install().makeAsyncIterator()
            #expect(await abandoned.next() == .installing)
            #expect(await subject.subscriberCount == 2)
        }
        #expect(await pollUntilSubscribers(subject, equal: 1))
        gateway.emit(.completed)
        #expect(await drain(survivor) == [.installing, .installed])
        #expect(await subject.status == .installed)
        #expect(gateway.activations.count == 1)
    }

    private func pollUntilSubscribers(_ subject: ExtensionInstallDataSourceImpl, equal target: Int) async -> Bool {
        // The count lives on the actor and is only readable, never announced, so yielding
        // between reads is the sole way to observe the detach hop.
        while !Task.isCancelled {
            guard await subject.subscriberCount != target else { return true }
            await Task.yield()
        }
        return false
    }

    @Test("every transition is logged for developers")
    func logsTransitions() async {
        let subject = makeSubject()
        let stream = await subject.install()
        await gateway.activations.waitForCount(1)
        gateway.emit(.needsApproval)
        gateway.emit(.completed)
        _ = await drain(stream)
        let messages = log.messages(in: .install)
        #expect(messages.count == 3)
        #expect(messages.allSatisfy { $0.contains("extension install status") })
    }
}
