import Dependencies
import Domain

/// The camera choice in one place: the cameras and their formats come from `CameraDevices`, the
/// stored choice from `CameraPreferences`, and the capture from `CameraSource`. Every method
/// forwards its call unchanged; turning a choice into a capture is the UseCase's policy.
public struct CameraSelectionRepositoryImpl: Sendable {
    @Dependency(\.cameraDevices) private var cameraDevices
    @Dependency(\.cameraPreferences) private var cameraPreferences
    @Dependency(\.cameraSource) private var cameraSource

    public init() {}
}

extension CameraSelectionRepositoryImpl: CameraSelectionRepository {
    public func devices() -> [CameraDevice] {
        cameraDevices.devices()
    }

    public func formats(ofDevice id: String) -> [CameraFormat] {
        cameraDevices.formats(ofDevice: id)
    }

    public func changes() -> AsyncStream<Void> {
        cameraDevices.changes()
    }

    public func storedSelection() -> CameraSelection {
        cameraPreferences.selection()
    }

    public func save(_ selection: CameraSelection) {
        cameraPreferences.save(selection)
    }

    public func apply(_ capture: CameraCapture) {
        cameraSource.configure(capture)
    }

    public func setMirrored(_ mirrored: Bool) {
        cameraSource.setMirrored(mirrored)
    }
}
