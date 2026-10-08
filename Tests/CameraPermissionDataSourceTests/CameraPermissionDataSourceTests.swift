import CameraPermissionDataSource
import Dependencies
import Domain
import TestDoubles
import Testing

@Suite("CameraPermissionDataSource", .timeLimit(.minutes(1)))
struct CameraPermissionDataSourceTests {
    private func makeSubject(_ gateway: ScriptedCameraAuthorization) -> CameraPermissionDataSourceImpl {
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
