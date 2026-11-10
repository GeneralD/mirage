import Dependencies

/// Thin pass-through to the OS's camera list (live: `AVCaptureDevice`): which cameras are
/// attached, and which capture formats each one offers. Which camera the user picks, and
/// what a format means for that choice, is decided one layer up.
public protocol CameraDeviceGateway: Sendable {
    func devices() -> [CameraDevice]
    func formats(ofDevice id: String) -> [CameraFormat]
    /// A signal that a camera was connected or disconnected. The value carries nothing: on each
    /// element, read `devices()` again.
    func changes() -> AsyncStream<Void>
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

    func changes() -> AsyncStream<Void> {
        reportIssue("CameraDeviceGateway.changes not implemented")
        return AsyncStream<Void> { $0.finish() }
    }
}
