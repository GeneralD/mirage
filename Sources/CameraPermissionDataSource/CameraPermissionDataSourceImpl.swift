import Dependencies
import Domain

/// Turns the gateway's two raw answers (current status, "did the user grant")
/// into one `CameraAuthorizationStatus`. The system prompt is shown at most
/// once: only `notDetermined` reaches `requestAccess`, because asking again
/// after a decision is a silent no-op that would hide the real state.
public struct CameraPermissionDataSourceImpl: Sendable {
    @Dependency(\.cameraAuthorizationGateway) private var cameraAuthorizationGateway

    public init() {}
}

extension CameraPermissionDataSourceImpl: CameraPermission {
    public func status() -> CameraAuthorizationStatus {
        cameraAuthorizationGateway.status()
    }

    public func request() async -> CameraAuthorizationStatus {
        let current = cameraAuthorizationGateway.status()
        guard current.canRequest else { return current }
        _ = await cameraAuthorizationGateway.requestAccess()
        return cameraAuthorizationGateway.status()
    }
}
