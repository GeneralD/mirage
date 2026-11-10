import Dependencies

/// The cameras the user can pick from: the OS's camera list without this app's own virtual
/// camera, sorted for display. Each camera's capture formats come through unchanged, and a
/// signal says when the set of attached cameras has changed.
public protocol CameraDevices: Sendable {
    func devices() -> [CameraDevice]
    func formats(ofDevice id: String) -> [CameraFormat]
    /// A signal that the set of attached cameras changed. The value carries nothing: on each
    /// element, read `devices()` again.
    func changes() -> AsyncStream<Void>
}

public enum CameraDevicesKey: TestDependencyKey {
    public static let testValue: any CameraDevices = UnimplementedCameraDevices()
}

extension DependencyValues {
    public var cameraDevices: any CameraDevices {
        get { self[CameraDevicesKey.self] }
        set { self[CameraDevicesKey.self] = newValue }
    }
}

private struct UnimplementedCameraDevices: CameraDevices {
    func devices() -> [CameraDevice] {
        reportIssue("CameraDevices.devices not implemented")
        return []
    }

    func formats(ofDevice id: String) -> [CameraFormat] {
        reportIssue("CameraDevices.formats not implemented")
        return []
    }

    func changes() -> AsyncStream<Void> {
        reportIssue("CameraDevices.changes not implemented")
        return AsyncStream<Void> { $0.finish() }
    }
}
