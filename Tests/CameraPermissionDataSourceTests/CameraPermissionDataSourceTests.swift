import CameraPermissionDataSource
import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("CameraPermissionDataSource", .timeLimit(.minutes(1)))
struct CameraPermissionDataSourceTests {
    private func makeSubject(_ gateway: any CameraAuthorizationGateway) -> CameraPermissionDataSourceImpl {
        withDependencies {
            $0.cameraAuthorizationGateway = gateway
        } operation: {
            CameraPermissionDataSourceImpl()
        }
    }

    @Test("status forwards the gateway's status", arguments: CameraAuthorizationStatus.allCases)
    func forwardsStatus(status: CameraAuthorizationStatus) {
        let subject = makeSubject(ScriptedCameraAuthorization(status: status))
        #expect(subject.status() == status)
    }

    @Test("notDetermined shows the prompt once and reports a grant")
    func requestGranted() async {
        let gateway = ScriptedCameraAuthorization(status: .notDetermined, grantsOnRequest: true)
        let status = await makeSubject(gateway).request()
        #expect(status == .authorized)
        #expect(gateway.requests.count == 1)
    }

    @Test("notDetermined shows the prompt once and reports a refusal")
    func requestDenied() async {
        let gateway = ScriptedCameraAuthorization(status: .notDetermined, grantsOnRequest: false)
        let status = await makeSubject(gateway).request()
        #expect(status == .denied)
        #expect(gateway.requests.count == 1)
    }

    @Test("a decided status is returned without showing the prompt", arguments: [CameraAuthorizationStatus.authorized, .denied, .restricted])
    func decidedStatusSkipsPrompt(existing: CameraAuthorizationStatus) async {
        let gateway = ScriptedCameraAuthorization(status: existing, grantsOnRequest: true)
        let status = await makeSubject(gateway).request()
        #expect(status == existing)
        #expect(gateway.requests.count == 0)
    }

    @Test(
        "the result is the re-read status, not the answer to the prompt",
        arguments: [(true, CameraAuthorizationStatus.restricted), (false, .authorized)]
    )
    func resultIsReReadStatus(answer: Bool, statusAfter: CameraAuthorizationStatus) async {
        let gateway = DisagreeingAuthorization(answer: answer, statusAfter: statusAfter)
        let status = await makeSubject(gateway).request()
        #expect(status == statusAfter)
        #expect(gateway.requests.count == 1)
    }

    @Test("requesting twice prompts only the first time")
    func secondRequestDoesNotPrompt() async {
        let gateway = ScriptedCameraAuthorization(status: .notDetermined, grantsOnRequest: false)
        let subject = makeSubject(gateway)
        _ = await subject.request()
        let second = await subject.request()
        #expect(second == .denied)
        #expect(gateway.requests.count == 1)
    }
}

/// A gateway whose prompt answer and post-prompt status disagree (a policy
/// change landing while the dialog is up), to prove the status is re-read.
private final class DisagreeingAuthorization: CameraAuthorizationGateway, Sendable {
    private let current: Locked<CameraAuthorizationStatus>
    private let answer: Bool
    private let statusAfter: CameraAuthorizationStatus
    let requests = Collector<Void>()

    init(answer: Bool, statusAfter: CameraAuthorizationStatus) {
        current = Locked(.notDetermined)
        self.answer = answer
        self.statusAfter = statusAfter
    }

    func status() -> CameraAuthorizationStatus { current.current }

    func requestAccess() async -> Bool {
        requests.append(())
        current.set(statusAfter)
        return answer
    }
}
