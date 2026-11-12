import Dependencies
import Domain

/// The OS's camera list as the user sees it: this app's own virtual camera is left out, since
/// it cannot be the input of the camera it produces, and the rest is sorted by name, then id.
public struct CameraDevicesDataSourceImpl: Sendable {
    @Dependency(\.cameraDeviceGateway) private var cameraDeviceGateway

    public init() {}
}

extension CameraDevicesDataSourceImpl: CameraDevices {
    public func devices() -> [CameraDevice] {
        cameraDeviceGateway.devices()
            .filter { $0.id.lowercased() != ProductIdentity.virtualDeviceID.lowercased() }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    public func formats(ofDevice id: String) -> [CameraFormat] {
        cameraDeviceGateway.formats(ofDevice: id)
    }

    public func changes() -> AsyncStream<Void> {
        cameraDeviceGateway.changes()
    }
}
