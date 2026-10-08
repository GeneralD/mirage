import Dependencies
import Domain

/// Camera permission policy: ask once while the status is `notDetermined`, and
/// hand back any decision that already exists without showing a prompt again.
public struct CameraControlUseCaseImpl: Sendable {
    @Dependency(\.cameraRepository) private var cameraRepository

    public init() {}
}

extension CameraControlUseCaseImpl: CameraControlUseCase {
    public func ensureAuthorized() async -> CameraAuthorizationStatus {
        let status = cameraRepository.authorizationStatus()
        guard status.canRequest else { return status }
        return await cameraRepository.requestAuthorization()
    }
}
