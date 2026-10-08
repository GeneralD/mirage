import Dependencies

/// Camera permission policy: `notDetermined` → ask once → the decision;
/// anything already decided is returned without prompting.
public protocol CameraControlUseCase: Sendable {
    func ensureAuthorized() async -> CameraAuthorizationStatus
}

public enum CameraControlUseCaseKey: TestDependencyKey {
    public static let testValue: any CameraControlUseCase = UnimplementedCameraControlUseCase()
}

extension DependencyValues {
    public var cameraControlUseCase: any CameraControlUseCase {
        get { self[CameraControlUseCaseKey.self] }
        set { self[CameraControlUseCaseKey.self] = newValue }
    }
}

private struct UnimplementedCameraControlUseCase: CameraControlUseCase {
    func ensureAuthorized() async -> CameraAuthorizationStatus {
        reportIssue("CameraControlUseCase.ensureAuthorized not implemented")
        return .denied
    }
}
