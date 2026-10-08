import Dependencies

/// Thin pass-through to `AVCaptureDevice.authorizationStatus` / `requestAccess`.
/// The notDetermined → request → authorized/denied policy lives above it.
public protocol CameraAuthorizationGateway: Sendable {
    func status() -> CameraAuthorizationStatus
    /// Shows the system prompt when the status is `notDetermined`; resolves with
    /// the user's answer (or the existing decision otherwise).
    func requestAccess() async -> Bool
}

public enum CameraAuthorizationGatewayKey: TestDependencyKey {
    public static let testValue: any CameraAuthorizationGateway = UnimplementedCameraAuthorizationGateway()
}

extension DependencyValues {
    public var cameraAuthorizationGateway: any CameraAuthorizationGateway {
        get { self[CameraAuthorizationGatewayKey.self] }
        set { self[CameraAuthorizationGatewayKey.self] = newValue }
    }
}

private struct UnimplementedCameraAuthorizationGateway: CameraAuthorizationGateway {
    func status() -> CameraAuthorizationStatus {
        reportIssue("CameraAuthorizationGateway.status not implemented")
        return .denied
    }

    func requestAccess() async -> Bool {
        reportIssue("CameraAuthorizationGateway.requestAccess not implemented")
        return false
    }
}
