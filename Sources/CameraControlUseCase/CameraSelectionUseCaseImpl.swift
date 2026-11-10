import Dependencies
import Domain

/// Works out the camera state from the stored choice and the attached cameras, and hands the capture to the
/// camera source. It reads the choice and never saves it; saving belongs to the commands.
public struct CameraSelectionUseCaseImpl: Sendable {
    @Dependency(\.cameraSelectionRepository) private var cameraSelectionRepository
    @Dependency(\.developerLog) private var developerLog

    private let policy = CameraSelectionPolicy()

    public init() {}
}

extension CameraSelectionUseCaseImpl: CameraSelectionUseCase {
    public func refresh() -> CameraState {
        let state = resolved(cameraSelectionRepository.storedSelection())
        cameraSelectionRepository.setMirrored(state.isMirrored)
        switch state.availability {
        case .available:
            break
        case .missing(let name):
            developerLog.record(.camera, "camera not connected: \(name)")
        case .noCamera:
            developerLog.record(.camera, "no camera found")
        }
        return state
    }

    public func changes() -> AsyncStream<Void> {
        cameraSelectionRepository.changes()
    }
}

extension CameraSelectionUseCaseImpl {
    /// The state for a selection, with the capture applied to the camera source when there is a camera to capture.
    /// Only the chosen camera's formats are read, so the other cameras are not asked for theirs.
    private func resolved(_ selection: CameraSelection) -> CameraState {
        let devices = cameraSelectionRepository.devices()
        let camera = policy.device(among: devices, selection: selection)
        let formats = camera.map { cameraSelectionRepository.formats(ofDevice: $0.id) } ?? []
        let state = policy.state(devices: devices, formats: formats, selection: selection)
        if let capture = policy.capture(devices: devices, formats: formats, selection: selection) {
            cameraSelectionRepository.apply(capture)
        }
        return state
    }
}
