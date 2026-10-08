import Dependencies

/// `CameraPermissionDataSource`: the TCC state, and the one-time request that
/// turns `notDetermined` into a decision.
public protocol CameraPermission: Sendable {
    func status() -> CameraAuthorizationStatus
    /// Prompts only when the status is `notDetermined`; otherwise returns the
    /// existing decision without showing anything.
    func request() async -> CameraAuthorizationStatus
}

public enum CameraPermissionKey: TestDependencyKey {
    public static let testValue: any CameraPermission = UnimplementedCameraPermission()
}

extension DependencyValues {
    public var cameraPermission: any CameraPermission {
        get { self[CameraPermissionKey.self] }
        set { self[CameraPermissionKey.self] = newValue }
    }
}

private struct UnimplementedCameraPermission: CameraPermission {
    func status() -> CameraAuthorizationStatus {
        reportIssue("CameraPermission.status not implemented")
        return .denied
    }

    func request() async -> CameraAuthorizationStatus {
        reportIssue("CameraPermission.request not implemented")
        return .denied
    }
}
