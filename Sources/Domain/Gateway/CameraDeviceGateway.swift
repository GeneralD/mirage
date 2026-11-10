import Dependencies

/// Thin pass-through to the OS's camera list (live: `AVCaptureDevice`): which cameras are
/// attached, and which capture formats each one offers. Which camera the user picks, and
/// what a format means for that choice, is decided one layer up.
public protocol CameraDeviceGateway: Sendable {
    func devices() -> [CameraDevice]
    func formats(ofDevice id: String) -> [CameraFormat]
}

public enum CameraDeviceGatewayKey: TestDependencyKey {
    public static let testValue: any CameraDeviceGateway = UnimplementedCameraDeviceGateway()
}

extension DependencyValues {
    public var cameraDeviceGateway: any CameraDeviceGateway {
        get { self[CameraDeviceGatewayKey.self] }
        set { self[CameraDeviceGatewayKey.self] = newValue }
    }
}

private struct UnimplementedCameraDeviceGateway: CameraDeviceGateway {
    func devices() -> [CameraDevice] {
        reportIssue("CameraDeviceGateway.devices not implemented")
        return []
    }

    func formats(ofDevice id: String) -> [CameraFormat] {
        reportIssue("CameraDeviceGateway.formats not implemented")
        return []
    }
}
