import CameraControlUseCase
import Dependencies
import Domain
import TestDoubles
import Testing

@Suite("CameraControlUseCase", .timeLimit(.minutes(1)))
struct CameraControlUseCaseTests {
    private func makeSubject(_ repository: FakeCameraRepository) -> CameraControlUseCaseImpl {
        withDependencies {
            $0.cameraRepository = repository
        } operation: {
            CameraControlUseCaseImpl()
        }
    }

    @Test("notDetermined asks once and returns the user's decision", arguments: [CameraAuthorizationStatus.authorized, .denied])
    func asksWhenUndecided(decision: CameraAuthorizationStatus) async {
        let repository = FakeCameraRepository(authorization: .notDetermined, requestDecision: decision)
        let status = await makeSubject(repository).ensureAuthorized()
        #expect(status == decision)
        #expect(repository.authorizationRequests.count == 1)
    }

    @Test("an existing decision is returned as is, without a prompt", arguments: [CameraAuthorizationStatus.authorized, .denied, .restricted])
    func keepsDecidedStatus(existing: CameraAuthorizationStatus) async {
        let repository = FakeCameraRepository(authorization: existing, requestDecision: .authorized)
        let status = await makeSubject(repository).ensureAuthorized()
        #expect(status == existing)
        #expect(repository.authorizationRequests.count == 0)
    }

    @Test("asking twice prompts only the first time")
    func promptsOnlyOnce() async {
        let repository = FakeCameraRepository(authorization: .notDetermined, requestDecision: .authorized)
        let subject = makeSubject(repository)
        _ = await subject.ensureAuthorized()
        let second = await subject.ensureAuthorized()
        #expect(second == .authorized)
        #expect(repository.authorizationRequests.count == 1)
    }
}
